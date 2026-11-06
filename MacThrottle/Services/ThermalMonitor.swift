import Foundation
import SwiftUI
import UserNotifications

@Observable
final class ThermalMonitor {
    // MARK: - Constants
    private static let historyDurationSeconds: TimeInterval = 600  // 10 minutes
    private static let pollIntervalSeconds: TimeInterval = 2.0

    // MARK: - CPU 温度阈值
    // 本地修改：除系统热压等级外，额外按 CPU 温度（M5 上为 11 个 CPU SMC 键的平均值）判定热压等级。
    // 采用滞回，避免温度在阈值附近抖动时状态来回跳变。
    /// 预警阈值：CPU 温度达到该值即进入「重度热压」
    static let warningTemperatureThreshold: Double = 90
    /// 预警解除阈值：已进入重度后，温度降回该值以下才退出
    static let warningReleaseTemperatureThreshold: Double = 88
    /// 严重阈值：CPU 温度达到该值即进入「临界热压」
    static let criticalTemperatureThreshold: Double = 97
    /// 严重解除阈值：已进入临界后，温度降回该值以下才退出
    static let criticalReleaseTemperatureThreshold: Double = 95

    // MARK: - State
    private(set) var pressure: ThermalPressure = .unknown
    private(set) var temperature: Double?
    private(set) var temperatureSource: String?  // SMC key or "HID"
    private(set) var fanSpeed: Double?  // Percentage 0-100%
    private(set) var hasFans: Bool = false
    private(set) var history: [HistoryEntry] = []
    private var timer: Timer?
    private var previousPressure: ThermalPressure = .unknown
    /// 温度判定等级（带滞回），与系统热压等级解耦
    private var temperaturePressure: ThermalPressure = .nominal

    // Notification settings
    var notifyOnHeavy: Bool = UserDefaults.standard.object(forKey: "notifyOnHeavy") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyOnHeavy, forKey: "notifyOnHeavy") }
    }

    var notifyOnCritical: Bool = UserDefaults.standard.object(forKey: "notifyOnCritical") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyOnCritical, forKey: "notifyOnCritical") }
    }

    var notifyOnRecovery: Bool = UserDefaults.standard.object(forKey: "notifyOnRecovery") as? Bool ?? false {
        didSet { UserDefaults.standard.set(notifyOnRecovery, forKey: "notifyOnRecovery") }
    }

    var notificationSound: Bool = UserDefaults.standard.object(forKey: "notificationSound") as? Bool ?? false {
        didSet { UserDefaults.standard.set(notificationSound, forKey: "notificationSound") }
    }

    // Graph settings
    var showFanSpeed: Bool = UserDefaults.standard.object(forKey: "showFanSpeed") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFanSpeed, forKey: "showFanSpeed") }
    }

    // Menu bar settings
    // swiftlint:disable:next line_length
    var showTemperatureInMenuBar: Bool = UserDefaults.standard.object(forKey: "showTemperatureInMenuBar") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showTemperatureInMenuBar, forKey: "showTemperatureInMenuBar") }
    }

    var timeInEachState: [(pressure: ThermalPressure, duration: TimeInterval)] {
        guard history.count >= 2 else { return [] }

        var durations: [ThermalPressure: TimeInterval] = [:]

        for i in 0..<(history.count - 1) {
            let current = history[i]
            let next = history[i + 1]
            let duration = next.timestamp.timeIntervalSince(current.timestamp)
            durations[current.pressure, default: 0] += duration
        }

        // Add time for the current (last) state up to now
        if let last = history.last {
            let duration = Date().timeIntervalSince(last.timestamp)
            durations[last.pressure, default: 0] += duration
        }

        // Sort by duration descending
        return durations.map { (pressure: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
    }

    var totalHistoryDuration: TimeInterval {
        guard let first = history.first else { return 0 }
        return Date().timeIntervalSince(first.timestamp)
    }

    init() {
        requestNotificationPermission()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    private func startMonitoring() {
        // Initial read
        updateThermalState()

        timer = Timer.scheduledTimer(withTimeInterval: Self.pollIntervalSeconds, repeats: true) { [weak self] _ in
            self?.updateThermalState()
        }
    }

    /// 按滞回规则推算「温度判定等级」：升级立即生效，降级需跌破解除阈值
    static func nextTemperaturePressure(previous: ThermalPressure, temperature: Double?) -> ThermalPressure {
        guard let temperature else { return previous }

        switch previous {
        case .critical:
            if temperature >= criticalReleaseTemperatureThreshold { return .critical }
            if temperature >= warningReleaseTemperatureThreshold { return .heavy }
            return .nominal
        case .heavy:
            if temperature >= criticalTemperatureThreshold { return .critical }
            if temperature >= warningReleaseTemperatureThreshold { return .heavy }
            return .nominal
        default:
            if temperature >= criticalTemperatureThreshold { return .critical }
            if temperature >= warningTemperatureThreshold { return .heavy }
            return .nominal
        }
    }

    /// 取系统热压等级与温度判定等级中更严重者
    static func resolvedPressure(
        systemPressure: ThermalPressure,
        temperaturePressure: ThermalPressure
    ) -> ThermalPressure {
        severity(of: temperaturePressure) > severity(of: systemPressure) ? temperaturePressure : systemPressure
    }

    private static func severity(of pressure: ThermalPressure) -> Int {
        switch pressure {
        case .critical: return 3
        case .heavy: return 2
        case .moderate: return 1
        case .nominal: return 0
        case .unknown: return -1
        }
    }

    /// 读取 CPU 温度（SMC 优先，HID 兜底）
    private func readTemperature() {
        if let smcReading = SMCReader.shared.readCPUTemperature() {
            temperature = smcReading.value
            temperatureSource = smcReading.source
        } else if let hidReading = HIDTemperatureReader.shared.readCPUTemperature() {
            temperature = hidReading.value
            temperatureSource = hidReading.source
        } else {
            temperature = nil
            temperatureSource = nil
        }
    }

    private func updateThermalState() {
        // 先读取温度，使其可参与热压等级判定
        readTemperature()
        temperaturePressure = Self.nextTemperaturePressure(previous: temperaturePressure, temperature: temperature)

        let systemPressure = ThermalPressureReader.shared.readPressure() ?? .unknown
        let newPressure = Self.resolvedPressure(
            systemPressure: systemPressure,
            temperaturePressure: temperaturePressure
        )

        if newPressure != previousPressure {
            // Check for throttling notifications
            if shouldNotify(for: newPressure, previous: previousPressure) {
                sendThrottleNotification(pressure: newPressure)
            }

            // Check for recovery notification
            let recovered = previousPressure.isThrottling && !newPressure.isThrottling
            if notifyOnRecovery && recovered && newPressure != .unknown {
                sendRecoveryNotification()
            }

            previousPressure = newPressure
        }

        pressure = newPressure

        // Read fan speed
        if let fan = SMCReader.shared.readFanSpeed() {
            fanSpeed = fan.percentage
            if !hasFans { hasFans = true }
        }

        // Record history
        let entry = HistoryEntry(
            pressure: newPressure,
            temperature: temperature,
            fanSpeed: fanSpeed,
            timestamp: Date()
        )
        history.append(entry)

        // Trim old entries
        let cutoff = Date().addingTimeInterval(-Self.historyDurationSeconds)
        history.removeAll { $0.timestamp < cutoff }
    }

    private func shouldNotify(for pressure: ThermalPressure, previous: ThermalPressure) -> Bool {
        switch pressure {
        case .heavy:
            return notifyOnHeavy && !previous.isThrottling
        case .critical:
            return notifyOnCritical && previous != .critical
        default:
            return false
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendThrottleNotification(pressure: ThermalPressure) {
        let content = UNMutableNotificationContent()
        content.title = "热压降频"
        content.body = pressure == .critical
            ? "Mac 正处于严重降频状态！"
            : "Mac 正在降频（重度热压）"
        if notificationSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func sendRecoveryNotification() {
        let content = UNMutableNotificationContent()
        content.title = "热压已恢复"
        content.body = "Mac 已不再降频"
        if notificationSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
