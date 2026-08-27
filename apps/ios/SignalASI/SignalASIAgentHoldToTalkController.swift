import Foundation
import SwiftUI
import UIKit

struct SignalASIAgentHoldToTalkMessages {
  var permissionDenied: String
  var speechDisabled: String
  var speechUnavailable: String
  var noSpeech: String
  var tooShort: String
  var cancelled: String

  static let `default` = SignalASIAgentHoldToTalkMessages(
    permissionDenied: "Microphone or speech permission is missing.",
    speechDisabled: "Speech recognition is turned off.",
    speechUnavailable: "Speech recognition could not start.",
    noSpeech: "No speech captured.",
    tooShort: "Hold a little longer.",
    cancelled: "Voice cancelled."
  )
}

@MainActor
final class SignalASIAgentHoldToTalkController: ObservableObject {
  @Published private(set) var isPending = false
  @Published private(set) var isRecording = false
  @Published private(set) var cancelPending = false
  @Published private(set) var transcript = ""
  @Published private(set) var stableTranscript = ""
  @Published private(set) var unstableTranscript = ""
  @Published private(set) var elapsedLabel = "00:00"
  @Published private(set) var waveformPhase = 0.0
  @Published private(set) var waveformAmplitude = 0.0
  @Published private(set) var statusMessage = ""
  @Published private(set) var correctionReview: VoiceTranscriptCorrectionReview?

  private let speech = SpeechCaptureService()
  private var holdTask: Task<Void, Never>?
  private var timer: Timer?
  private var startedAt: Date?
  private var touchActive = false
  private var lastMessages = SignalASIAgentHoldToTalkMessages.default
  private var voiceSettings = VoiceSettings.default
  private var pendingSend = false
  private var deliveredThisCapture = false
  private var deliveredCommandKeys: Set<String> = []
  private var deferredTranscript: String?
  private var deferredSessionId = ""
  private var onRecordingStarted: (() -> Void)?
  private var onFinishedTranscript: ((SignalASIVoiceTranscriptSubmission) -> Void)?
  private var onCaptureCancelled: (() -> Void)?

  private static let holdStartDelayNs: UInt64 = 280_000_000
  private static let cancelThreshold: CGFloat = 56
  private static let minimumSendDuration: TimeInterval = 0.8
  private static let maximumDuration: TimeInterval = 120

  func dragChanged(
    translation: CGSize,
    settings: VoiceSettings,
    messages: SignalASIAgentHoldToTalkMessages,
    onStart: @escaping () -> Void,
    onFinish: @escaping (SignalASIVoiceTranscriptSubmission) -> Void,
    onCancel: @escaping () -> Void
  ) {
    if !touchActive {
      touchActive = true
      beginPending(
        settings: settings,
        messages: messages,
        onStart: onStart,
        onFinish: onFinish,
        onCancel: onCancel
      )
    }
    updateCancelState(translation: translation)
  }

  func dragEnded(translation: CGSize) {
    let shouldCancel = cancelPending || translation.height <= -Self.cancelThreshold
    touchActive = false
    holdTask?.cancel()
    holdTask = nil

    if isPending && !isRecording {
      speech.cancel()
      resetIdle(keepStatus: true)
      return
    }

    guard isRecording else {
      resetIdle(keepStatus: true)
      return
    }

    let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
    if shouldCancel {
      finish(send: false, status: lastMessages.cancelled)
    } else if elapsed < Self.minimumSendDuration {
      finish(send: false, status: lastMessages.tooShort)
    } else {
      finish(send: true, status: "")
    }
  }

  func cancelFromView() {
    touchActive = false
    holdTask?.cancel()
    holdTask = nil
    if isRecording {
      finish(send: false, status: lastMessages.cancelled)
    } else {
      speech.cancel()
      resetIdle(keepStatus: false)
    }
  }

  private func beginPending(
    settings: VoiceSettings,
    messages: SignalASIAgentHoldToTalkMessages,
    onStart: @escaping () -> Void,
    onFinish: @escaping (SignalASIVoiceTranscriptSubmission) -> Void,
    onCancel: @escaping () -> Void
  ) {
    isPending = true
    cancelPending = false
    statusMessage = ""
    transcript = ""
    stableTranscript = ""
    unstableTranscript = ""
    elapsedLabel = "00:00"
    waveformPhase = 0
    waveformAmplitude = 0
    pendingSend = false
    deliveredThisCapture = false
    deferredTranscript = nil
    deferredSessionId = ""
    correctionReview = nil
    voiceSettings = settings
    lastMessages = messages
    onRecordingStarted = onStart
    onFinishedTranscript = onFinish
    onCaptureCancelled = onCancel

    holdTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: Self.holdStartDelayNs)
      guard !Task.isCancelled else { return }
      await self?.startRecordingIfStillPending()
    }
  }

  private func startRecordingIfStillPending() async {
    guard isPending, !isRecording else { return }
    guard voiceSettings.speechRecognitionEnabled else {
      fail(lastMessages.speechDisabled)
      return
    }

    let granted = await speech.requestAuthorization(settings: voiceSettings)
    guard isPending, !isRecording else { return }
    guard granted else {
      fail(lastMessages.permissionDenied)
      return
    }

    do {
      speech.onVoiceCommand = { [weak self] command in
        Task { @MainActor in
          self?.handleVoiceCommand(command)
        }
      }
      try speech.start(settings: voiceSettings, source: "agent_input")
      isPending = false
      isRecording = true
      startedAt = Date()
      startTimer()
      onRecordingStarted?()
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    } catch {
      fail(error.localizedDescription.ifBlank(lastMessages.speechUnavailable))
    }
  }

  private func updateCancelState(translation: CGSize) {
    guard isRecording else { return }
    let nextCancel = translation.height <= -Self.cancelThreshold
    guard cancelPending != nextCancel else { return }
    cancelPending = nextCancel
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  private func finish(send: Bool, status: String) {
    pendingSend = send
    stopTimer()

    if let deferredTranscript {
      completeDeferred(send: send, transcript: deferredTranscript, status: status)
    } else if send {
      // Do not cancel SFSpeechRecognizer immediately on release. It often publishes
      // the final partial result just after the audio input is ended.
      speech.stopForHoldToTalk { [weak self] finalTranscript in
        guard let self else { return }
        let cleanTranscript = self.bestTranscript().ifBlank(finalTranscript)
        if !self.deliveredThisCapture {
          if !self.deliver(cleanTranscript) {
            if self.statusMessage != self.lastMessages.noSpeech {
              self.onCaptureCancelled?()
            }
            self.statusMessage = self.lastMessages.noSpeech
          }
        }
        self.resetIdle(keepStatus: true)
      }
    } else {
      speech.cancel()
      onCaptureCancelled?()
      if !status.isEmpty {
        statusMessage = status
      }
      resetIdle(keepStatus: true)
    }
  }

  private func completeDeferred(send: Bool, transcript: String, status: String) {
    if send {
      speech.stop()
      _ = deliver(transcript)
      if !deferredSessionId.isEmpty {
        _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: deferredSessionId))
      }
    } else {
      speech.cancel()
      onCaptureCancelled?()
      if !deferredSessionId.isEmpty {
        _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
          .cancelled(sessionId: deferredSessionId, reasonCode: "user_cancelled")
        )
      }
      statusMessage = status
    }
    resetIdle(keepStatus: true)
  }

  private func handleVoiceCommand(_ command: VoiceInteractionCommand) {
    switch command {
    case let .routeFinalTranscript(sessionId, transcript, idempotencyKey):
      let cleanText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanText.isEmpty, deliveredCommandKeys.insert(idempotencyKey).inserted else { return }
      self.transcript = cleanText
      stableTranscript = cleanText
      unstableTranscript = ""
      deferredSessionId = sessionId
      correctionReview = speech.correctionReview(sessionId: sessionId)
      if pendingSend {
        _ = deliver(cleanText)
        _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: sessionId))
      } else {
        deferredTranscript = cleanText
      }
    case let .cancelLegacyWork(sessionId, _, _):
      if pendingSend {
        if !deliveredThisCapture {
          onCaptureCancelled?()
        }
        statusMessage = lastMessages.noSpeech
      } else if !sessionId.isEmpty {
        _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(
          .cancelled(sessionId: sessionId, reasonCode: "user_cancelled")
        )
      }
    }
  }

  @discardableResult
  private func deliver(_ value: String) -> Bool {
    let cleanText = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let audioSnapshot = speech.completedPCMSnapshot
    let audioData = audioSnapshot.flatMap { snapshot in
      snapshot.samples.isEmpty ? nil : PcmWaveFileAdapter.waveData(snapshot: snapshot)
    }
    guard (!cleanText.isEmpty || audioData != nil), !deliveredThisCapture else { return false }
    deliveredThisCapture = true
    let sessionId = deferredSessionId.ifBlank(
      VoiceInteractionCoordinatorRegistry.coordinator.snapshot().sessionId
    )
    onFinishedTranscript?(SignalASIVoiceTranscriptSubmission(
      text: cleanText,
      correctionReview: correctionReview,
      sessionId: sessionId,
      audioData: audioData,
      audioDurationMillis: audioSnapshot?.durationMs ?? 0
    ))
    return true
  }

  private func bestTranscript() -> String {
    speech.transcript.ifBlank(transcript).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func fail(_ message: String) {
    holdTask?.cancel()
    holdTask = nil
    speech.onVoiceCommand = nil
    onCaptureCancelled?()
    statusMessage = message
    resetIdle(keepStatus: true)
  }

  private func resetIdle(keepStatus: Bool) {
    isPending = false
    isRecording = false
    cancelPending = false
    startedAt = nil
    pendingSend = false
    deliveredThisCapture = false
    deferredTranscript = nil
    deferredSessionId = ""
    correctionReview = nil
    onRecordingStarted = nil
    onFinishedTranscript = nil
    onCaptureCancelled = nil
    speech.onVoiceCommand = nil
    stopTimer()
    stableTranscript = ""
    unstableTranscript = ""
    waveformAmplitude = 0
    if !keepStatus {
      statusMessage = ""
    }
  }

  private func startTimer() {
    stopTimer()
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.tick()
      }
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    waveformPhase += 0.34
    let targetAmplitude = min(max(Double(speech.currentAudioLevel) * 8, 0), 1)
    waveformAmplitude += (targetAmplitude - waveformAmplitude) * 0.35
    let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
    elapsedLabel = Self.formatElapsed(elapsed)
    stableTranscript = speech.stableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    unstableTranscript = speech.unstableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    let currentTranscript = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    if !currentTranscript.isEmpty {
      transcript = currentTranscript
    }
    if elapsed >= Self.maximumDuration {
      finish(send: true, status: "")
    }
  }

  private static func formatElapsed(_ value: TimeInterval) -> String {
    let totalSeconds = max(0, Int(value))
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}
