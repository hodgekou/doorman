import Foundation
import Testing
@testable import DoormanCore

/// 活跃误锁 · M1 发布阻断项的逻辑层回放：
/// 用秒级轨迹驱动「在场状态机 → 闸门 → 执行前复核」整条链，统计会调用系统锁屏的次数。
/// 真机验收仍需在 MacBook 内置键盘 / 触控板和外接键鼠上各跑一遍。
@Suite("活跃使用回放")
struct ActiveUseReplayTests {
    struct Step {
        var rssi: Int?          // nil = 这一秒没有样本
        var input: Bool         // 这一秒有键鼠输入
    }

    /// 返回会调用系统锁屏的次数。
    func replay(_ steps: [Step], injectInputAfterRelease: Bool = false) -> Int {
        let t0 = ContinuousClock.now
        let config = DoormanConfig()
        var presence = PresenceMachine(config: config, now: t0)
        var gate = LockGate(config: config)
        var lastInputAt = t0
        var lockCalls = 0

        func handleGate(_ effects: [GateEffect], now: Instant) {
            for case .execute(let round, let start) in effects {
                if injectInputAfterRelease { lastInputAt = now }
                let decision = ExecutionCheck.evaluate(round: round, currentRoundID: gate.currentRoundID,
                                                       session: .unlocked, lastInputAt: lastInputAt,
                                                       warningStartedAt: start)
                switch decision {
                case .proceed:
                    lockCalls += 1
                    gate.finishExecution()
                case .abort(.inputAfterWarning):
                    gate.endByUser()
                default:
                    gate.finishExecution()
                }
            }
        }

        for (i, step) in steps.enumerated() {
            let now = t0 + .seconds(i)
            if step.input { lastInputAt = now }
            if let rssi = step.rssi {
                for effect in presence.onSample(rssi, at: now, epoch: presence.epoch) {
                    if case .deviceReturned = effect { handleGate(gate.revoke(.deviceReturned), now: now) }
                }
            }
            for effect in presence.onTick(at: now) {
                if case .lockWanted(let reason) = effect { gate.onLockWanted(reason) }
            }
            if gate.isEndedByUser, presence.isStablyNear(at: now) { gate.onStableNear() }
            handleGate(gate.onTick(at: now, lastInputAt: lastInputAt), now: now)
        }
        return lockCalls
    }

    @Test("持续打字时手表被挡住：0 次锁屏调用")
    func typingWhileBlocked() {
        let steps = [Step(rssi: -55, input: true)]
            + Array(repeating: Step(rssi: -88, input: true), count: 120)
        #expect(replay(steps) == 0)
    }

    @Test("持续打字时信号骤失（失联路径）：0 次锁屏调用")
    func typingWhileSignalLost() {
        let steps = [Step(rssi: -55, input: true)]
            + Array(repeating: Step(rssi: nil, input: true), count: 120)
        #expect(replay(steps) == 0)
    }

    @Test("放行后、执行前注入输入：0 次锁屏调用")
    func inputBetweenReleaseAndExecute() {
        let steps = [Step(rssi: -55, input: true)]
            + Array(repeating: Step(rssi: -90, input: false), count: 60)
        #expect(replay(steps, injectInputAfterRelease: true) == 0)
    }

    @Test("只看屏幕：取消一次预警后本轮不再预警")
    func readingAfterCancelDoesNotRetry() {
        // 第 7 秒判定离开；第 10 秒空闲满 10 秒出现预警；第 12 秒碰一下鼠标取消；之后 30 分钟不动
        var steps = [Step(rssi: -55, input: true)]
        steps += Array(repeating: Step(rssi: -90, input: false), count: 11)
        steps.append(Step(rssi: -90, input: true))
        steps += Array(repeating: Step(rssi: -90, input: false), count: 1800)
        #expect(replay(steps) == 0)
    }

    @Test("真的走开：锁屏一次")
    func walkingAwayLocksOnce() {
        let steps = [Step(rssi: -55, input: true)]
            + Array(repeating: Step(rssi: -90, input: false), count: 60)
        #expect(replay(steps) == 1)
    }
}
