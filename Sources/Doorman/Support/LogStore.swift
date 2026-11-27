import Foundation
import DoormanCore

/// 诊断记录的本地持久化：~/Library/Application Support/Doorman/lock-log.json
/// 路径固定，不接受外部输入。
struct LogStore {
    private let fileURL: URL?

    init(fileManager: FileManager = .default) {
        if let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = base.appendingPathComponent("Doorman", isDirectory: true)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("lock-log.json")
        } else {
            fileURL = nil
        }
    }

    func load() -> LockLog {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              var log = try? JSONDecoder.iso.decode(LockLog.self, from: data) else {
            return LockLog()
        }
        log.prune(now: Date())
        return log
    }

    func save(_ log: LockLog) {
        guard let fileURL, let data = try? JSONEncoder.iso.encode(log) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
