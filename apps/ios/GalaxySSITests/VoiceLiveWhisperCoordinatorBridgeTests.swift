import XCTest
@testable import GalaxySSI

final class VoiceLiveWhisperCoordinatorBridgeTests: XCTestCase {
  private var elapsedNs: Int64 = 1_000

  func testPartialUpdateDispatchesStableAndUnstableText() {
    let (coordinator, captureBridge) = makeBridge()
    beginListening(captureBridge)
    let bridge = VoiceLiveWhisperCoordinatorBridge(coordinatorBridge: captureBridge)

    let transitions = bridge.apply(
      update(stable: " hello ", unstable: " wor", revision: 3, final: false)
    )

    XCTAssertEqual(transitions.count, 2)
    XCTAssertEqual(coordinator.snapshot().stableText, "hello")
    XCTAssertEqual(coordinator.snapshot().partialText, "hello wor")
    XCTAssertEqual(coordinator.snapshot().asrProvider, voiceLocalWhisperProviderId)
    XCTAssertEqual(coordinator.snapshot().modelProfileId, "tiny")
  }

  func testFinalUpdateRoutesBestTranscriptOnce() {
    let (coordinator, captureBridge) = makeBridge()
    beginListening(captureBridge)
    let bridge = VoiceLiveWhisperCoordinatorBridge(coordinatorBridge: captureBridge)

    let transitions = bridge.apply(
      update(stable: " hello world ", unstable: "", revision: 7, final: true)
    )
    let duplicate = bridge.apply(
      update(stable: " hello world ", unstable: "", revision: 8, final: true)
    )

    XCTAssertEqual(transitions.count, 1)
    XCTAssertEqual(transitions.first?.current.phase, .routing)
    XCTAssertEqual(routeFinalTranscriptCount(transitions.first?.commands ?? []), 1)
    XCTAssertEqual(coordinator.snapshot().finalText, "hello world")
    XCTAssertTrue(duplicate.isEmpty)
  }

  func testEmptyNonFinalUpdateDoesNotMutateCoordinator() {
    let (coordinator, captureBridge) = makeBridge()
    beginListening(captureBridge)
    let before = coordinator.snapshot()
    let bridge = VoiceLiveWhisperCoordinatorBridge(coordinatorBridge: captureBridge)

    let transitions = bridge.apply(
      update(stable: "   ", unstable: "  ", revision: 1, final: false)
    )

    XCTAssertTrue(transitions.isEmpty)
    XCTAssertEqual(coordinator.snapshot(), before)
  }

  private func makeBridge() -> (VoiceInteractionCoordinator, VoiceSpeechCaptureCoordinatorBridge) {
    let coordinator = VoiceInteractionCoordinator(
      elapsedClock: { [unowned self] in
        elapsedNs += 1
        return elapsedNs
      },
      sessionIdFactory: { "generated-session" }
    )
    let bridge = VoiceSpeechCaptureCoordinatorBridge(
      coordinator: coordinator,
      isCoordinatorEnabled: { true },
      elapsedClock: { [unowned self] in
        elapsedNs += 1
        return elapsedNs
      },
      latencyTracer: nil
    )
    return (coordinator, bridge)
  }

  private func beginListening(_ bridge: VoiceSpeechCaptureCoordinatorBridge) {
    bridge.begin(config: VoiceSessionConfig(source: "ios_local_whisper", language: "en-US"))
    bridge.capturePrepared()
    bridge.speechStarted()
  }

  private func update(
    stable: String,
    unstable: String,
    revision: Int,
    final: Bool
  ) -> VoiceLiveWhisperTranscriptUpdate {
    VoiceLiveWhisperTranscriptUpdate(
      voiceSessionId: "voice-1",
      transcript: VoiceWhisperStabilizedTranscript(
        stableText: stable,
        unstableText: unstable,
        revision: revision,
        final: final
      ),
      modelProfileId: "tiny",
      realTimeFactor: 0.25
    )
  }

  private func routeFinalTranscriptCount(_ commands: [VoiceInteractionCommand]) -> Int {
    commands.filter {
      if case .routeFinalTranscript(sessionId: _, transcript: _, idempotencyKey: _) = $0 { return true }
      return false
    }.count
  }
}
