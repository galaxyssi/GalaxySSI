import XCTest
@testable import GalaxySSI

final class VoiceLiveWhisperCaptureControllerTests: XCTestCase {
  private var elapsedNs: Int64 = 1_000

  func testSpeechAudioLevelOffersNewestRequestedWindow() {
    let session = FakeCaptureLiveWhisperSession(modelProfileId: "tiny")
    session.nextWindows = [3_000]
    let controller = controller(session: session)
    var requestedWindows: [Int64] = []

    XCTAssertTrue(
      controller.start(
        voiceSessionId: "voice-1",
        settings: settings(),
        scheduler: NoopCaptureScheduler()
      )
    )
    controller.handleAudioLevel(isSpeech: true, nowMillis: 1_500) { windowMillis in
      requestedWindows.append(windowMillis)
      return Self.snapshot(sampleCount: 100)
    }
    controller.handleSpeechStarted(nowMillis: 1_000)
    controller.handleAudioLevel(isSpeech: false, nowMillis: 2_000) { windowMillis in
      requestedWindows.append(windowMillis)
      return Self.snapshot(sampleCount: 100)
    }
    controller.handleAudioLevel(isSpeech: true, nowMillis: 2_500) { windowMillis in
      requestedWindows.append(windowMillis)
      return Self.snapshot(sampleCount: 100)
    }

    XCTAssertEqual(session.capturedAudioMillis, [1_500])
    XCTAssertEqual(requestedWindows, [3_000])
    XCTAssertEqual(session.offeredPartials.count, 1)
  }

  func testUpdatesAreBridgedIntoVoiceCoordinator() {
    let (coordinator, captureBridge) = makeBridge()
    beginListening(captureBridge)
    let session = FakeCaptureLiveWhisperSession(modelProfileId: "tiny")
    var transitions: [VoiceInteractionTransition] = []
    let controller = VoiceLiveWhisperCaptureController(
      sessionBuilder: { _, _, _, _, onUpdate in
        session.onUpdate = onUpdate
        return session
      },
      coordinatorBridge: VoiceLiveWhisperCoordinatorBridge(coordinatorBridge: captureBridge),
      transitionHandler: { transitions.append($0) }
    )

    XCTAssertTrue(
      controller.start(
        voiceSessionId: "voice-1",
        settings: settings(),
        scheduler: NoopCaptureScheduler()
      )
    )
    session.emit(stable: "hello", unstable: " wor", revision: 1, final: false)

    XCTAssertEqual(coordinator.snapshot().stableText, "hello")
    XCTAssertEqual(coordinator.snapshot().partialText, "hello wor")
    XCTAssertEqual(transitions.count, 2)

    session.emit(stable: "hello world", unstable: "", revision: 2, final: true)

    XCTAssertEqual(coordinator.snapshot().finalText, "hello world")
    XCTAssertEqual(routeFinalTranscriptCount(transitions.last?.commands ?? []), 1)
  }

  func testUpdateHandlerCanBeReplacedForLiveDisplayText() {
    let session = FakeCaptureLiveWhisperSession(modelProfileId: "tiny")
    let controller = controller(session: session)
    var displayTexts: [String] = []
    controller.setUpdateHandler { update in
      displayTexts.append(update.transcript.displayText)
    }

    XCTAssertTrue(
      controller.start(
        voiceSessionId: "voice-1",
        settings: settings(),
        scheduler: NoopCaptureScheduler()
      )
    )
    session.emit(stable: "local", unstable: " whisper", revision: 1, final: false)

    XCTAssertEqual(displayTexts, ["local whisper"])
  }

  func testTransitionHandlerCanBeReplacedForFinalCommands() {
    let (_, captureBridge) = makeBridge()
    beginListening(captureBridge)
    let session = FakeCaptureLiveWhisperSession(modelProfileId: "tiny")
    let controller = VoiceLiveWhisperCaptureController(
      sessionBuilder: { _, _, _, _, onUpdate in
        session.onUpdate = onUpdate
        return session
      },
      coordinatorBridge: VoiceLiveWhisperCoordinatorBridge(coordinatorBridge: captureBridge)
    )
    var transitions: [VoiceInteractionTransition] = []
    controller.setTransitionHandler { transitions.append($0) }

    XCTAssertTrue(
      controller.start(
        voiceSessionId: "voice-1",
        settings: settings(),
        scheduler: NoopCaptureScheduler()
      )
    )
    session.emit(stable: "final command", unstable: "", revision: 1, final: true)

    XCTAssertEqual(routeFinalTranscriptCount(transitions.last?.commands ?? []), 1)
  }

  func testFinishReturnsNativeResultAndCloseClosesSession() async throws {
    let session = FakeCaptureLiveWhisperSession(modelProfileId: "tiny")
    session.finalResult = Self.nativeResult("done")
    let controller = controller(session: session)
    XCTAssertTrue(
      controller.start(
        voiceSessionId: "voice-1",
        settings: settings(),
        scheduler: NoopCaptureScheduler()
      )
    )

    let final = try await controller.finish(Self.snapshot(sampleCount: 1_600))
    controller.close()

    XCTAssertEqual(final?.text, "done")
    XCTAssertEqual(session.finishedSnapshots.count, 1)
    XCTAssertEqual(session.closeCount, 1)
    XCTAssertNil(controller.activeModelProfileId)
  }

  private func controller(session: FakeCaptureLiveWhisperSession) -> VoiceLiveWhisperCaptureController {
    VoiceLiveWhisperCaptureController(
      sessionBuilder: { _, _, _, _, onUpdate in
        session.onUpdate = onUpdate
        return session
      },
      coordinatorBridge: VoiceLiveWhisperCoordinatorBridge(
        emitPartial: { _, _, _ in Self.rejectedTransition() },
        emitStable: { _, _, _ in Self.rejectedTransition() },
        emitFinal: { _, _, _ in Self.rejectedTransition() }
      )
    )
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

  private func settings() -> VoiceSettings {
    VoiceSettings(
      wakeListeningEnabled: false,
      speechRecognitionEnabled: true,
      textToSpeechEnabled: true,
      autoSendTranscripts: false,
      preferredLocaleIdentifier: "en-US",
      asrModelId: "tiny"
    )
  }

  private static func snapshot(sampleCount: Int) -> PcmSnapshot {
    PcmSnapshot(
      samples: Array(repeating: Int16(7), count: sampleCount),
      sampleRateHz: 16_000,
      speechDetected: true,
      speechStartSample: 0,
      speechEndSampleExclusive: Int64(sampleCount),
      captureStartSample: 0,
      captureEndSampleExclusive: Int64(sampleCount)
    )
  }

  fileprivate static func nativeResult(_ text: String) -> VoiceNativeWhisperResult {
    VoiceNativeWhisperResult(
      codeValue: VoiceNativeWhisperCode.ok.rawValue,
      segments: [
        VoiceNativeWhisperSegment(
          startMillis: 0,
          endMillis: 100,
          text: text,
          averageLogProbability: -0.1,
          noSpeechProbability: 0
        )
      ],
      detectedLanguage: "en",
      timings: .empty,
      aborted: false,
      message: nil
    )
  }

  private static func rejectedTransition() -> VoiceInteractionTransition {
    VoiceInteractionTransition(
      previous: VoiceInteractionState(),
      current: VoiceInteractionState(),
      accepted: false
    )
  }

  private func routeFinalTranscriptCount(_ commands: [VoiceInteractionCommand]) -> Int {
    commands.filter {
      if case .routeFinalTranscript(sessionId: _, transcript: _, idempotencyKey: _) = $0 { return true }
      return false
    }.count
  }
}

private final class FakeCaptureLiveWhisperSession: VoiceLiveWhisperSessionHandling {
  let modelProfileId: String
  var nextWindows: [Int64?] = []
  var finalResult = VoiceLiveWhisperCaptureControllerTests.nativeResult("final")
  var onUpdate: ((VoiceLiveWhisperTranscriptUpdate) -> Void)?
  private(set) var capturedAudioMillis: [Int64] = []
  private(set) var offeredPartials: [PcmSnapshot] = []
  private(set) var finishedSnapshots: [PcmSnapshot] = []
  private(set) var closeCount = 0

  init(modelProfileId: String) {
    self.modelProfileId = modelProfileId
  }

  func nextPartialWindowMillis(capturedAudioMillis: Int64) -> Int64? {
    self.capturedAudioMillis.append(capturedAudioMillis)
    return nextWindows.isEmpty ? nil : nextWindows.removeFirst() ?? nil
  }

  func offerPartial(_ snapshot: PcmSnapshot) {
    offeredPartials.append(snapshot)
  }

  func finish(_ snapshot: PcmSnapshot) async throws -> VoiceNativeWhisperResult {
    finishedSnapshots.append(snapshot)
    return finalResult
  }

  func close() {
    closeCount += 1
  }

  func emit(stable: String, unstable: String, revision: Int, final: Bool) {
    onUpdate?(
      VoiceLiveWhisperTranscriptUpdate(
        voiceSessionId: "voice-1",
        transcript: VoiceWhisperStabilizedTranscript(
          stableText: stable,
          unstableText: unstable,
          revision: revision,
          final: final
        ),
        modelProfileId: modelProfileId,
        realTimeFactor: 0.2
      )
    )
  }
}

private final class NoopCaptureScheduler: VoiceWhisperDecodeScheduling {
  func submit(_ request: VoiceScheduledWhisperDecode) async -> VoiceScheduledWhisperResult {
    .dropped(request: request, reason: .schedulerClosed)
  }

  func cancelSession(_ sessionId: String) {}
  func queueSnapshot() -> VoiceWhisperDecodeQueueSnapshot { VoiceWhisperDecodeQueueSnapshot() }
  func close() {}
}
