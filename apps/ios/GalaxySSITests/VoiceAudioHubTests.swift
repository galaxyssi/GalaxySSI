import XCTest
@testable import GalaxySSI

final class VoiceAudioHubTests: XCTestCase {
  func testHubFansOutOnePcmStreamAndReturnsBoundedSpeechSnapshot() async {
    let recorder = FakePcmRecorder()
    let listener = RecordingListener()
    let hub = VoiceAudioHub(
      recorder: recorder,
      sessionIdFactory: { "pcm-session" },
      vadFactory: { ThresholdVad() }
    )
    guard let session = hub.start(
      config: VoiceAudioSessionConfig(
        capture: PcmCaptureConfig(sampleRateHz: 1_000, frameDurationMs: 20, maxDurationMs: 5_000),
        endpoint: AdaptiveEndpointConfig(
          noSpeechTimeoutMs: 1_500,
          minimumSpeechMs: 240,
          shortUtteranceSilenceMs: 350,
          normalUtteranceSilenceMs: 350,
          longUtteranceSilenceMs: 350,
          minTrailingSilenceMs: 350,
          maxTrailingSilenceMs: 1_200,
          maxDurationMs: 5_000,
          preRollMs: 200,
          postRollMs: 100
        ),
        autoEndpoint: true
      ),
      listener: listener
    ) else {
      XCTFail("Expected PCM session")
      return
    }

    await Task.yield()
    for index in 0..<15 {
      recorder.emit(frame(sequence: Int64(index), samples: Array(repeating: 0, count: 20)))
    }
    for index in 0..<20 {
      recorder.emit(frame(sequence: Int64(15 + index), samples: Array(repeating: 5_000, count: 20)))
    }
    for index in 0..<20 {
      recorder.emit(frame(sequence: Int64(35 + index), samples: Array(repeating: 0, count: 20)))
    }

    XCTAssertEqual(listener.speechStarts, 1)
    XCTAssertEqual(listener.endpoint, .trailingSilence)
    let partial = hub.snapshotWindow(session: session, maxDurationMs: 200)
    XCTAssertTrue(partial?.speechDetected ?? false)
    XCTAssertEqual(partial?.samples.count, 200)
    let result = await hub.stop(session: session, reason: .adaptiveEndpoint)
    XCTAssertNotNil(result)
    XCTAssertTrue(result?.snapshot.speechDetected ?? false)
    XCTAssertTrue((result?.snapshot.durationMs ?? 0) >= 600)
    XCTAssertTrue((result?.snapshot.durationMs ?? 0) <= 800)
    XCTAssertEqual(result?.stopReason, .adaptiveEndpoint)
  }

  private final class FakePcmRecorder: PcmRecorder {
    private let lock = NSLock()
    private var continuation: AsyncStream<AudioFrame>.Continuation?
    private var pendingFrames: [AudioFrame] = []
    private var state = PcmRecorderState()

    func start(config: PcmCaptureConfig) throws -> AsyncStream<AudioFrame> {
      locked {
        state = PcmRecorderState(phase: .recording, audioSource: "fake_pcm", inputRoute: "built_in_mic")
      }
      return AsyncStream { continuation in
        let buffered = locked { () -> [AudioFrame] in
          self.continuation = continuation
          let frames = self.pendingFrames
          self.pendingFrames.removeAll()
          return frames
        }
        buffered.forEach { continuation.yield($0) }
      }
    }

    func emit(_ frame: AudioFrame) {
      locked {
        if let continuation = continuation {
          continuation.yield(frame)
        } else {
          pendingFrames.append(frame)
        }
        state.currentAmplitude = frame.samples.prefix(frame.validSamples).map { abs(Int($0)) }.max() ?? 0
      }
    }

    func requestStop(reason: PcmStopReason) {
      locked {
        state.phase = .stopping
        state.stopReason = reason
        continuation?.finish()
      }
    }

    func stop(reason: PcmStopReason) async {
      requestStop(reason: reason)
      locked { state.phase = .stopped }
    }

    func currentState() -> PcmRecorderState {
      locked { state }
    }

    private func locked<T>(_ action: () -> T) -> T {
      lock.lock()
      defer { lock.unlock() }
      return action()
    }
  }

  private final class ThresholdVad: VoiceActivityDetector {
    private var active = false
    private var silenceFrames = 0

    func reset() {
      active = false
      silenceFrames = 0
    }

    func accept(_ frame: AudioFrame) -> VadDecision {
      let voiced = frame.samples.prefix(frame.validSamples).contains { abs(Int($0)) > 1_000 }
      let started = voiced && !active
      var ended = false
      if voiced {
        active = true
        silenceFrames = 0
      } else if active {
        silenceFrames += 1
        if silenceFrames >= 2 {
          active = false
          ended = true
        }
      }
      return VadDecision(
        probability: voiced ? 1 : 0,
        isSpeech: voiced,
        speechStarted: started,
        speechEndedCandidate: ended,
        rms: 0,
        peak: voiced ? 5_000 : 0,
        noiseFloorDb: -58
      )
    }
  }

  private final class RecordingListener: VoiceAudioHubListener {
    var speechStarts = 0
    var endpoint: EndpointReason?

    func onSpeechStarted(session: VoiceAudioSession, sequence: Int64) {
      speechStarts += 1
    }

    func onEndpoint(session: VoiceAudioSession, reason: EndpointReason) {
      endpoint = reason
    }
  }

  private func frame(sequence: Int64, samples: [Int]) -> AudioFrame {
    AudioFrame(
      sequence: sequence,
      captureTimeNanos: sequence * 20_000_000,
      samples: samples.map { Int16($0) }
    )
  }
}
