#include "microphonepassthrough.h"

#include <Limelight.h>
#include <SDL.h>

#include <QHostAddress>
#include <QUdpSocket>
#include <QtEndian>

#include <cstring>

namespace {

constexpr int kSampleRate = 48000;
constexpr int kChannels = 1;
constexpr int kSamplesPerFrame = 480; // 10 ms @ 48 kHz
constexpr int kBytesPerSample = sizeof(Sint16);

#pragma pack(push, 1)
struct MicPassthroughHeader
{
    char magic[4];
    quint32 sequence;
    quint16 sampleRate;
    quint16 channels;
    quint16 bytesPerSample;
    quint16 payloadBytes;
};
#pragma pack(pop)

static_assert(sizeof(MicPassthroughHeader) == 16, "MicPassthroughHeader must be 16 bytes");

} // namespace

struct MicrophonePassthroughWorker::CaptureContext
{
    MicrophonePassthroughWorker* worker;
    SDL_AudioDeviceID device;
};

void MicrophonePassthroughWorker::captureCallback(void* userdata, unsigned char* stream, int len)
{
    auto* context = static_cast<CaptureContext*>(userdata);
    if (context != nullptr && context->worker != nullptr && stream != nullptr && len > 0) {
        context->worker->enqueueCapturedAudio(stream, len);
    }
}

MicrophonePassthroughWorker::MicrophonePassthroughWorker(const QString& hostAddress)
    : m_HostAddress(hostAddress),
      m_StopRequested(false),
      m_Sequence(0)
{
}

MicrophonePassthroughWorker::~MicrophonePassthroughWorker()
{
    requestStop();
    wait();
}

void MicrophonePassthroughWorker::requestStop()
{
    m_StopRequested = true;
}

void MicrophonePassthroughWorker::enqueueCapturedAudio(const unsigned char* data, int length)
{
    QMutexLocker locker(&m_BufferLock);

    if (m_PendingAudio.size() + length > k_MaxPendingBytes) {
        // Drop oldest data to keep latency bounded.
        const int overflow = (m_PendingAudio.size() + length) - k_MaxPendingBytes;
        m_PendingAudio.remove(0, overflow);
    }

    m_PendingAudio.append(reinterpret_cast<const char*>(data), length);
}

bool MicrophonePassthroughWorker::dequeueCapturedAudio(QByteArray& buffer)
{
    QMutexLocker locker(&m_BufferLock);

    const int frameBytes = kSamplesPerFrame * kChannels * kBytesPerSample;
    if (m_PendingAudio.size() < frameBytes) {
        return false;
    }

    buffer = m_PendingAudio.left(frameBytes);
    m_PendingAudio.remove(0, frameBytes);
    return true;
}

void MicrophonePassthroughWorker::run()
{
    if (m_HostAddress.isEmpty()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone passthrough disabled: empty host address");
        return;
    }

    QHostAddress destination(m_HostAddress);
    if (destination.isNull()) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Microphone passthrough disabled: invalid host address '%s'",
                     m_HostAddress.toUtf8().constData());
        return;
    }

    if (!SDL_WasInit(SDL_INIT_AUDIO)) {
        if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "Microphone passthrough disabled: SDL_InitSubSystem(SDL_INIT_AUDIO) failed: %s",
                         SDL_GetError());
            return;
        }
    }

    SDL_AudioSpec want, have;
    SDL_zero(want);
    want.freq = kSampleRate;
    want.format = AUDIO_S16SYS;
    want.channels = kChannels;
    want.samples = kSamplesPerFrame;
    want.callback = captureCallback;

    CaptureContext captureContext {};
    captureContext.worker = this;
    want.userdata = &captureContext;

    captureContext.device = SDL_OpenAudioDevice(nullptr, 1, &want, &have, 0);
    if (captureContext.device == 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Failed to open microphone capture device: %s",
                     SDL_GetError());
        return;
    }
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Microphone passthrough capture opened (%u Hz, %u channel(s), device %u)",
                have.freq,
                have.channels,
                captureContext.device);

    SDL_PauseAudioDevice(captureContext.device, 0);

    QUdpSocket socket;

    while (!m_StopRequested) {
        QByteArray pcmFrame;
        if (!dequeueCapturedAudio(pcmFrame)) {
            SDL_Delay(1);
            continue;
        }

        QByteArray datagram;
        datagram.resize(static_cast<int>(sizeof(MicPassthroughHeader)) + pcmFrame.size());

        auto* header = reinterpret_cast<MicPassthroughHeader*>(datagram.data());
        std::memcpy(header->magic, MIC_PASSTHROUGH_MAGIC, sizeof(header->magic));
        header->sequence = qToBigEndian(m_Sequence.fetch_add(1, std::memory_order_relaxed) + 1);
        header->sampleRate = qToBigEndian(static_cast<quint16>(have.freq));
        header->channels = qToBigEndian(static_cast<quint16>(have.channels));
        header->bytesPerSample = qToBigEndian(static_cast<quint16>(kBytesPerSample));
        header->payloadBytes = qToBigEndian(static_cast<quint16>(pcmFrame.size()));
        std::memcpy(datagram.data() + sizeof(MicPassthroughHeader),
                    pcmFrame.constData(),
                    pcmFrame.size());

        const qint64 sent = socket.writeDatagram(datagram,
                                                 destination,
                                                 MIC_PASSTHROUGH_PORT);
        if (sent != datagram.size()) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Microphone passthrough UDP send failed: %s",
                        socket.errorString().toUtf8().constData());
        }
    }

    SDL_PauseAudioDevice(captureContext.device, 1);
    SDL_CloseAudioDevice(captureContext.device);

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "Microphone passthrough stopped");
}

MicrophonePassthroughManager::MicrophonePassthroughManager(bool enabled, const QString& hostAddress)
    : m_Worker(nullptr)
{
    if (!enabled) {
        return;
    }

    m_Worker = new MicrophonePassthroughWorker(hostAddress);
    m_Worker->start();
}

MicrophonePassthroughManager::~MicrophonePassthroughManager()
{
    if (m_Worker != nullptr) {
        m_Worker->requestStop();
        m_Worker->wait();
        delete m_Worker;
        m_Worker = nullptr;
    }
}

bool MicrophonePassthroughManager::isActive() const
{
    return m_Worker != nullptr;
}
