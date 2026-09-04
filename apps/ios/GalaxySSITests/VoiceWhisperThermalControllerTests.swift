import XCTest
@testable import GalaxySSI

final class VoiceWhisperThermalControllerTests: XCTestCase {
  func testModerateThermalStatusIsHeldDuringCooldown() {
    var now: Int64 = 1_000
    let controller = VoiceWhisperThermalController(elapsedMillis: { now })

    XCTAssertEqual(controller.effectiveStatus(observedStatus: 2), 2)
    XCTAssertEqual(controller.remainingCooldownMillis(), 30_000)

    now += 10_000
    XCTAssertEqual(controller.effectiveStatus(observedStatus: 0), 2)
    XCTAssertEqual(controller.remainingCooldownMillis(), 20_000)

    now += 20_000
    XCTAssertEqual(controller.effectiveStatus(observedStatus: 0), 0)
    XCTAssertEqual(controller.remainingCooldownMillis(), 0)
  }

  func testHigherThermalStatusExtendsCooldown() {
    var now: Int64 = 0
    let controller = VoiceWhisperThermalController(elapsedMillis: { now })

    XCTAssertEqual(controller.effectiveStatus(observedStatus: 2), 2)
    now += 5_000
    XCTAssertEqual(controller.effectiveStatus(observedStatus: 3), 3)
    XCTAssertEqual(controller.remainingCooldownMillis(), 90_000)

    now += 89_999
    XCTAssertEqual(controller.effectiveStatus(observedStatus: 0), 3)
    now += 1
    XCTAssertEqual(controller.effectiveStatus(observedStatus: 0), 0)
  }

  func testCriticalAndOutOfRangeStatusAreClamped() {
    var now: Int64 = 0
    let controller = VoiceWhisperThermalController(elapsedMillis: { now })

    XCTAssertEqual(controller.effectiveStatus(observedStatus: 99), 4)
    XCTAssertEqual(controller.remainingCooldownMillis(), 180_000)

    now += 180_000
    XCTAssertEqual(controller.effectiveStatus(observedStatus: -10), 0)
  }
}
