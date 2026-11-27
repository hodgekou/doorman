/// 中值滤波：保留最近 N 个样本取中位数，并按时间淘汰过期样本。
/// 单个 ±20 dBm 的尖峰会被整个滤掉。
public struct MedianFilter: Sendable {
    public struct Sample: Sendable, Equatable {
        public let rssi: Int
        public let at: Instant
    }

    public let capacity: Int
    public private(set) var samples: [Sample] = []

    public init(capacity: Int = 5) {
        self.capacity = max(1, capacity)
    }

    public var median: Int? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.map(\.rssi).sorted()
        return sorted[sorted.count / 2]
    }

    public mutating func reset() {
        samples.removeAll()
    }

    /// 丢弃早于 cutoff 的样本。主动 / 被动采样的间隔不同，按时间而不是按个数淘汰。
    public mutating func drop(olderThan cutoff: Instant) {
        samples.removeAll { $0.at < cutoff }
    }

    @discardableResult
    public mutating func push(_ rssi: Int, at now: Instant) -> Int {
        samples.append(Sample(rssi: rssi, at: now))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        // samples 非空，median 一定有值
        return median ?? rssi
    }
}
