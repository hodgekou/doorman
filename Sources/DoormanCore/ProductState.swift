/// 产品状态：界面始终如实告诉用户 Doorman 此刻能不能自动锁屏。
public enum ProductState: Sendable, Equatable {
    case autoLockAvailable
    case reminderOnly
    case notReady(NotReadyReason)

    public enum NotReadyReason: String, Sendable, Equatable {
        case noDeviceBound
        case autoLockDisabled
        case paused
        case bluetoothOff
        case bluetoothUnauthorized
        case resampling
        case notFoundAfterWake
        case signalUnstable
    }

    public static func derive(
        hasDevice: Bool,
        autoLockEnabled: Bool,
        paused: Bool,
        presence: Presence,
        gateEndedByUser: Bool,
        canLock: Bool
    ) -> ProductState {
        guard hasDevice else { return .notReady(.noDeviceBound) }
        guard autoLockEnabled else { return .notReady(.autoLockDisabled) }
        if paused { return .notReady(.paused) }
        switch presence {
        case .unavailable(.bluetoothOff): return .notReady(.bluetoothOff)
        case .unavailable(.bluetoothUnauthorized): return .notReady(.bluetoothUnauthorized)
        case .unavailable(.notFoundAfterWake): return .notReady(.notFoundAfterWake)
        case .resampling: return .notReady(.resampling)
        default: break
        }
        if gateEndedByUser { return .notReady(.signalUnstable) }
        return canLock ? .autoLockAvailable : .reminderOnly
    }
}
