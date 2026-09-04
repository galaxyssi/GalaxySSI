import AVFoundation
import XCTest
@testable import GalaxySSI

final class VoicePcmTapPipelineTests: XCTestCase {
  func testAudioFrameAndSnapshotCanWipePcmPlaintext() {
    var released: [Int16] = []
    let frame = AudioFrame(
      sequence: 1,
      captureTimeNanos: 2,
      samples: [10, 20, 30],
      releaseAction: { released = $0 }
    )
    frame.close()
    frame.close()

    XCTAssertEqual(released, [0, 0, 0])
    XCTAssertTrue(frame.samples.isEmpty)

    var snapshot = PcmSnapshot(
      samples: [40, 50],
      sampleRateHz: 16_000,
      speechDetected: true,
      speechStartSample: 0,
      speechEndSampleExclusive: 2,
      captureStartSample: 0,
      captureEndSampleExclusive: 2
    )
    snapshot.wipeSensitive()

    XCTAssertTrue(snapshot.samples.isEmpty)
    XCTAssertNil(snapshot.speechStartSample)
    XCTAssertNil(snapshot.speechEndSampleExclusive)
  }

  func testTapPipelineConvertsAudioBufferAndMarksSpeechSegment() throws {
    let pipeline = VoicePcmTapPipeline(
      config: VoiceAudioSessionConfig(
        capture: PcmCaptureConfig(sampleRateHz: 1_000, frameDurationMs: 20, maxDurationMs: 5_000),
        endpoint: AdaptiveEndpointConfig(
          noSpeechTimeoutMs: 1_500,
          minimumSpeechMs: 20,
          shortUtteranceSilenceMs: 350,
          normalUtteranceSilenceMs: 350,
          longUtteranceSilenceMs: 350,
          minTrailingSilenceMs: 350,
          maxTrailingSilenceMs: 1_200,
          maxDurationMs: 5_000
        ),
        autoEndpoint: true
      ),
      vad: AlwaysSpeechVad(),
      elapsedClock: { 42 }
    )
    let buffer = try audioBuffer(values: [0.0, 0.5, -0.5, 1.0])

    let update = pipeline.accept(buffer: buffer)
    let snapshot = pipeline.snapshot()
    let partial = pipeline.snapshotWindow(maxDurationMs: 1)

    XCTAssertEqual(update?.frame.captureTimeNanos, 42)
    XCTAssertEqual(update?.frame.samples.count, 4)
    XCTAssertLessThanOrEqual(abs(Int(update?.frame.samples[1] ?? 0) - 16_384), 1)
    XCTAssertTrue(update?.endpoint.speechStarted ?? false)
    XCTAssertTrue(snapshot.speechDetected)
    XCTAssertEqual(snapshot.samples.count, 4)
    XCTAssertEqual(partial.samples.count, 1)
  }

  private func audioBuffer(values: [Float]) throws -> AVAudioPCMBuffer {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 1_000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)))
    buffer.frameLength = AVAudioFrameCount(values.count)
    let channel = try XCTUnwrap(buffer.floatChannelData?[0])
    for index in values.indices {
      channel[index] = values[index]
    }
    return buffer
  }

  private final class AlwaysSpeechVad: VoiceActivityDetector {
    private var started = false

    func reset() {
      started = false
    }

    func accept(_ frame: AudioFrame) -> VadDecision {
      let first = !started
      started = true
      return VadDecision(
        probability: 1,
        isSpeech: true,
        speechStarted: first,
        speechEndedCandidate: false,
        rms: 0.5,
        peak: 16_384,
        noiseFloorDb: -58
      )
    }
  }
}
