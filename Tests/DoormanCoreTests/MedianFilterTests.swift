import Testing
@testable import DoormanCore

@Suite("中值滤波")
struct MedianFilterTests {
    @Test("单个尖峰被滤掉")
    func spikeIsRejected() {
        var filter = MedianFilter(capacity: 5)
        let t0 = ContinuousClock.now
        for (i, value) in [-58, -57, -80, -59, -58].enumerated() {
            filter.push(value, at: t0 + .seconds(i))
        }
        #expect(filter.median == -58)
    }

    @Test("窗口只保留最近 N 个样本")
    func keepsCapacity() {
        var filter = MedianFilter(capacity: 3)
        let t0 = ContinuousClock.now
        for (i, value) in [-50, -60, -70, -80, -90].enumerated() {
            filter.push(value, at: t0 + .seconds(i))
        }
        #expect(filter.samples.map(\.rssi) == [-70, -80, -90])
        #expect(filter.median == -80)
    }

    @Test("按时间淘汰过期样本")
    func dropsOldSamples() {
        var filter = MedianFilter(capacity: 5)
        let t0 = ContinuousClock.now
        filter.push(-50, at: t0)
        filter.push(-60, at: t0 + .seconds(10))
        filter.drop(olderThan: t0 + .seconds(5))
        #expect(filter.samples.map(\.rssi) == [-60])
    }
}
