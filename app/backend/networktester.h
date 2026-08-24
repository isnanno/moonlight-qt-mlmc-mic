#pragma once

#include <QObject>
#include <QStringList>
#include <QQmlEngine>

class ComputerManager;
class NvComputer;

class NetworkTester : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool hasResult READ hasResult NOTIFY resultChanged)
    Q_PROPERTY(int qualityTier READ qualityTier NOTIFY resultChanged)
    Q_PROPERTY(QString qualityLabel READ qualityLabel NOTIFY resultChanged)
    Q_PROPERTY(QString summaryText READ summaryText NOTIFY resultChanged)
    Q_PROPERTY(QString recommendationText READ recommendationText NOTIFY resultChanged)
    Q_PROPERTY(int recommendedWidth READ recommendedWidth NOTIFY resultChanged)
    Q_PROPERTY(int recommendedHeight READ recommendedHeight NOTIFY resultChanged)
    Q_PROPERTY(int recommendedFps READ recommendedFps NOTIFY resultChanged)
    Q_PROPERTY(int recommendedBitrateKbps READ recommendedBitrateKbps NOTIFY resultChanged)
    Q_PROPERTY(QStringList hostNames READ hostNames NOTIFY hostsChanged)
    Q_PROPERTY(int selectedHostIndex READ selectedHostIndex WRITE setSelectedHostIndex NOTIFY selectedHostIndexChanged)

public:
    static NetworkTester* get(QQmlEngine* qmlEngine = nullptr);

    bool busy() const { return m_Busy; }
    bool hasResult() const { return m_HasResult; }
    int qualityTier() const { return static_cast<int>(m_QualityTier); }
    QString qualityLabel() const { return m_QualityLabel; }
    QString summaryText() const { return m_SummaryText; }
    QString recommendationText() const { return m_RecommendationText; }
    int recommendedWidth() const { return m_RecommendedWidth; }
    int recommendedHeight() const { return m_RecommendedHeight; }
    int recommendedFps() const { return m_RecommendedFps; }
    int recommendedBitrateKbps() const { return m_RecommendedBitrateKbps; }
    QStringList hostNames() const { return m_HostNames; }
    int selectedHostIndex() const { return m_SelectedHostIndex; }
    void setSelectedHostIndex(int index);

    Q_INVOKABLE void refreshHosts(ComputerManager* computerManager);
    Q_INVOKABLE void startHostTest(ComputerManager* computerManager);
    Q_INVOKABLE void analyzeActiveStream();
    Q_INVOKABLE bool applyRecommendations();

    // Ctrl+Alt+Shift+N during a live stream: analyze, save prefs for next session, show overlay.
    void analyzeActiveStreamAndShowOverlay();

signals:
    void busyChanged();
    void resultChanged();
    void hostsChanged();
    void selectedHostIndexChanged();
    void testFailed(QString error);

private:
    enum class QualityTier {
        Excellent,
        Good,
        Fair,
        Poor
    };

    struct ProbeMetrics {
        bool reachable = false;
        bool fromLiveStream = false;
        double meanRttMs = 0;
        double rttVarianceMs = 0;
        float networkLossPct = -1.0f;
        float jitterPct = -1.0f;
        QString reachabilityLabel;
        bool isVpn = false;
        QString hostName;
        bool hasHevc = false;
        bool hasAv1 = false;
    };

    explicit NetworkTester(QQmlEngine* qmlEngine);

    void setBusy(bool busy);
    void clearResult();
    void finishWithMetrics(const ProbeMetrics& metrics);
    void computeRecommendations(const ProbeMetrics& metrics);
    QualityTier classifyQuality(const ProbeMetrics& metrics) const;
    static QString qualityTierToString(QualityTier tier);
    ProbeMetrics collectLiveStreamMetrics() const;
    ProbeMetrics probeHost(NvComputer* computer) const;

    static NetworkTester* s_Instance;

    QQmlEngine* m_QmlEngine;
    bool m_Busy = false;
    bool m_HasResult = false;
    QualityTier m_QualityTier = QualityTier::Poor;
    QString m_QualityLabel;
    QString m_SummaryText;
    QString m_RecommendationText;
    int m_RecommendedWidth = 1280;
    int m_RecommendedHeight = 720;
    int m_RecommendedFps = 60;
    int m_RecommendedBitrateKbps = 10000;
    int m_RecommendedPacketSize = 0;
    int m_RecommendedVideoCodec = 0; // StreamingPreferences::VCC_AUTO
    bool m_RecommendDisableYuv444 = false;
    double m_LastMeanRttMs = 0;
    QStringList m_HostNames;
    QVector<QString> m_HostUuids;
    int m_SelectedHostIndex = -1;
};
