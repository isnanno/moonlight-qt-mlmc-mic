#!/usr/bin/env python3
"""
Receptor UDP para Moonlight Parallel Microphone Passthrough (pacotes MLMC).

Layout do cabeçalho (16 bytes, big-endian), compatível com
app/streaming/audio/microphonepassthrough.cpp:

  magic[4]         = b"MLMC"
  sequence         = uint32 BE
  sample_rate      = uint16 BE
  channels         = uint16 BE
  bytes_per_sample = uint16 BE  (2 = PCM S16LE)
  payload_bytes    = uint16 BE
  payload          = PCM S16LE interleaved
"""

from __future__ import annotations

import argparse
import logging
import signal
import socket
import struct
import sys
import threading
import time
from dataclasses import dataclass
from typing import Optional, Tuple

import numpy as np
import sounddevice as sd

LOG = logging.getLogger("udp_audio")

UDP_MAX = 65507
HEADER_SIZE = 16
MAGIC = b"MLMC"
HEADER_STRUCT = struct.Struct("!4sIHHHH")

MOONLIGHT_RATE = 48000
MOONLIGHT_CHANNELS = 1
MOONLIGHT_FRAME_SAMPLES = 480  # 10 ms @ 48 kHz (kSamplesPerFrame no cliente)
MOONLIGHT_BYTES_PER_SAMPLE = 2


@dataclass
class MlmcPacket:
    sequence: int
    sample_rate: int
    channels: int
    bytes_per_sample: int
    payload: bytes


@dataclass
class SequenceStats:
    last_sequence: Optional[int] = None
    packets_ok: int = 0
    duplicates: int = 0
    out_of_order: int = 0
    gaps: int = 0
    missed_packets: int = 0
    invalid: int = 0

    def check(self, sequence: int) -> Tuple[bool, Optional[str]]:
        if self.last_sequence is None:
            self.last_sequence = sequence
            self.packets_ok += 1
            return True, None

        if sequence == self.last_sequence:
            self.duplicates += 1
            return False, "duplicate"

        expected = (self.last_sequence + 1) & 0xFFFFFFFF
        if sequence == expected:
            self.last_sequence = sequence
            self.packets_ok += 1
            return True, None

        delta = (sequence - expected) & 0xFFFFFFFF
        if delta > 0x80000000:
            self.out_of_order += 1
            return False, f"out_of_order (got {sequence}, expected {expected})"

        self.gaps += 1
        self.missed_packets += delta
        self.last_sequence = sequence
        self.packets_ok += 1
        return True, f"gap: missed {delta} packet(s)"


class NumpyRingBuffer:
    def __init__(self, capacity_samples: int) -> None:
        self._data = np.zeros(capacity_samples, dtype=np.int16)
        self._capacity = capacity_samples
        self._write = 0
        self._read = 0
        self._count = 0
        self._lock = threading.Lock()

    def __len__(self) -> int:
        with self._lock:
            return self._count

    def fill_ms(self, sample_rate: int) -> float:
        with self._lock:
            return self._count / sample_rate * 1000.0

    def write(self, samples: np.ndarray) -> int:
        flat = np.asarray(samples, dtype=np.int16).ravel()
        n = len(flat)
        if n == 0:
            return 0

        with self._lock:
            space = self._capacity - self._count
            to_write = min(n, space)
            dropped = n - to_write
            if to_write == 0:
                return dropped

            first = min(to_write, self._capacity - self._write)
            self._data[self._write : self._write + first] = flat[:first]
            remaining = to_write - first
            if remaining:
                self._data[:remaining] = flat[first:to_write]
            self._write = (self._write + to_write) % self._capacity
            self._count += to_write
            return dropped

    def read(self, n: int) -> np.ndarray:
        out = np.zeros(n, dtype=np.int16)
        with self._lock:
            to_read = min(n, self._count)
            if to_read == 0:
                return out

            first = min(to_read, self._capacity - self._read)
            out[:first] = self._data[self._read : self._read + first]
            remaining = to_read - first
            if remaining:
                out[first:to_read] = self._data[:remaining]
            self._read = (self._read + to_read) % self._capacity
            self._count -= to_read
        return out


def parse_mlmc_packet(data: bytes) -> Optional[MlmcPacket]:
    if len(data) < HEADER_SIZE:
        return None

    magic, sequence, sample_rate, channels, bytes_per_sample, payload_bytes = (
        HEADER_STRUCT.unpack_from(data, 0)
    )

    if magic != MAGIC:
        return None
    if bytes_per_sample != MOONLIGHT_BYTES_PER_SAMPLE:
        return None
    if channels < 1 or channels > 8:
        return None
    if sample_rate < 8000 or sample_rate > 192000:
        return None

    total_size = HEADER_SIZE + payload_bytes
    if len(data) < total_size:
        return None

    payload = data[HEADER_SIZE:total_size]
    if len(payload) != payload_bytes:
        return None

    frame_bytes = channels * bytes_per_sample
    if payload_bytes == 0 or payload_bytes % frame_bytes != 0:
        return None

    return MlmcPacket(
        sequence=sequence,
        sample_rate=sample_rate,
        channels=channels,
        bytes_per_sample=bytes_per_sample,
        payload=payload,
    )


def pcm_payload_to_numpy(packet: MlmcPacket) -> np.ndarray:
    samples = np.frombuffer(packet.payload, dtype=np.int16)
    if packet.channels == 1:
        return samples
    return samples.reshape(-1, packet.channels)


class UdpAudioServer:
    def __init__(
        self,
        host: str,
        port: int,
        device: Optional[int],
        priming_ms: int,
        buffer_ms: int,
        blocksize: int,
    ) -> None:
        self.host = host
        self.port = port
        self.device = device
        self.blocksize = blocksize
        self.seq_stats = SequenceStats()
        self.sample_rate = MOONLIGHT_RATE
        self.channels = MOONLIGHT_CHANNELS

        self._priming_samples = int(self.sample_rate * priming_ms / 1000)
        capacity = max(
            int(self.sample_rate * buffer_ms / 1000),
            self._priming_samples * 4,
        )
        self.buffer = NumpyRingBuffer(capacity)

        self._playback_enabled = False
        self._priming_logged = False
        self._stop = threading.Event()
        self._sock: Optional[socket.socket] = None
        self._stream: Optional[sd.OutputStream] = None
        self._dropped_samples = 0
        self._underruns = 0

    def _maybe_enable_playback(self) -> None:
        if self._playback_enabled:
            return
        fill = len(self.buffer)
        if fill >= self._priming_samples:
            self._playback_enabled = True
            if not self._priming_logged:
                self._priming_logged = True
                LOG.info(
                    "Pré-buffer pronto: %.0f ms — reprodução iniciada.",
                    fill / self.sample_rate * 1000,
                )

    def _audio_callback(
        self,
        outdata: np.ndarray,
        frames: int,
        _time_info,
        status: sd.CallbackFlags,
    ) -> None:
        if status.output_underflow and self._playback_enabled:
            self._underruns += 1

        if not self._playback_enabled:
            outdata.fill(0)
            return

        needed = frames * self.channels
        pcm = self.buffer.read(needed)
        if len(pcm) < needed:
            self._underruns += 1
            pcm = np.pad(pcm, (0, needed - len(pcm)))

        outdata[:] = pcm.reshape(frames, self.channels)

    def _handle_datagram(self, data: bytes, addr: tuple[str, int]) -> None:
        packet = parse_mlmc_packet(data)
        if packet is None:
            self.seq_stats.invalid += 1
            return

        if packet.sample_rate != self.sample_rate or packet.channels != self.channels:
            LOG.warning(
                "Stream mudou para %d Hz / %d ch (esperado %d / %d); reconfigure o cliente.",
                packet.sample_rate,
                packet.channels,
                self.sample_rate,
                self.channels,
            )
            self.sample_rate = packet.sample_rate
            self.channels = packet.channels

        ok, note = self.seq_stats.check(packet.sequence)
        if not ok:
            if note and note != "duplicate":
                LOG.debug("[%s] seq=%d: %s", addr[0], packet.sequence, note)
            return

        if note:
            LOG.info("[%s] seq=%d: %s", addr[0], packet.sequence, note)

        samples = pcm_payload_to_numpy(packet)
        dropped = self.buffer.write(samples)
        if dropped:
            self._dropped_samples += dropped
            LOG.warning("Buffer cheio: descartadas %d amostras", dropped)

        self._maybe_enable_playback()

    def _recv_loop(self) -> None:
        assert self._sock is not None
        while not self._stop.is_set():
            try:
                self._sock.settimeout(0.5)
                data, addr = self._sock.recvfrom(UDP_MAX)
            except socket.timeout:
                continue
            except OSError:
                if not self._stop.is_set():
                    LOG.exception("Erro ao receber UDP")
                break

            if data:
                self._handle_datagram(data, addr)

    def _stats_loop(self, interval: float) -> None:
        while not self._stop.is_set():
            time.sleep(interval)
            s = self.seq_stats
            LOG.info(
                "stats: ok=%d invalid=%d dup=%d ooo=%d gaps=%d missed=%d "
                "last_seq=%s underruns=%d drops=%d fill=%.0fms state=%s",
                s.packets_ok,
                s.invalid,
                s.duplicates,
                s.out_of_order,
                s.gaps,
                s.missed_packets,
                s.last_sequence,
                self._underruns,
                self._dropped_samples,
                self.buffer.fill_ms(self.sample_rate),
                "PLAY" if self._playback_enabled else "PRIME",
            )

    def start(self, stats_interval: float) -> None:
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 512 * 1024)
        self._sock.bind((self.host, self.port))

        dev = sd.query_devices(self.device, "output")
        LOG.info("Escutando MLMC/UDP em %s:%d", self.host, self.port)
        LOG.info("Saída: [%s] %s", dev["index"], dev["name"])
        LOG.info(
            "Esperado: %d Hz, mono, frames de %d amostras (10 ms)",
            MOONLIGHT_RATE,
            MOONLIGHT_FRAME_SAMPLES,
        )

        recv_thread = threading.Thread(target=self._recv_loop, name="udp-recv", daemon=True)
        stats_thread = threading.Thread(
            target=self._stats_loop, args=(stats_interval,), name="stats", daemon=True
        )
        recv_thread.start()
        stats_thread.start()

        self._stream = sd.OutputStream(
            device=self.device,
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype="int16",
            blocksize=self.blocksize,
            latency="low",
            callback=self._audio_callback,
        )
        self._stream.start()

        try:
            while not self._stop.is_set():
                time.sleep(0.2)
        except KeyboardInterrupt:
            LOG.info("Encerrando...")
        finally:
            self.stop()
            recv_thread.join(timeout=2)
            stats_thread.join(timeout=2)

    def stop(self) -> None:
        self._stop.set()
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        if self._sock is not None:
            self._sock.close()
            self._sock = None


def list_devices() -> None:
    print(sd.query_devices())
    default_out, _ = sd.default.device
    print(f"\nDispositivo de saída padrão (índice): {default_out}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Receptor Moonlight MLMC/UDP → sounddevice (Windows/Linux/macOS).",
    )
    parser.add_argument("--host", default="0.0.0.0", help="Interface de escuta")
    parser.add_argument("--port", type=int, default=9000, help="Porta UDP (padrão: 9000)")
    parser.add_argument("--device", type=int, default=None, help="Índice do dispositivo de saída")
    parser.add_argument("--priming-ms", type=int, default=50, help="Pré-buffer antes de reproduzir (ms)")
    parser.add_argument("--buffer-ms", type=int, default=300, help="Capacidade do buffer circular (ms)")
    parser.add_argument(
        "--blocksize",
        type=int,
        default=MOONLIGHT_FRAME_SAMPLES,
        help="Frames por callback de áudio",
    )
    parser.add_argument("--stats-interval", type=float, default=5.0, help="Intervalo de log de estatísticas")
    parser.add_argument("--list-devices", action="store_true", help="Lista dispositivos e sai")
    parser.add_argument("--log-file", default=None, help="Arquivo de log adicional")
    parser.add_argument("-v", "--verbose", action="store_true", help="Logs detalhados")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    if args.log_file:
        handlers.append(logging.FileHandler(args.log_file, encoding="utf-8"))

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
        handlers=handlers,
        force=True,
    )

    if args.list_devices:
        list_devices()
        return 0

    server = UdpAudioServer(
        host=args.host,
        port=args.port,
        device=args.device,
        priming_ms=args.priming_ms,
        buffer_ms=args.buffer_ms,
        blocksize=args.blocksize,
    )

    def handle_signal(_sig, _frame) -> None:
        server.stop()

    signal.signal(signal.SIGINT, handle_signal)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, handle_signal)

    server.start(stats_interval=args.stats_interval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
