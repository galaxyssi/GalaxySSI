import XCTest
@testable import GalaxySSI

final class VoiceWhisperTextStabilizerTests: XCTestCase {
  func testRepeatedWindowsPromoteStablePrefixWithoutDuplicatingOverlap() {
    let stabilizer = VoiceWhisperTextStabilizer(stabilityLagMillis: 300)

    let first = stabilizer.accept(window("hello world", startMillis: 0, windowEndMillis: 2_000, endMillis: 1_400))
    let second = stabilizer.accept(window("hello world again", startMillis: 0, windowEndMillis: 3_000, endMillis: 2_100))
    let third = stabilizer.accept(window("world again today", startMillis: 1_000, windowEndMillis: 4_000, endMillis: 3_100))

    XCTAssertEqual(first.stableText, "")
    XCTAssertTrue(second.stableText.hasPrefix("hello world"))
    XCTAssertEqual(third.displayText.components(separatedBy: "world").count - 1, 1)
    XCTAssertTrue(third.stableText.hasPrefix(second.stableText))
  }

  func testFinalUsesAuthoritativeFullDecodeAndClearsUnstableSuffix() {
    let stabilizer = VoiceWhisperTextStabilizer()
    _ = stabilizer.accept(window("\u{4f60}\u{597d}\u{4e16}", startMillis: 0, windowEndMillis: 1_500, endMillis: 700))
    _ = stabilizer.accept(window("\u{4f60}\u{597d}\u{4e16}\u{754c}", startMillis: 0, windowEndMillis: 2_000, endMillis: 1_200))

    let final = stabilizer.accept(
      window("\u{4f60}\u{597d}\u{4e16}\u{754c}\u{3002}", startMillis: 0, windowEndMillis: 2_500, endMillis: 2_500, final: true)
    )

    XCTAssertTrue(final.final)
    XCTAssertEqual(final.stableText, "\u{4f60}\u{597d}\u{4e16}\u{754c}\u{3002}")
    XCTAssertEqual(final.unstableText, "")
  }

  func testLowConfidenceOrNoSpeechSegmentsRemainUnstable() {
    let stabilizer = VoiceWhisperTextStabilizer()
    let weak = VoiceWhisperDecodedWindow(
      requestId: "weak",
      windowStartMillis: 0,
      windowEndMillis: 2_000,
      text: "maybe",
      segments: [
        VoiceWhisperTimedSegment(
          startMillis: 0,
          endMillis: 1_000,
          text: "maybe",
          averageLogProbability: -3.0,
          noSpeechProbability: 0.9
        )
      ],
      realTimeFactor: 0.2,
      final: false
    )

    _ = stabilizer.accept(weak)
    var repeated = weak
    repeated.requestId = "weak-2"
    let transcript = stabilizer.accept(repeated)

    XCTAssertEqual(transcript.stableText, "")
    XCTAssertFalse(transcript.unstableText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  func testDecoderOffsetsNativeSegmentsAndNormalizesText() {
    let result = VoiceNativeWhisperResult(
      codeValue: VoiceNativeWhisperCode.ok.rawValue,
      segments: [
        VoiceNativeWhisperSegment(
          startMillis: 100,
          endMillis: 600,
          text: " hello   world ",
          averageLogProbability: Float.nan,
          noSpeechProbability: 0.1
        )
      ],
      detectedLanguage: "en",
      timings: VoiceNativeWhisperTimings(
        sampleMillis: 1,
        encodeMillis: 2,
        decodeMillis: 3,
        totalMillis: 6,
        audioMillis: 1_000,
        realTimeFactor: 0.4
      ),
      aborted: false,
      message: nil
    )

    let decoded = VoiceWhisperSegmentDecoder.decode(
      requestId: "window-1",
      windowStartSample: 16_000,
      windowEndSampleExclusive: 32_000,
      result: result,
      final: false
    )

    XCTAssertEqual(decoded.windowStartMillis, 1_000)
    XCTAssertEqual(decoded.windowEndMillis, 2_000)
    XCTAssertEqual(decoded.text, "hello world")
    XCTAssertEqual(decoded.segments.singleValue().startMillis, 1_100)
    XCTAssertNil(decoded.segments.singleValue().averageLogProbability)
  }

  func testResetClearsRevisionAndStablePrefix() {
    let stabilizer = VoiceWhisperTextStabilizer(stabilityLagMillis: 0)
    _ = stabilizer.accept(window("hello world", startMillis: 0, windowEndMillis: 1_000, endMillis: 500))

    stabilizer.reset()
    let next = stabilizer.accept(window("new phrase", startMillis: 0, windowEndMillis: 1_000, endMillis: 500))

    XCTAssertEqual(next.revision, 1)
    XCTAssertFalse(next.displayText.contains("hello"))
  }

  private func window(
    _ text: String,
    startMillis: Int64,
    windowEndMillis: Int64,
    endMillis: Int64,
    final: Bool = false
  ) -> VoiceWhisperDecodedWindow {
    VoiceWhisperDecodedWindow(
      requestId: text,
      windowStartMillis: startMillis,
      windowEndMillis: windowEndMillis,
      text: text,
      segments: [
        VoiceWhisperTimedSegment(
          startMillis: startMillis,
          endMillis: endMillis,
          text: text,
          averageLogProbability: -0.2,
          noSpeechProbability: 0.05
        )
      ],
      realTimeFactor: 0.4,
      final: final
    )
  }
}
