import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthAtlasChapterClockTests: XCTestCase {
  typealias Clock = GalaxySSIHealthAtlasChapterClock
  func testEveryChapterBoundaryUsesFiveSecondsOfActiveTime() {
    for count in 1...10 {
      var clock = Clock(chapters: count, phase: 0)
      clock.resume(500)
      for chapter in 1..<count {
        let boundary = Int64(500 + chapter * 5_000)
        XCTAssertLessThan(clock.sample(boundary - 1), Double(chapter) / Double(count))
        XCTAssertEqual(clock.sample(boundary), Double(chapter) / Double(count))
        XCTAssertEqual(clock.nextStepIn(boundary), 5_000)
      }
      XCTAssertEqual(clock.sample(Int64(500 + count * 5_000)), 1)
      XCTAssertFalse(clock.playing)
    }
  }
  func testPauseResumeKeepsTheFractionalChapterAndExcludesBackgroundTime() {
    var clock = Clock(chapters: 4, phase: 0)
    clock.resume(100); clock.pause(2_100)
    XCTAssertEqual(clock.sample(10_000), 0.1)
    clock.resume(10_000)
    XCTAssertEqual(clock.nextStepIn(10_000), 3_000)
    XCTAssertLessThan(clock.sample(12_999), 0.25)
    XCTAssertEqual(clock.sample(13_000), 0.25)
  }
  func testSeekPausesAndReplayRestartsOnlyAtTheEnd() {
    var clock = Clock(chapters: 5, phase: 0.4)
    clock.resume(1_000)
    XCTAssertEqual(clock.sample(3_500), 0.5)
    clock.seek(0.8); XCTAssertFalse(clock.playing)
    XCTAssertEqual(clock.sample(123_456), 0.8)
    clock.resume(124_000); XCTAssertEqual(clock.sample(129_000), 1)
    clock.resume(132_000); XCTAssertEqual(clock.sample(132_000), 0)
    clock.resume(133_000); XCTAssertEqual(clock.sample(133_000), 0.04)
    clock.seek(.nan); XCTAssertEqual(clock.sample(0), 0)
    clock.seek(.infinity); XCTAssertEqual(clock.sample(0), 0)
    clock.seek(-1); XCTAssertEqual(clock.sample(0), 0)
    clock.seek(2); XCTAssertEqual(clock.sample(0), 1)
  }
  func testBackwardClockDoesNotRemovePreviouslyConsumedTime() {
    var clock = Clock(chapters: 4, phase: 0.5)
    clock.resume(1_000); XCTAssertEqual(clock.sample(999), 0.5)
    clock.pause(999); XCTAssertEqual(clock.sample(9_000), 0.5)
  }
  @MainActor func testHandoffPausesAtTheActualOwnershipChangeNotTheNextFrame() {
    let group = GalaxySSIHealthAtlasPlayback()
    var lesson = Clock(chapters: 4, phase: 0)
    group.claim("function|heart|HEARTBEAT", now: 100); lesson.resume(100)
    group.claim("models-disclosure|heart", now: 1_750)
    lesson.pause(group.changedAt)
    XCTAssertEqual(lesson.sample(10_000), 0.0825)
    group.release("function|heart|HEARTBEAT")
    XCTAssertEqual(group.owner, "models-disclosure|heart")
    group.claim("simulation|heart", now: 12_000)
    group.claim("function|heart|HEARTBEAT", now: 12_250)
    XCTAssertEqual(group.changedAt, 12_250)
    group.release("simulation|heart")
    XCTAssertEqual(group.owner, "function|heart|HEARTBEAT")
  }
  @MainActor func testOwnershipCallbacksCompleteBeforeANewSnapshotCanBeTaken() {
    let group = GalaxySSIHealthAtlasPlayback()
    var pausedAt: Int64?
    group.claim("lesson", now: 100, pause: { pausedAt = $0; group.release("lesson") })
    group.claim("models", now: 1_750)
    XCTAssertEqual(pausedAt, 1_750); XCTAssertEqual(group.owner, "models")
    var previews = 0
    group.claim("lesson", now: 2_000, pause: { _ in previews += 1; group.release("lesson") })
    group.pause()
    XCTAssertEqual(previews, 1); XCTAssertNil(group.owner)
    group.pause(); XCTAssertEqual(previews, 1)
  }
}
