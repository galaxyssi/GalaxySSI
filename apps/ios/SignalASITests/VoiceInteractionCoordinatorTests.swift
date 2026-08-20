import XCTest
@testable import SignalASI

final class VoiceInteractionCoordinatorTests: XCTestCase {
  private var elapsedNs: Int64 = 1_000

  private func coordinator() -> VoiceInteractionCoordinator {
    VoiceInteractionCoordinator(
      elapsedClock: { [unowned self] in
        elapsedNs += 1
        return elapsedNs
      },
      sessionIdFactory: { "generated-session" }
    )
  }

  private func begin(_ coordinator: VoiceInteractionCoordinator, id: String = "voice-1") -> String {
    let transition = coordinator.begin(
      config: VoiceSessionConfig(
        requestedSessionId: id,
        source: "chat_hold_to_talk",
        language: "zh-CN"
      )
    )
    XCTAssertTrue(transition.accepted)
    return transition.current.sessionId
  }

  @discardableResult
  private func reachFinal(
    _ coordinator: VoiceInteractionCoordinator,
    sessionId: String,
    text: String = "hello"
  ) -> VoiceInteractionTransition {
    coordinator.dispatch(.capturePrepared(sessionId: sessionId))
    elapsedNs += 1
    coordinator.dispatch(.speechStarted(sessionId: sessionId, atElapsedNs: elapsedNs))
    elapsedNs += 1
    coordinator.dispatch(.speechEnded(sessionId: sessionId, atElapsedNs: elapsedNs))
    coordinator.dispatch(.finalizationStarted(sessionId: sessionId))
    return coordinator.dispatch(
      .transcriptFinal(
        sessionId: sessionId,
        value: TranscriptHypothesis(
          text: text,
          revision: 1,
          provider: "whisper.cpp",
          modelProfileId: "tiny"
        )
      )
    )
  }

  func testLocalActionFollowsCanonicalStatePath() {
    let coordinator = coordinator()
    let sessionId = begin(coordinator)
    let final = reachFinal(coordinator, sessionId: sessionId)

    XCTAssertEqual(final.current.phase, .routing)
    XCTAssertEqual(final.commands.routeFinalTranscriptCount, 1)
    coordinator.dispatch(
      .routeSelected(
        sessionId: sessionId,
        decision: VoiceRouteDecision(kind: .localAction, targetId: "timer")
      )
    )
    let completed = coordinator.dispatch(.localActionCompleted(sessionId: sessionId))

    XCTAssertEqual(completed.current.phase, .completed)
    XCTAssertFalse(completed.current.canInterrupt)
    XCTAssertEqual(coordinator.result()?.completed, true)
  }

  func testDuplicateFinalNeverCreatesASecondRoutingCommand() {
    let coordinator = coordinator()
    let sessionId = begin(coordinator)
    let first = reachFinal(coordinator, sessionId: sessionId)
    let duplicate = coordinator.dispatch(
      .transcriptFinal(
        sessionId: sessionId,
        value: TranscriptHypothesis(text: "hello", revision: 1)
      )
    )

    XCTAssertEqual(first.commands.count, 1)
    XCTAssertTrue(duplicate.commands.isEmpty)
    XCTAssertFalse(duplicate.accepted)
    XCTAssertEqual(coordinator.snapshot().finalText, "hello")
  }

  func testCorrectionUpdatesTranscriptWithoutReenteringRouting() {
    let coordinator = coordinator()
    let sessionId = begin(coordinator)
    reachFinal(coordinator, sessionId: sessionId)
    coordinator.dispatch(
      .routeSelected(
        sessionId: sessionId,
        decision: VoiceRouteDecision(kind: .cloudModel, targetId: "provider")
      )
    )
    coordinator.dispatch(.modelDelta(sessionId: sessionId, text: "answer"))
    coordinator.dispatch(.completed(sessionId: sessionId))

    let correction = coordinator.dispatch(
      .transcriptCorrected(
        sessionId: sessionId,
        original: TranscriptHypothesis(text: "hello", revision: 1),
        corrected: TranscriptHypothesis(text: "hello world", revision: 2)
      )
    )

    XCTAssertTrue(correction.accepted)
    XCTAssertEqual(correction.current.phase, .completed)
    XCTAssertEqual(correction.current.correctedText, "hello world")
    XCTAssertTrue(correction.commands.isEmpty)
  }

  func testRemoteAgentProgressUsesRealAcceptedAndProgressEvents() {
    let coordinator = coordinator()
    let sessionId = begin(coordinator)
    reachFinal(coordinator, sessionId: sessionId)
    coordinator.dispatch(
      .routeSelected(
        sessionId: sessionId,
        decision: VoiceRouteDecision(kind: .remoteAgent, targetId: "codex")
      )
    )

    XCTAssertEqual(coordinator.snapshot().phase, .startingAgent)
    coordinator.dispatch(.agentAccepted(sessionId: sessionId, runId: "run-1"))
    let progress = coordinator.dispatch(.agentProgress(sessionId: sessionId, runId: "run-1"))

    XCTAssertEqual(progress.current.phase, .agentRunning)
    XCTAssertEqual(progress.current.agentRunId, "run-1")
  }

  func testRemoteAgentCancellationUsesCancelledTerminalState() {
    let coordinator = coordinator()
    let sessionId = begin(coordinator)
    reachFinal(coordinator, sessionId: sessionId)
    coordinator.dispatch(
      .routeSelected(
        sessionId: sessionId,
        decision: VoiceRouteDecision(kind: .remoteAgent, targetId: "codex")
      )
    )
    coordinator.dispatch(.agentAccepted(sessionId: sessionId, runId: "run-1"))

    let cancelled = coordinator.dispatch(.cancelled(sessionId: sessionId, reasonCode: "remote_agent_cancelled"))

    XCTAssertEqual(cancelled.current.phase, .cancelled)
    XCTAssertEqual(coordinator.result()?.cancelled, true)
  }

  func testCancellationIsTerminalAndEmitsOneLegacyCancelCommand() {
    let coordinator = coordinator()
    let sessionId = begin(coordinator)
    coordinator.dispatch(.capturePrepared(sessionId: sessionId))

    let cancelled = coordinator.cancel(reasonCode: "activity_destroyed")
    let duplicate = coordinator.cancel(reasonCode: "activity_destroyed")

    XCTAssertEqual(cancelled.current.phase, .cancelled)
    XCTAssertEqual(cancelled.commands.cancelLegacyWorkCount, 1)
    XCTAssertFalse(duplicate.accepted)
    XCTAssertTrue(duplicate.commands.isEmpty)
    XCTAssertEqual(coordinator.result()?.cancelled, true)
  }

  func testActiveSessionCannotBeRestartedByUIRecreation() {
    let coordinator = coordinator()
    let sessionId = begin(coordinator)
    coordinator.dispatch(.capturePrepared(sessionId: sessionId))
    let before = coordinator.snapshot()

    let duplicateBegin = coordinator.begin(
      config: VoiceSessionConfig(requestedSessionId: "voice-2", source: "activity_recreation")
    )

    XCTAssertFalse(duplicateBegin.accepted)
    XCTAssertEqual(before, coordinator.snapshot())
  }

  func testObserversReattachToCurrentStateWithoutReplayingCommands() {
    let coordinator = coordinator()
    let sessionId = begin(coordinator)
    reachFinal(coordinator, sessionId: sessionId)
    var observed: [VoiceInteractionState] = []

    let observerId = coordinator.observe { observed.append($0) }

    XCTAssertEqual(observed.single?.phase, .routing)
    XCTAssertNotNil(coordinator.snapshot().finalText)
    coordinator.removeObserver(observerId)
    coordinator.dispatch(
      .routeSelected(
        sessionId: sessionId,
        decision: VoiceRouteDecision(kind: .cloudModel)
      )
    )
    XCTAssertEqual(observed.count, 1)
  }

  func testFailingObserverCannotBreakSessionLifecycle() {
    let coordinator = coordinator()
    coordinator.observe { _ in throw ObserverFailure.expected }

    let sessionId = begin(coordinator)
    let transition = coordinator.dispatch(.capturePrepared(sessionId: sessionId))

    XCTAssertTrue(transition.accepted)
    XCTAssertEqual(coordinator.snapshot().phase, .listening)
  }

  func testLateEventFromCompletedSessionCannotMutateNextSession() {
    let coordinator = coordinator()
    let firstSession = begin(coordinator, id: "voice-1")
    reachFinal(coordinator, sessionId: firstSession)
    coordinator.dispatch(.completed(sessionId: firstSession))
    let secondSession = begin(coordinator, id: "voice-2")

    let lateEvent = coordinator.dispatch(
      .failed(
        sessionId: firstSession,
        failure: VoiceFailure(code: "late_failure", recoverable: true, stage: .routing)
      )
    )

    XCTAssertFalse(lateEvent.accepted)
    XCTAssertEqual(coordinator.snapshot().sessionId, secondSession)
    XCTAssertEqual(coordinator.snapshot().phase, .preparing)
  }

  func testEventFromAnotherSessionIsRejected() {
    let coordinator = coordinator()
    begin(coordinator)

    let transition = coordinator.dispatch(
      .failed(
        sessionId: "another-session",
        failure: VoiceFailure(code: "wrong_session", recoverable: false, stage: .preparing)
      )
    )

    XCTAssertFalse(transition.accepted)
    XCTAssertEqual(coordinator.snapshot().phase, .preparing)
  }

  func testVoiceInteractionModelsUseAndroidWireNames() throws {
    let state = VoiceInteractionState(
      sessionId: "voice-1",
      phase: .routing,
      partialText: "hel",
      stableText: "hello",
      finalText: "hello",
      finalTranscriptRevision: 2,
      asrProvider: "whisper.cpp",
      modelProfileId: "tiny",
      route: VoiceRouteDecision(kind: .remoteAgent, targetId: "codex", reasonCode: "delegate"),
      agentRunId: "run-1",
      canInterrupt: false,
      revision: 3,
      createdAtElapsedNs: 100,
      updatedAtElapsedNs: 200
    )
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(state)) as? [String: Any])
    let route = try XCTUnwrap(object["route"] as? [String: Any])

    XCTAssertEqual(object["session_id"] as? String, "voice-1")
    XCTAssertEqual(object["phase"] as? String, "ROUTING")
    XCTAssertEqual((object["final_transcript_revision"] as? NSNumber)?.intValue, 2)
    XCTAssertEqual(object["asr_provider"] as? String, "whisper.cpp")
    XCTAssertEqual(object["model_profile_id"] as? String, "tiny")
    XCTAssertEqual(route["kind"] as? String, "REMOTE_AGENT")
    XCTAssertEqual(route["target_id"] as? String, "codex")
  }

  func testVoiceFeatureFlagPersistsCoordinatorSetting() {
    let suiteName = "signalasi-voice-flags-\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    XCTAssertTrue(VoiceFeatureFlags.isCoordinatorEnabled(userDefaults: userDefaults, defaultEnabled: true))
    VoiceFeatureFlags.setCoordinatorEnabled(false, userDefaults: userDefaults)
    XCTAssertFalse(VoiceFeatureFlags.isCoordinatorEnabled(userDefaults: userDefaults, defaultEnabled: true))
    VoiceFeatureFlags.setCoordinatorEnabled(true, userDefaults: userDefaults)
    XCTAssertTrue(VoiceFeatureFlags.isCoordinatorEnabled(userDefaults: userDefaults, defaultEnabled: false))
  }

  func testVoiceFeatureFlagPersistsPcmCaptureSetting() {
    let suiteName = "signalasi-voice-pcm-flags-\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    XCTAssertTrue(VoiceFeatureFlags.isPcmCaptureEnabled(userDefaults: userDefaults, defaultEnabled: true))
    VoiceFeatureFlags.setPcmCaptureEnabled(false, userDefaults: userDefaults)
    XCTAssertFalse(VoiceFeatureFlags.isPcmCaptureEnabled(userDefaults: userDefaults, defaultEnabled: true))
    VoiceFeatureFlags.setPcmCaptureEnabled(true, userDefaults: userDefaults)
    XCTAssertTrue(VoiceFeatureFlags.isPcmCaptureEnabled(userDefaults: userDefaults, defaultEnabled: false))
  }

  func testVoiceFeatureFlagPersistsLocalWhisperRuntimeV2Setting() {
    let suiteName = "signalasi-voice-whisper-runtime-flags-\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    XCTAssertTrue(VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(userDefaults: userDefaults, defaultEnabled: true))
    VoiceFeatureFlags.setLocalWhisperRuntimeV2Enabled(false, userDefaults: userDefaults)
    XCTAssertFalse(VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(userDefaults: userDefaults, defaultEnabled: true))
    VoiceFeatureFlags.setLocalWhisperRuntimeV2Enabled(true, userDefaults: userDefaults)
    XCTAssertTrue(VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(userDefaults: userDefaults, defaultEnabled: false))
  }

  func testVoiceFeatureFlagPersistsWhisperSecondPassSetting() {
    let suiteName = "signalasi-voice-whisper-second-pass-flags-\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    XCTAssertTrue(VoiceFeatureFlags.isWhisperSecondPassEnabled(userDefaults: userDefaults, defaultEnabled: true))
    VoiceFeatureFlags.setWhisperSecondPassEnabled(false, userDefaults: userDefaults)
    XCTAssertFalse(VoiceFeatureFlags.isWhisperSecondPassEnabled(userDefaults: userDefaults, defaultEnabled: true))
    VoiceFeatureFlags.setWhisperSecondPassEnabled(true, userDefaults: userDefaults)
    XCTAssertTrue(VoiceFeatureFlags.isWhisperSecondPassEnabled(userDefaults: userDefaults, defaultEnabled: false))
    VoiceFeatureFlags.resetWhisperSecondPassEnabled(userDefaults: userDefaults)
    XCTAssertFalse(VoiceFeatureFlags.isWhisperSecondPassEnabled(userDefaults: userDefaults, defaultEnabled: false))
  }

  func testVoiceFeatureFlagsPersistAdvancedASRSettings() {
    let suiteName = "signalasi-voice-advanced-asr-flags-\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    XCTAssertTrue(VoiceFeatureFlags.isOnlineRealtimeASREnabled(userDefaults: userDefaults, defaultEnabled: true))
    XCTAssertFalse(VoiceFeatureFlags.isRemoteWhisperNodeEnabled(userDefaults: userDefaults, defaultEnabled: false))

    VoiceFeatureFlags.setOnlineRealtimeASREnabled(false, userDefaults: userDefaults)
    VoiceFeatureFlags.setRemoteWhisperNodeEnabled(true, userDefaults: userDefaults)

    XCTAssertFalse(VoiceFeatureFlags.isOnlineRealtimeASREnabled(userDefaults: userDefaults, defaultEnabled: true))
    XCTAssertTrue(VoiceFeatureFlags.isRemoteWhisperNodeEnabled(userDefaults: userDefaults, defaultEnabled: false))

    VoiceFeatureFlags.resetOnlineRealtimeASREnabled(userDefaults: userDefaults)
    VoiceFeatureFlags.resetRemoteWhisperNodeEnabled(userDefaults: userDefaults)

    XCTAssertFalse(VoiceFeatureFlags.isOnlineRealtimeASREnabled(userDefaults: userDefaults, defaultEnabled: false))
    XCTAssertTrue(VoiceFeatureFlags.isRemoteWhisperNodeEnabled(userDefaults: userDefaults, defaultEnabled: true))
  }

}

private enum ObserverFailure: Error {
  case expected
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

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
