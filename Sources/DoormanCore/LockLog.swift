import Foundation

/// 一条诊断记录。只记原因、结果、耗时、权限状态，不记录周边其他设备。
public struct LockLogEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case blockedByActivity
        case warningCancelled
        case abortedBeforeExecution
        case observedLocked
        case unconfirmed
        case lateConfirmation
        case skippedAlreadyLocked
        case reminded
        case revoked
        case monitorNotReady
        case quickUnlockClue
        case manualLock
        case lockCallFailed
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    public var reason: LockReason?
    public var latencySeconds: Double?
    public var note: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        kind: Kind,
        reason: LockReason? = nil,
        latencySeconds: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.reason = reason
        self.latencySeconds = latencySeconds
        self.note = note
    }
}

/// 本地限量保存：最近 30 天、最多 500 条。
public struct LockLog: Codable, Sendable, Equatable {
    public static let maxEntries = 500
    public static let maxAge: TimeInterval = 30 * 24 * 3600

    public private(set) var entries: [LockLogEntry]

    public init(entries: [LockLogEntry] = []) {
        self.entries = entries
    }

    public mutating func append(_ entry: LockLogEntry, now: Date) {
        entries.append(entry)
        prune(now: now)
    }

    public mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.date) > Self.maxAge }
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    public mutating func clear() {
        entries.removeAll()
    }
}
