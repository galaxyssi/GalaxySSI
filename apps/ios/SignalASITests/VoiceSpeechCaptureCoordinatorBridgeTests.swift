import XCTest
@testable import SignalASI

final class VoiceSpeechCaptureCoordinatorBridgeTests: XCTestCase {
  private var elapsedNs: Int64 = 1_000

  private func makeBridge(
    enabled: Bool = true
  ) -> (VoiceInteractionCoordinator, VoiceSpeechCaptureCoordinatorBridge) {
    let coordinator = VoiceInteractionCoordinator(
      elapsedClock: { [unowned self] in
        elapsedNs += 1
        return elapsedNs
      },
      sessionIdFactory: { "generated-session" }
    )
    let bridge = VoiceSpeechCaptureCoordinatorBridge(
      coordinator: coordinator,
      isCoordinatorEnabled: { enabled },
      elapsedClock: { [unowned self] in
        elapsedNs += 1
        return elapsedNs
      }
    )
    return (coordinator, bridge)
  }

  func testBeginCaptureUsesVoiceSettingsConfig() {
    let (coordinator, bridge) = makeBridge()
    let config = VoiceSpeechCaptureCoordinatorBridge.config(
      settings: VoiceSettings(
        wakeListeningEnabled: true,
        speechRecognitionEnabled: true,
        textToSpeechEnabled: true,
        autoSendTranscripts: true,
        preferredLocaleIdentifier: "zh-CN",
        targetContactId: "codex",
        speakReplies: false,
        routingMode: .contact
      ),
      source: "ios_wake_phrase"
    )

    let transition = bridge.begin(config: config)

    XCTAssertTrue(transition.accepted)
    XCTAssertEqual(transition.current.sessionId, "generated-session")
    XCTAssertEqual(coordinator.config()?.source, "ios_wake_phrase")
    XCTAssertEqual(coordinator.config()?.language, "zh-CN")
    XCTAssertEqual(coordinator.config()?.targetId, "codex")
    XCTAssertEqual(coordinator.config()?.routingMode, "contact")
    XCTAssertEqual(coordinator.config()?.speakReplies, false)
    XCTAssertEqual(coordinator.config()?.continueInBackground, true)
  }

  func testCaptureEventsAdvanceToListeningAndTrackPartialTranscript() {
    let (coordinator, bridge) = makeBridge()
    bridge.begin(config: VoiceSessionConfig(source: "ios_hold_to_talk", language: "en-US"))

    bridge.capturePrepared()
    bridge.speechStarted()
    let partial = bridge.transcriptPartial(" hello ", provider: iosSpeechProviderId, modelProfileId: "en-US")

    XCTAssertEqual(partial.current.phase, .listening)
    XCTAssertEqual(coordinator.snapshot().partialText, "hello")
    XCTAssertEqual(coordinator.snapshot().asrProvider, iosSpeechProviderId)
    XCTAssertEqual(coordinator.snapshot().modelProfileId, "en-US")
  }

  func testStoppedCaptureWithTranscriptFinalizesAndRoutesOnce() {
    let (coordinator, bridge) = makeBridge()
    bridge.begin(config: VoiceSessionConfig(source: "ios_hold_to_talk", language: "en-US"))
    bridge.capturePrepared()
    bridge.speechStarted()

    let final = bridge.finishStoppedCapture(transcript: " Open the timer ")
    let duplicateStop = bridge.finishStoppedCapture(transcript: "Open the timer")

    XCTAssertEqual(final.current.phase, .routing)
    XCTAssertEqual(final.current.finalText, "Open the timer")
    XCTAssertEqual(final.commands.routeFinalTranscriptCount, 1)
    XCTAssertFalse(duplicateStop.accepted)
    XCTAssertEqual(coordinator.snapshot().finalText, "Open the timer")
  }

  func testStoppedCaptureWithoutTranscriptCancelsSession() {
    let (_, bridge) = makeBridge()
    bridge.begin(config: VoiceSessionConfig(source: "ios_hold_to_talk", language: "en-US"))
    bridge.capturePrepared()
    bridge.speechStarted()

    let cancelled = bridge.finishStoppedCapture(transcript: "   ")

    XCTAssertEqual(cancelled.current.phase, .cancelled)
    XCTAssertEqual(cancelled.commands.cancelLegacyWorkCount, 1)
    XCTAssertEqual(cancelled.commands.first?.idempotencyKey, "generated-session:cancel")
    XCTAssertEqual(bridge.sessionId(), "")
  }

  func testFailureUsesCurrentCoordinatorPhaseAsStage() {
    let (_, bridge) = makeBridge()
    bridge.begin(config: VoiceSessionConfig(source: "ios_hold_to_talk", language: "en-US"))
    bridge.capturePrepared()
    bridge.speechStarted()

    let failed = bridge.failCurrent(code: "ios_speech_capture_failed", detail: "busy", recoverable: true)

    XCTAssertEqual(failed.current.phase, .failed)
    XCTAssertEqual(failed.current.failure?.stage, .listening)
    XCTAssertEqual(failed.current.failure?.detail, "busy")
    XCTAssertEqual(bridge.sessionId(), "")
  }

  func testDisabledBridgeRejectsWithoutMutatingCoordinator() {
    let (coordinator, bridge) = makeBridge(enabled: false)

    let begin = bridge.begin(config: VoiceSessionConfig(source: "ios_hold_to_talk", language: "en-US"))
    let prepared = bridge.capturePrepared()

    XCTAssertFalse(begin.accepted)
    XCTAssertFalse(prepared.accepted)
    XCTAssertEqual(coordinator.snapshot().phase, .idle)
    XCTAssertEqual(bridge.sessionId(), "")
  }
}

private extension Array where Element == VoiceInteractionCommand {
  var routeFinalTranscriptCount: Int {
    filter {
      if case .routeFinalTranscript(sessionId: _, transcript: _, idempotencyKey: _) = $0 { return true }
      return false
    }.count
  }

  var cancelLegacyWorkCount: Int {
    filter {
      if case .cancelLegacyWork(sessionId: _, reasonCode: _, idempotencyKey: _) = $0 { return true }
      return false
    }.count
  }
}
