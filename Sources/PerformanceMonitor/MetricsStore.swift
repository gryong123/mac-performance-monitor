import Combine
import Foundation

@MainActor
final class MetricsStore: ObservableObject {
    static let shared = MetricsStore()

    @Published private(set) var snapshot = MetricSnapshot.empty
    @Published private(set) var history: [HistoricalSample] = []
    @Published private(set) var healthLevel: HealthLevel = .normal
    @Published private(set) var isRefreshing = false
    @Published var isPanelVisible = true
    @Published var historyRange: HistoryRange = .hour {
        didSet { loadHistory() }
    }
    @Published var processSortMetric: ProcessSortMetric {
        didSet {
            defaults.set(processSortMetric.rawValue, forKey: "process.sortMetric")
        }
    }

    @Published var thresholds: AlertThresholds {
        didSet {
            defaults.set(thresholds.cpu, forKey: "threshold.cpu")
            defaults.set(thresholds.memory, forKey: "threshold.memory")
            defaults.set(thresholds.disk, forKey: "threshold.disk")
        }
    }

    private let provider: MetricsProvider
    private let historyStore: HistoryStore
    private let alertManager: AlertManager
    private let defaults = UserDefaults.standard
    private var timer: AnyCancellable?
    private var sampleCounter = 0

    private init(
        provider: MetricsProvider = SystemMetricsProvider(),
        historyStore: HistoryStore = HistoryStore(),
        alertManager: AlertManager = AlertManager()
    ) {
        self.provider = provider
        self.historyStore = historyStore
        self.alertManager = alertManager

        processSortMetric = ProcessSortMetric(
            rawValue: UserDefaults.standard.string(forKey: "process.sortMetric") ?? ""
        ) ?? .cpu
        let savedCPU = defaults.double(forKey: "threshold.cpu")
        let savedMemory = defaults.double(forKey: "threshold.memory")
        let savedDisk = defaults.double(forKey: "threshold.disk")
        thresholds = AlertThresholds(
            cpu: savedCPU > 0 ? savedCPU : AlertThresholds.defaults.cpu,
            memory: savedMemory > 0 ? savedMemory : AlertThresholds.defaults.memory,
            disk: savedDisk > 0 ? savedDisk : AlertThresholds.defaults.disk
        )
    }

    func start() {
        alertManager.requestAuthorization()
        historyStore.deleteOlderThanSevenDays()
        loadHistory()

        Task { await refresh() }
        timer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let newSnapshot = await provider.sample()
        snapshot = newSnapshot
        historyStore.upsertMinute(newSnapshot)
        healthLevel = alertManager.evaluate(snapshot: newSnapshot, thresholds: thresholds)
        isRefreshing = false

        sampleCounter += 1
        if sampleCounter % 30 == 0 {
            loadHistory()
            historyStore.deleteOlderThanSevenDays()
        }
    }

    func loadHistory() {
        let start = Date().addingTimeInterval(-historyRange.interval)
        historyStore.samples(since: start) { [weak self] samples in
            Task { @MainActor in
                self?.history = samples
            }
        }
    }
}
