import Foundation
import DoormanCore

enum SamplingMode: String, Codable, CaseIterable, Identifiable {
    case active
    case passive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return L("主动连接（更稳定）")
        case .passive: return L("被动监听（不干扰键鼠、热点）")
        }
    }
}

enum SensorPolicy: String, Codable, CaseIterable, Identifiable {
    case remindOnly
    case lock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remindOnly: return L("只提醒")
        case .lock: return L("锁屏（同样经过活动守卫）")
        }
    }
}

/// M0 待选的锁屏方式。最终只保留在目标分发渠道下「触发 + 确认」都通过的那种。
enum LockMethodKind: String, Codable, CaseIterable, Identifiable {
    case privateSAC
    case shortcut
    case reminderOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateSAC: return L("A1 · SACLockScreenImmediate（私有接口）")
        case .shortcut: return L("B1 · 合成 ⌃⌘Q（需辅助功能）")
        case .reminderOnly: return L("D · 仅提醒，不锁屏")
        }
    }
}

/// 灵敏度预设：把在场阈值、离开阈值、离开延迟打包成用户能理解的三档。
enum Sensitivity: String, CaseIterable, Identifiable {
    case sensitive
    case balanced
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sensitive: return L("灵敏")
        case .balanced: return L("均衡")
        case .relaxed: return L("宽松")
        }
    }

    var detail: String {
        switch self {
        case .sensitive: return L("走开几步就锁屏，信号波动大时偶尔会出现预警")
        case .balanced: return L("适合大多数办公环境")
        case .relaxed: return L("走得更远才锁屏，误判最少")
        }
    }

    var values: (present: Int, leave: Int, delay: Int) {
        switch self {
        case .sensitive: return (-55, -75, 3)
        case .balanced: return (-60, -80, 5)
        case .relaxed: return (-65, -85, 10)
        }
    }
}

/// 设备类型：决定图标。auto 表示按设备名猜测。
enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case auto, watch, iphone, ipad, airpods, mac, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return L("自动识别")
        case .watch: return "Apple Watch"
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .airpods: return "AirPods"
        case .mac: return "Mac"
        case .other: return L("其他设备")
        }
    }

    /// auto 时返回 nil，由调用方按名称猜测
    var symbol: String? {
        switch self {
        case .auto: return nil
        case .watch: return "applewatch"
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .airpods: return "airpodspro"
        case .mac: return "laptopcomputer"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

/// 用户设置。持久化到 UserDefaults；缺字段时取默认值，便于以后加字段。
struct AppSettings: Codable, Equatable {
    var onboardingCompleted = false
    var language: AppLanguage = .system
    var boundDeviceID: UUID?
    var boundDeviceName: String?
    /// 用户给设备起的显示名称；空字符串表示使用设备广播的名称
    var deviceAlias = ""
    var deviceKind: DeviceKind = .auto
    var presentRSSI = -60
    var leaveRSSI = -80
    var leaveDelaySeconds = 5
    var signalTimeoutSeconds = 60
    var idleThresholdSeconds = 10
    var warningSeconds = 5
    var samplingMode: SamplingMode = .active
    var sensorPolicy: SensorPolicy = .remindOnly
    var lockMethod: LockMethodKind = .privateSAC
    var autoLockEnabled = true

    static let presentRange = -75 ... -40
    static let leaveRange = -95 ... -60
    static let leaveDelayRange = 2 ... 60
    static let signalTimeoutRange = 15 ... 300
    static let idleRange = 3 ... 120
    static let warningRange = 3 ... 15

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        boundDeviceID = try c.decodeIfPresent(UUID.self, forKey: .boundDeviceID)
        boundDeviceName = try c.decodeIfPresent(String.self, forKey: .boundDeviceName)
        deviceAlias = try c.decodeIfPresent(String.self, forKey: .deviceAlias) ?? ""
        deviceKind = try c.decodeIfPresent(DeviceKind.self, forKey: .deviceKind) ?? .auto
        // 老版本没有这个字段：已绑定过设备的用户视为完成引导
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? (boundDeviceID != nil)
        presentRSSI = try c.decodeIfPresent(Int.self, forKey: .presentRSSI) ?? d.presentRSSI
        leaveRSSI = try c.decodeIfPresent(Int.self, forKey: .leaveRSSI) ?? d.leaveRSSI
        leaveDelaySeconds = try c.decodeIfPresent(Int.self, forKey: .leaveDelaySeconds) ?? d.leaveDelaySeconds
        signalTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .signalTimeoutSeconds) ?? d.signalTimeoutSeconds
        idleThresholdSeconds = try c.decodeIfPresent(Int.self, forKey: .idleThresholdSeconds) ?? d.idleThresholdSeconds
        warningSeconds = try c.decodeIfPresent(Int.self, forKey: .warningSeconds) ?? d.warningSeconds
        samplingMode = try c.decodeIfPresent(SamplingMode.self, forKey: .samplingMode) ?? d.samplingMode
        sensorPolicy = try c.decodeIfPresent(SensorPolicy.self, forKey: .sensorPolicy) ?? d.sensorPolicy
        lockMethod = try c.decodeIfPresent(LockMethodKind.self, forKey: .lockMethod) ?? d.lockMethod
        autoLockEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoLockEnabled) ?? d.autoLockEnabled
    }

    /// 把越界值夹回合法范围，并保证在场阈值 ≥ 离开阈值（保留滞回区间）。
    func normalized() -> AppSettings {
        var s = self
        s.presentRSSI = s.presentRSSI.clamped(to: Self.presentRange)
        s.leaveRSSI = s.leaveRSSI.clamped(to: Self.leaveRange)
        if s.leaveRSSI > s.presentRSSI { s.leaveRSSI = s.presentRSSI }
        s.leaveDelaySeconds = s.leaveDelaySeconds.clamped(to: Self.leaveDelayRange)
        s.signalTimeoutSeconds = s.signalTimeoutSeconds.clamped(to: Self.signalTimeoutRange)
        s.idleThresholdSeconds = s.idleThresholdSeconds.clamped(to: Self.idleRange)
        s.warningSeconds = s.warningSeconds.clamped(to: Self.warningRange)
        if s.deviceAlias.count > 40 {
            s.deviceAlias = String(s.deviceAlias.prefix(40))
        }
        if let name = s.boundDeviceName, name.count > 100 {
            s.boundDeviceName = String(name.prefix(100))
        }
        return s
    }

    /// 当前值对应的预设；不匹配任何预设时为 nil（自定义）。
    var sensitivity: Sensitivity? {
        Sensitivity.allCases.first {
            let v = $0.values
            return v.present == presentRSSI && v.leave == leaveRSSI && v.delay == leaveDelaySeconds
        }
    }

    mutating func apply(_ preset: Sensitivity) {
        let v = preset.values
        presentRSSI = v.present
        leaveRSSI = v.leave
        leaveDelaySeconds = v.delay
    }

    var config: DoormanConfig {
        DoormanConfig(
            presentRSSI: presentRSSI,
            leaveRSSI: leaveRSSI,
            leaveDelay: .seconds(leaveDelaySeconds),
            signalTimeout: .seconds(signalTimeoutSeconds),
            idleThreshold: .seconds(idleThresholdSeconds),
            warningLength: .seconds(warningSeconds)
        )
    }

    private static let defaultsKey = "doorman.settings.v1"

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded.normalized()
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
