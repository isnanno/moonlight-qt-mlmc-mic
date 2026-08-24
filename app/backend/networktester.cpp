#include "networktester.h"

#include "computermanager.h"
#include "nvcomputer.h"
#include "nvhttp.h"
#include "settings/streamingpreferences.h"
#include "streaming/session.h"

#include <Limelight.h>

#include <QElapsedTimer>
#include <QMetaObject>
#include <QReadLocker>
#include <QThreadPool>
#include <QtMath>

NetworkTester* NetworkTester::s_Instance = nullptr;

NetworkTester* NetworkTester::get(QQmlEngine* qmlEngine)
{
    if (s_Instance == nullptr) {
        s_Instance = new NetworkTester(qmlEngine);
    }
    return s_Instance;
}

NetworkTester::NetworkTester(QQmlEngine* qmlEngine)
    : QObject(qmlEngine),
      m_QmlEngine(qmlEngine)
{
}

void NetworkTester::setSelectedHostIndex(int index)
{
    if (m_SelectedHostIndex == index) {
        return;
    }
    m_SelectedHostIndex = index;
    emit selectedHostIndexChanged();
}

void NetworkTester::setBusy(bool busy)
{
    if (m_Busy == busy) {
        return;
    }
    m_Busy = busy;
    emit busyChanged();
}

void NetworkTester::clearResult()
{
    m_HasResult = false;
    m_QualityLabel.clear();
    m_SummaryText.clear();
    m_RecommendationText.clear();
    emit resultChanged();
}

void NetworkTester::refreshHosts(ComputerManager* computerManager)
{
    m_HostNames.clear();
    m_HostUuids.clear();

    if (computerManager == nullptr) {
        m_SelectedHostIndex = -1;
        emit hostsChanged();
        emit selectedHostIndexChanged();
        return;
    }

    const QVector<NvComputer*> computers = computerManager->getComputers();
    int preferredIndex = -1;

    for (int i = 0; i < computers.size(); i++) {
        NvComputer* computer = computers[i];
        QReadLocker locker(&computer->lock);

        QString label = computer->name;
        if (computer->state == NvComputer::CS_ONLINE) {
            label += QStringLiteral(" (Online)");
            if (preferredIndex < 0) {
                preferredIndex = i;
            }
        }
        else if (computer->state == NvComputer::CS_OFFLINE) {
            label += QStringLiteral(" (Offline)");
        }
        else {
            label += QStringLiteral(" (Unknown)");
        }

        m_HostNames.append(label);
        m_HostUuids.append(computer->uuid);
    }

    if (preferredIndex < 0 && !m_HostNames.isEmpty()) {
        preferredIndex = 0;
    }

    m_SelectedHostIndex = preferredIndex;
    emit hostsChanged();
    emit selectedHostIndexChanged();
}

NetworkTester::ProbeMetrics NetworkTester::probeHost(NvComputer* computer) const
{
    ProbeMetrics metrics;
    if (computer == nullptr) {
        return metrics;
    }

    QString name;
    int codecModes = 0;
    {
        QReadLocker locker(&computer->lock);
        name = computer->name;
        codecModes = computer->serverCodecModeSupport;
        if (computer->activeAddress.isNull()) {
            metrics.hostName = name;
            return metrics;
        }
    }

    metrics.hostName = name;
    metrics.hasHevc = (codecModes & SCM_HEVC) != 0;
    metrics.hasAv1 = (codecModes & SCM_AV1_MAIN8) != 0 || (codecModes & SCM_AV1_MAIN10) != 0;

    const NvComputer::ReachabilityType reachability = computer->getActiveAddressReachability();
    metrics.isVpn = (reachability == NvComputer::RI_VPN);
    switch (reachability) {
    case NvComputer::RI_LAN:
        metrics.reachabilityLabel = tr("LAN");
        break;
    case NvComputer::RI_VPN:
        metrics.reachabilityLabel = tr("VPN / tunnel");
        break;
    default:
        metrics.reachabilityLabel = tr("Unknown path");
        break;
    }

    QVector<qint64> samplesMs;
    samplesMs.reserve(5);

    for (int i = 0; i < 5; i++) {
        try {
            NvHTTP http(computer);
            QElapsedTimer timer;
            timer.start();
            http.getServerInfo(NvHTTP::NVLL_NONE, true);
            samplesMs.append(timer.elapsed());
        }
        catch (...) {
            // Keep going; partial samples are still useful.
        }
    }

    if (samplesMs.isEmpty()) {
        return metrics;
    }

    metrics.reachable = true;

    double sum = 0;
    for (qint64 sample : samplesMs) {
        sum += sample;
    }
    metrics.meanRttMs = sum / samplesMs.size();

    if (samplesMs.size() > 1) {
        double varSum = 0;
        for (qint64 sample : samplesMs) {
            const double delta = sample - metrics.meanRttMs;
            varSum += delta * delta;
        }
        metrics.rttVarianceMs = qSqrt(varSum / (samplesMs.size() - 1));
    }

    return metrics;
}

NetworkTester::ProbeMetrics NetworkTester::collectLiveStreamMetrics() const
{
    ProbeMetrics metrics;
    uint32_t rttMs = 0;
    uint32_t rttVarianceMs = 0;
    float networkLossPct = -1.0f;
    float jitterPct = -1.0f;
    QString hostName;
    bool isVpn = false;
    QString reachabilityLabel;

    if (!Session::fillLiveNetworkMetrics(rttMs, rttVarianceMs, networkLossPct, jitterPct,
                                         hostName, isVpn, reachabilityLabel)) {
        return metrics;
    }

    metrics.reachable = true;
    metrics.fromLiveStream = true;
    metrics.meanRttMs = rttMs;
    metrics.rttVarianceMs = rttVarianceMs;
    metrics.networkLossPct = networkLossPct;
    metrics.jitterPct = jitterPct;
    metrics.hostName = hostName;
    metrics.isVpn = isVpn;
    metrics.reachabilityLabel = reachabilityLabel;
    return metrics;
}

NetworkTester::QualityTier NetworkTester::classifyQuality(const ProbeMetrics& metrics) const
{
    int tier = static_cast<int>(QualityTier::Excellent);

    if (metrics.meanRttMs >= 80) {
        tier = static_cast<int>(QualityTier::Poor);
    }
    else if (metrics.meanRttMs >= 50) {
        tier = static_cast<int>(QualityTier::Fair);
    }
    else if (metrics.meanRttMs >= 25) {
        tier = static_cast<int>(QualityTier::Good);
    }

    if (metrics.rttVarianceMs > 70) {
        tier = static_cast<int>(QualityTier::Poor);
    }
    else if (metrics.rttVarianceMs > 40) {
        tier = qMax(tier, static_cast<int>(QualityTier::Fair));
    }

    if (metrics.networkLossPct >= 0) {
        if (metrics.networkLossPct > 3.0f || metrics.jitterPct > 3.0f) {
            tier = static_cast<int>(QualityTier::Poor);
        }
        else if (metrics.networkLossPct > 1.0f || metrics.jitterPct > 1.5f) {
            tier = qMax(tier, static_cast<int>(QualityTier::Fair));
        }
    }

    if (metrics.isVpn && tier < static_cast<int>(QualityTier::Poor)) {
        tier += 1;
    }

    return static_cast<QualityTier>(tier);
}

QString NetworkTester::qualityTierToString(QualityTier tier)
{
    switch (tier) {
    case QualityTier::Excellent:
        return tr("Excellent");
    case QualityTier::Good:
        return tr("Good");
    case QualityTier::Fair:
        return tr("Fair");
    case QualityTier::Poor:
    default:
        return tr("Poor");
    }
}

void NetworkTester::computeRecommendations(const ProbeMetrics& metrics)
{
    StreamingPreferences* prefs = StreamingPreferences::get();
    const QualityTier tier = classifyQuality(metrics);

    int width = prefs->width;
    int height = prefs->height;
    int fps = prefs->fps;

    auto clampRes = [&](int maxW, int maxH, int maxFps) {
        if (width * height > maxW * maxH) {
            width = maxW;
            height = maxH;
        }
        if (fps > maxFps) {
            fps = maxFps;
        }
    };

    float bitrateFactor = 1.0f;
    m_RecommendedVideoCodec = StreamingPreferences::VCC_AUTO;
    m_RecommendDisableYuv444 = false;

    switch (tier) {
    case QualityTier::Excellent:
        bitrateFactor = 1.0f;
        break;
    case QualityTier::Good:
        bitrateFactor = 0.85f;
        clampRes(1920, 1080, 120);
        break;
    case QualityTier::Fair:
        bitrateFactor = 0.55f;
        clampRes(1920, 1080, 60);
        m_RecommendDisableYuv444 = prefs->enableYUV444;
        if (metrics.hasHevc) {
            m_RecommendedVideoCodec = StreamingPreferences::VCC_FORCE_HEVC;
        }
        break;
    case QualityTier::Poor:
        bitrateFactor = 0.35f;
        clampRes(1280, 720, metrics.meanRttMs > 100 ? 30 : 60);
        m_RecommendDisableYuv444 = prefs->enableYUV444;
        if (metrics.hasAv1) {
            m_RecommendedVideoCodec = StreamingPreferences::VCC_FORCE_AV1;
        }
        else if (metrics.hasHevc) {
            m_RecommendedVideoCodec = StreamingPreferences::VCC_FORCE_HEVC;
        }
        break;
    }

    if (metrics.isVpn) {
        bitrateFactor *= 0.85f;
        m_RecommendedPacketSize = 1024;
    }
    else {
        m_RecommendedPacketSize = 0; // auto
    }

    const bool yuv444 = prefs->enableYUV444 && !m_RecommendDisableYuv444;
    int bitrate = qRound(StreamingPreferences::getDefaultBitrate(width, height, fps, yuv444) * bitrateFactor);
    bitrate = qBound(2000, bitrate, prefs->unlockBitrate ? 500000 : 150000);

    m_RecommendedWidth = width;
    m_RecommendedHeight = height;
    m_RecommendedFps = fps;
    m_RecommendedBitrateKbps = bitrate;
    m_LastMeanRttMs = metrics.meanRttMs;
    m_QualityTier = tier;
    m_QualityLabel = qualityTierToString(tier);

    QStringList summaryParts;
    summaryParts << tr("Host: %1").arg(metrics.hostName);
    summaryParts << tr("Path: %1").arg(metrics.reachabilityLabel.isEmpty()
                                           ? (metrics.fromLiveStream ? tr("Live stream") : tr("Unknown"))
                                           : metrics.reachabilityLabel);
    if (metrics.meanRttMs > 0) {
        summaryParts << tr("Latency: %1 ms (variance %2 ms)")
                            .arg(QString::number(metrics.meanRttMs, 'f', 0))
                            .arg(QString::number(metrics.rttVarianceMs, 'f', 0));
    }
    if (metrics.networkLossPct >= 0) {
        summaryParts << tr("Packet/frame loss: %1%").arg(QString::number(metrics.networkLossPct, 'f', 1));
    }
    if (metrics.jitterPct >= 0) {
        summaryParts << tr("Jitter drops: %1%").arg(QString::number(metrics.jitterPct, 'f', 1));
    }
    if (!metrics.fromLiveStream) {
        summaryParts << tr("Note: loss/jitter need an active stream (Ctrl+Alt+Shift+N).");
    }
    m_SummaryText = summaryParts.join('\n');

    QStringList recParts;
    recParts << tr("%1x%2 @ %3 FPS").arg(width).arg(height).arg(fps);
    recParts << tr("Bitrate: %1 Mbps").arg(QString::number(bitrate / 1000.0, 'f', 1));
    if (m_RecommendedPacketSize > 0) {
        recParts << tr("Packet size: %1 (VPN-safe)").arg(m_RecommendedPacketSize);
    }
    if (m_RecommendedVideoCodec == StreamingPreferences::VCC_FORCE_HEVC) {
        recParts << tr("Codec: HEVC (more efficient on weak links)");
    }
    else if (m_RecommendedVideoCodec == StreamingPreferences::VCC_FORCE_AV1) {
        recParts << tr("Codec: AV1 (more efficient on weak links)");
    }
    if (m_RecommendDisableYuv444) {
        recParts << tr("Disable YUV 4:4:4 (halves bandwidth need)");
    }
    m_RecommendationText = recParts.join('\n');
}

void NetworkTester::finishWithMetrics(const ProbeMetrics& metrics)
{
    if (!metrics.reachable) {
        clearResult();
        setBusy(false);
        emit testFailed(tr("Could not reach the selected host. Make sure it is online and reachable."));
        return;
    }

    computeRecommendations(metrics);
    m_HasResult = true;
    setBusy(false);
    emit resultChanged();
}

void NetworkTester::startHostTest(ComputerManager* computerManager)
{
    if (m_Busy) {
        return;
    }
    if (computerManager == nullptr || m_SelectedHostIndex < 0 ||
        m_SelectedHostIndex >= m_HostUuids.size()) {
        emit testFailed(tr("Select an online Moonlight host first."));
        return;
    }

    const QString uuid = m_HostUuids[m_SelectedHostIndex];
    NvComputer* computer = nullptr;
    for (NvComputer* candidate : computerManager->getComputers()) {
        QReadLocker locker(&candidate->lock);
        if (candidate->uuid == uuid) {
            computer = candidate;
            break;
        }
    }

    if (computer == nullptr) {
        emit testFailed(tr("Selected host is no longer available."));
        return;
    }

    clearResult();
    setBusy(true);

    QThreadPool::globalInstance()->start([this, computer]() {
        ProbeMetrics metrics = probeHost(computer);
        QMetaObject::invokeMethod(this, [this, metrics]() {
            finishWithMetrics(metrics);
        }, Qt::QueuedConnection);
    });
}

void NetworkTester::analyzeActiveStream()
{
    if (Session::get() == nullptr) {
        emit testFailed(tr("No active stream. Start streaming, then press Ctrl+Alt+Shift+N."));
        return;
    }

    clearResult();
    setBusy(true);
    finishWithMetrics(collectLiveStreamMetrics());
}

void NetworkTester::analyzeActiveStreamAndShowOverlay()
{
    Session* session = Session::get();
    if (session == nullptr) {
        return;
    }

    analyzeActiveStream();
    if (!m_HasResult) {
        QByteArray msg = tr("Network test failed — not enough stream stats yet.").toUtf8();
        session->getOverlayManager().updateOverlayText(Overlay::OverlayStatusUpdate, msg.constData());
        session->getOverlayManager().setOverlayState(Overlay::OverlayStatusUpdate, true);
        return;
    }

    applyRecommendations();

    const QString overlay =
        tr("Network: %1 | RTT ~%2 ms\nRecommended: %3x%4 @ %5 FPS, %6 Mbps\nSaved for next stream — reconnect to apply.")
            .arg(m_QualityLabel)
            .arg(QString::number(m_LastMeanRttMs, 'f', 0))
            .arg(m_RecommendedWidth)
            .arg(m_RecommendedHeight)
            .arg(m_RecommendedFps)
            .arg(QString::number(m_RecommendedBitrateKbps / 1000.0, 'f', 1));

    session->getOverlayManager().updateOverlayText(Overlay::OverlayStatusUpdate,
                                                   overlay.left(500).toUtf8().constData());
    session->getOverlayManager().setOverlayState(Overlay::OverlayStatusUpdate, true);
}

bool NetworkTester::applyRecommendations()
{
    if (!m_HasResult) {
        return false;
    }

    StreamingPreferences* prefs = StreamingPreferences::get();
    prefs->width = m_RecommendedWidth;
    prefs->height = m_RecommendedHeight;
    prefs->fps = m_RecommendedFps;
    prefs->bitrateKbps = m_RecommendedBitrateKbps;
    prefs->packetSize = m_RecommendedPacketSize;

    if (m_RecommendedVideoCodec != StreamingPreferences::VCC_AUTO) {
        prefs->videoCodecConfig = static_cast<StreamingPreferences::VideoCodecConfig>(m_RecommendedVideoCodec);
        emit prefs->videoCodecConfigChanged();
    }
    if (m_RecommendDisableYuv444 && prefs->enableYUV444) {
        prefs->enableYUV444 = false;
        emit prefs->enableYUV444Changed();
    }

    emit prefs->displayModeChanged();
    emit prefs->bitrateChanged();
    prefs->save();
    return true;
}
