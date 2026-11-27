import Testing
@testable import DoormanCore

@Suite("在场状态机")
struct PresenceMachineTests {
    let t0 = ContinuousClock.now

    private func feed(_ m: inout PresenceMachine, _ values: [Int], from start: Int = 0) -> [PresenceEffect] {
        var effects: [PresenceEffect] = []
        for (i, v) in values.enumerated() {
            effects += m.onSample(v, at: t0 + .seconds(start + i), epoch: m.epoch)
        }
        return effects
    }

    @Test("重新采样中收到强信号进入在场")
    func resamplingToNear() {
        var m = PresenceMachine(now: t0)
        let effects = feed(&m, [-55])
        #expect(m.state == .near)
        #expect(effects == [.deviceReturned])
    }

    @Test("滞回区间内不改变状态")
    func hysteresisHoldsNear() {
        var m = PresenceMachine(now: t0)
        _ = feed(&m, [-55, -70, -72, -75, -78, -70])
        #expect(m.state == .near)
    }

    @Test("滤波值低于离开阈值开始倒计时，到期后想要锁屏")
    func leavingThenAway() {
        var m = PresenceMachine(now: t0)
        _ = feed(&m, [-55, -85, -86, -88, -90, -91])
        guard case .leaving(let deadline) = m.state else {
            Issue.record("应进入离开中，实际 \(m.state)")
            return
        }
        #expect(m.onTick(at: deadline - .milliseconds(1)).isEmpty)
        #expect(m.onTick(at: deadline) == [.lockWanted(.away)])
        #expect(m.state == .away)
    }

    @Test("倒计时内信号回升则取消")
    func leavingCancelled() {
        var m = PresenceMachine(now: t0)
        _ = feed(&m, [-55, -85, -86, -88, -60, -58, -57])
        #expect(m.state == .near)
    }

    @Test("超过失联超时进入失联")
    func lostAfterTimeout() {
        var m = PresenceMachine(now: t0)
        _ = feed(&m, [-55])
        #expect(m.onTick(at: t0 + .seconds(60)).isEmpty)
        #expect(m.onTick(at: t0 + .seconds(61)) == [.lockWanted(.lost)])
        #expect(m.state == .lost)
    }

    @Test("唤醒后找不到设备进入监控不可用，设备回来后恢复")
    func resampleTimeoutThenRecover() {
        var m = PresenceMachine(now: t0)
        m.restart(at: t0)
        #expect(m.onTick(at: t0 + .seconds(16)) == [.monitorNotReady(.notFoundAfterWake)])
        #expect(m.state == .unavailable(.notFoundAfterWake))
        let effects = m.onSample(-55, at: t0 + .seconds(20), epoch: m.epoch)
        #expect(effects == [.deviceReturned])
        #expect(m.state == .near)
    }

    @Test("旧 epoch 的样本被丢弃")
    func staleEpochIgnored() {
        var m = PresenceMachine(now: t0)
        let old = m.epoch
        m.restart(at: t0)
        #expect(m.onSample(-50, at: t0 + .seconds(1), epoch: old).isEmpty)
        #expect(m.state == .resampling(since: t0))
    }

    @Test("本机蓝牙关闭时不接收样本，恢复后重新采样")
    func sensorBlocked() {
        var m = PresenceMachine(now: t0)
        #expect(m.sensorUnavailable(.bluetoothOff) == [.monitorNotReady(.bluetoothOff)])
        #expect(m.onSample(-50, at: t0 + .seconds(1), epoch: m.epoch).isEmpty)
        m.sensorAvailable(at: t0 + .seconds(2))
        #expect(m.state == .resampling(since: t0 + .seconds(2)))
    }

    @Test("连续在场达到时长才算稳定")
    func stableNear() {
        var m = PresenceMachine(now: t0)
        _ = feed(&m, [-55])
        #expect(!m.isStablyNear(at: t0 + .seconds(9)))
        #expect(m.isStablyNear(at: t0 + .seconds(10)))
    }
}
