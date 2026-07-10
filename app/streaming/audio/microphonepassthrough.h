#pragma once

#include <QByteArray>
#include <QMutex>
#include <QThread>
#include <QString>
#include <atomic>

#define MIC_PASSTHROUGH_PORT 9000
#define MIC_PASSTHROUGH_MAGIC "MLMC"

class MicrophonePassthroughWorker : public QThread
{
public:
    explicit MicrophonePassthroughWorker(const QString& hostAddress);
    ~MicrophonePassthroughWorker() override;

    void requestStop();

protected:
    void run() override;

private:
    struct CaptureContext;

    static void captureCallback(void* userdata, unsigned char* stream, int len);

    void enqueueCapturedAudio(const unsigned char* data, int length);
    bool dequeueCapturedAudio(QByteArray& buffer);

    QString m_HostAddress;
    std::atomic<bool> m_StopRequested;

    QMutex m_BufferLock;
    QByteArray m_PendingAudio;
    static constexpr int k_MaxPendingBytes = 48000 * 2 * 2; // ~1 s stereo @ 48 kHz

    std::atomic<uint32_t> m_Sequence;
};

// RAII helper — mirrors RichPresenceManager usage in Session::execInternal().
class MicrophonePassthroughManager
{
public:
    MicrophonePassthroughManager(bool enabled, const QString& hostAddress);
    ~MicrophonePassthroughManager();

    MicrophonePassthroughManager(const MicrophonePassthroughManager&) = delete;
    MicrophonePassthroughManager& operator=(const MicrophonePassthroughManager&) = delete;

    bool isActive() const;

private:
    MicrophonePassthroughWorker* m_Worker;
};
