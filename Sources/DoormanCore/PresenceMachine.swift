/// 为什么想锁屏。
public enum LockReason: String, Sendable, Codable, Equatable {
    case away
    case lost
    case sensorUnavailable
    case manual
}

/// 监控不可用的原因。
public enum MonitorIssue: String, Sendable, Codable, Equatable {
    case bluetoothOff
    case bluetoothUnauthorized
    case notFoundAfterWake
}

/// 撤销一轮自动锁屏尝试的原因。
public enum InterruptReason: String, Sendable, Codable, Equatable {
    case deviceReturned
    case paused
    case systemSleep
    case sessionSwitched
    case sensorUnavailable
    case sensorRestored
    case idleUnreadable
    case rebound
}

/// ① 设备在场状态。只回答「设备在不在」，不知道屏幕是否已锁。
public enum Presence: Sendable, Equatable {
    case resampling(since: Instant)
    case near
    case leaving(deadline: Instant)
    case away
    case lost
    case unavailable(MonitorIssue)
}

public enum PresenceEffect: Sendable, Equatable {
    /// 想要锁屏。只是申请，要先经过 LockGate。
    case lockWanted(LockReason)
    /// 设备从非在场回到在场。外层据此撤销当前轮次。
    case deviceReturned
    case monitorNotReady(MonitorIssue)
}

/// 在场状态机（纯逻辑）。输入：样本、时钟、系统事件；输出：PresenceEffect。
public struct PresenceMachine: Sendable {
    public private(set) var config: DoormanConfig
    public private(set) var state: Presence
    /// 每次重启（唤醒、恢复、重新绑定、蓝牙恢复）+1；旧 epoch 的样本直接丢弃。
    public private(set) var epoch = 0
    public private(set) var nearSince: Instant?
    public private(set) var lastSampleAt: Instant?
    public private(set) var lastRaw: Int?
    public private(set) var estimate: Int?
    private var filter: MedianFilter

    public init(config: DoormanConfig = .init(), now: Instant) {
        self.config = config
        self.filter = MedianFilter(capacity: config.filterSize)
        self.state = .resampling(since: now)
    }

    public var isPresent: Bool {
        switch state {
        case .near, .leaving: return true
        default: return false
        }
    }

    /// 本机蓝牙关闭或无权限：此时不接收样本。
    public var isSensorBlocked: Bool {
        if case .unavailable(let issue) = state, issue != .notFoundAfterWake { return true }
        return false
    }

    public func isStablyNear(at now: Instant) -> Bool {
        guard case .near = state, let since = nearSince else { return false }
        return now - since >= config.stableNearDuration
    }

    public mutating func updateConfig(_ newConfig: DoormanConfig) {
        if newConfig.filterSize != config.filterSize {
            filter = MedianFilter(capacity: newConfig.filterSize)
        }
        config = newConfig
    }

    public mutating func onSample(_ raw: Int, at now: Instant, epoch sampleEpoch: Int) -> [PresenceEffect] {
        // 非负 RSSI 是无效读数
        guard sampleEpoch == epoch, raw < 0, !isSensorBlocked else { return [] }
        filter.drop(olderThan: now - config.sampleMaxAge)
        lastSampleAt = now
        lastRaw = raw

        var effects: [PresenceEffect] = []
        // 进入在场用原始值，响应更快
        if raw >= config.presentRSSI, !isPresent {
            filter.reset()
            state = .near
            nearSince = now
            effects.append(.deviceReturned)
        }

        let est = filter.push(raw, at: now)
        estimate = est
        switch state {
        case .near where est < config.leaveRSSI:
            state = .leaving(deadline: now + config.leaveDelay)
            nearSince = nil
        case .leaving(_) where est >= config.leaveRSSI:
            state = .near
            nearSince = now
        default:
            break
        }
        return effects
    }

    public mutating func onTick(at now: Instant) -> [PresenceEffect] {
        switch state {
        case .leaving(let deadline) where now >= deadline:
            state = .away
            return [.lockWanted(.away)]
        case .near, .leaving(_):
            if let last = lastSampleAt, now - last > config.signalTimeout {
                state = .lost
                nearSince = nil
                estimate = nil
                filter.reset()
                return [.lockWanted(.lost)]
            }
        case .resampling(let since) where now - since > config.resampleTimeout:
            state = .unavailable(.notFoundAfterWake)
            return [.monitorNotReady(.notFoundAfterWake)]
        default:
            break
        }
        return []
    }

    /// 唤醒、暂停后恢复、重新绑定、蓝牙恢复：作废旧 epoch，进入「重新采样中」。
    public mutating func restart(at now: Instant) {
        epoch += 1
        filter.reset()
        lastSampleAt = nil
        lastRaw = nil
        estimate = nil
        nearSince = nil
        state = .resampling(since: now)
    }

    public mutating func sensorUnavailable(_ issue: MonitorIssue) -> [PresenceEffect] {
        if case .unavailable(issue) = state { return [] }
        epoch += 1
        filter.reset()
        lastSampleAt = nil
        lastRaw = nil
        estimate = nil
        nearSince = nil
        state = .unavailable(issue)
        return [.monitorNotReady(issue)]
    }

    public mutating func sensorAvailable(at now: Instant) {
        if isSensorBlocked { restart(at: now) }
    }
}
