import XCTest
@testable import GalaxySSI

final class GlobalAgentServiceContinuityTests: XCTestCase {
  func testRecoverySignalsAreCoalescedWhileWorkIsPendingAndDuringCooldown() {
    let gate = GlobalAgentRecoverySignalGate(cooldownMillis: 2_000)

    XCTAssertTrue(gate.tryAcquire(nowMillis: 10_000))
    XCTAssertFalse(gate.tryAcquire(nowMillis: 10_100))
    gate.release()
    XCTAssertFalse(gate.tryAcquire(nowMillis: 11_999))
    XCTAssertTrue(gate.tryAcquire(nowMillis: 12_000))
  }

  func testServiceRecoveryPreservesEarlierDurableWorkWake() {
    XCTAssertEqual(
      GlobalAgentServiceContinuityPolicy.recoveryWakeAt(
        nowMillis: 1_000_000,
        scheduledWorkWakeAtMillis: 1_030_000
      ),
      1_030_000
    )
  }

  func testServiceRecoveryBoundsDistantOrMissingWake() {
    XCTAssertEqual(
      GlobalAgentServiceContinuityPolicy.recoveryWakeAt(
        nowMillis: 1_000_000,
        scheduledWorkWakeAtMillis: 1_600_000
      ),
      1_060_000
    )
    XCTAssertEqual(
      GlobalAgentServiceContinuityPolicy.recoveryWakeAt(
        nowMillis: 1_000_000,
        scheduledWorkWakeAtMillis: 0
      ),
      1_060_000
    )
  }
}
