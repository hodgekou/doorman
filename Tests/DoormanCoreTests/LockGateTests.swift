import Foundation
import Testing
@testable import DoormanCore

@Suite("活动守卫闸门")
struct LockGateTests {
    let t0 = ContinuousClock.now
    let config = DoormanConfig() // 空闲门槛 10 秒，预警 5 秒

    @Test("近期有键鼠输入：拦截，不进入预警")
    func blockedByRecentInput() {
        var gate = LockGate(config: config)
        gate.onLockWanted(.away)
        let effects = gate.onTick(at: t0, lastInputAt: t0 - .seconds(2))
        guard case .blockedByActivity = effects.first else {
            Issue.record("应拦截，实际 \(effects)")
            return
        }
        // 只报告一次，继续观察
        #expect(gate.onTick(at: t0 + .seconds(1), lastInputAt: t0 + .seconds(1)).isEmpty)
        #expect(gate.currentRoundID != nil)
    }

    @Test("空闲达到门槛进入预警，预警期间无输入则放行")
    func warningThenRelease() {
        var gate = LockGate(config: config)
        gate.onLockWanted(.away)
        let lastInput = t0 - .seconds(10)
        let show = gate.onTick(at: t0, lastInputAt: lastInput)
        guard case .showWarning = show.first else {
            Issue.record("应进入预警，实际 \(show)")
            return
        }
        #expect(gate.onTick(at: t0 + .seconds(4), lastInputAt: lastInput).isEmpty)
        let release = gate.onTick(at: t0 + .seconds(5), lastInputAt: lastInput)
        #expect(release.first == .hideWarning)
        guard case .execute(_, let start) = release.last else {
            Issue.record("应放行，实际 \(release)")
            return
        }
        #expect(start == t0)
    }

    @Test("预警最后一刻有输入：结束本轮，不放行")
    func inputAtLastMomentEndsRound() {
        var gate = LockGate(config: config)
        gate.onLockWanted(.away)
        _ = gate.onTick(at: t0, lastInputAt: t0 - .seconds(10))
        let effects = gate.onTick(at: t0 + .seconds(5), lastInputAt: t0 + .milliseconds(4_999))
        #expect(effects.first == .hideWarning)
        guard case .cancelledByUser = effects.last else {
            Issue.record("应视为用户取消，实际 \(effects)")
            return
        }
        #expect(gate.isEndedByUser)
        #expect(!effects.contains { if case .execute = $0 { return true } else { return false } })
    }

    @Test("用户取消后忽略新的锁屏申请，设备稳定在场后才恢复")
    func endedByUserIgnoresUntilStable() {
        var gate = LockGate(config: config)
        gate.onLockWanted(.away)
        _ = gate.onTick(at: t0, lastInputAt: t0 - .seconds(10))
        _ = gate.onTick(at: t0 + .seconds(1), lastInputAt: t0 + .seconds(1))
        #expect(gate.isEndedByUser)

        gate.onLockWanted(.lost)
        #expect(gate.currentRoundID == nil)

        gate.onStableNear()
        gate.onLockWanted(.away)
        #expect(gate.currentRoundID != nil)
    }

    @Test("设备回到在场：撤下预警并作废本轮")
    func revokeHidesWarning() {
        var gate = LockGate(config: config)
        gate.onLockWanted(.away)
        _ = gate.onTick(at: t0, lastInputAt: t0 - .seconds(10))
        let effects = gate.revoke(.deviceReturned)
        #expect(effects.first == .hideWarning)
        guard case .revoked(_, .deviceReturned) = effects.last else {
            Issue.record("应撤销本轮，实际 \(effects)")
            return
        }
        #expect(gate.currentRoundID == nil)
    }

    @Test("读不到空闲时长：撤销本轮，宁可漏锁")
    func idleUnreadableRevokes() {
        var gate = LockGate(config: config)
        gate.onLockWanted(.lost)
        let effects = gate.onTick(at: t0, lastInputAt: nil)
        guard case .revoked(_, .idleUnreadable) = effects.last else {
            Issue.record("应撤销，实际 \(effects)")
            return
        }
    }
}
