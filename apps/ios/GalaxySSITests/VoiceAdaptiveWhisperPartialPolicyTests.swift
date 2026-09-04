import XCTest
@testable import GalaxySSI

final class VoiceAdaptiveWhisperPartialPolicyTests: XCTestCase {
  func testTinyStartsFastAndSlowsWhenRealTimeFactorRises() {
    let tiny = VoiceWhisperModelCatalog.model("tiny")
    let policy = VoiceAdaptiveWhisperPartialPolicy(profile: tiny)
    XCTAssertTrue(policy.shouldSubmit(nowMillis: 1_000, capturedAudioMillis: 1_000))

    policy.onDecodeCompleted(realTimeFactor: 1.1)
    let degraded = policy.snapshot()

    XCTAssertTrue(degraded.enabled)
    XCTAssertTrue(degraded.intervalMillis > tiny.defaultPartialIntervalMillis)
    XCTAssertTrue(degraded.windowMillis < tiny.maxWindowMillis)
  }

  func testRepeatedBacklogSkipsWorkAndIncreasesInterval() {
    let policy = VoiceAdaptiveWhisperPartialPolicy(profile: VoiceWhisperModelCatalog.model("base"))
    let congested = VoiceWhisperDecodeQueueSnapshot(queuedPartials: 2)

    XCTAssertFalse(policy.shouldSubmit(nowMillis: 2_000, capturedAudioMillis: 2_000, queue: congested))
    let once = policy.snapshot()
    XCTAssertFalse(policy.shouldSubmit(nowMillis: 4_000, capturedAudioMillis: 4_000, queue: congested))
    let twice = policy.snapshot()

    XCTAssertGreaterThanOrEqual(twice.intervalMillis, once.intervalMillis)
    XCTAssertGreaterThanOrEqual(twice.backlogStreak, 2)
  }

  func testSlowProfileNeverOffersRealtimePartial() {
    let policy = VoiceAdaptiveWhisperPartialPolicy(profile: VoiceWhisperModelCatalog.model("medium"))

    XCTAssertFalse(policy.shouldSubmit(nowMillis: 10_000, capturedAudioMillis: 10_000))
    XCTAssertFalse(policy.snapshot().enabled)
  }

  func testCertificationCanEnableOrDisablePartialIndependentOfModelName() {
    let measuredFastMedium = VoiceAdaptiveWhisperPartialPolicy(
      profile: VoiceWhisperModelCatalog.model("medium_q5_0"),
      certifiedPartialIntervalMillis: 2_500,
      realtimeCertified: true
    )
    let untestedTiny = VoiceAdaptiveWhisperPartialPolicy(
      profile: VoiceWhisperModelCatalog.model("tiny"),
      realtimeCertified: false
    )

    XCTAssertTrue(measuredFastMedium.shouldSubmit(nowMillis: 3_000, capturedAudioMillis: 3_000))
    XCTAssertEqual(measuredFastMedium.snapshot().intervalMillis, 2_500)
    XCTAssertFalse(untestedTiny.shouldSubmit(nowMillis: 3_000, capturedAudioMillis: 3_000))
  }

  func testActiveRealtimePartialCountsAsBacklog() {
    let policy = VoiceAdaptiveWhisperPartialPolicy(profile: VoiceWhisperModelCatalog.model("tiny"))
    let active = VoiceWhisperDecodeQueueSnapshot(activeMode: .realtimePartial, queuedPartials: 1)

    XCTAssertFalse(policy.shouldSubmit(nowMillis: 2_000, capturedAudioMillis: 2_000, queue: active))
    XCTAssertEqual(policy.snapshot().backlogStreak, 1)
  }

  func testHealthyFastDecodesRestoreBaseWindow() {
    let policy = VoiceAdaptiveWhisperPartialPolicy(profile: VoiceWhisperModelCatalog.model("tiny"))
    policy.onDecodeCompleted(realTimeFactor: 1.0)
    let constrained = policy.snapshot()

    policy.onDecodeCompleted(realTimeFactor: 0.2)
    policy.onDecodeCompleted(realTimeFactor: 0.2)
    let restored = policy.snapshot()

    XCTAssertLessThan(constrained.windowMillis, restored.windowMillis)
    XCTAssertEqual(restored.backlogStreak, 0)
  }
}
