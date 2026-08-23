import Foundation
import SwiftUI

/// Foreground-only wake listening for the Voice tab. iOS cannot keep a general
/// microphone listener alive after the app leaves the foreground, so the owner
/// explicitly starts and stops this controller with the selected root tab.
@MainActor
final class SignalASIVoiceWakeController: ObservableObject {
  @Published private(set) var isListening = false
  @Published private(set) var isPreparing = false
  @Published private(set) var isCommandCapturing = false
  @Published private(set) var failureDescription = ""

  private let speech = SpeechCaptureService()
  private var settings = VoiceSettings.default
  private var wantsListening = false
  private var manualCaptureActive = false
  private var configurationGeneration = 0
  private var restartTask: Task<Void, Never>?
  private var onWakeDetected: (() -> Void)?
  private var onWakeCommand: ((String) -> Void)?

  deinit {
    restartTask?.cancel()
  }

  func activate(
    settings: VoiceSettings,
    onWakeDetected: @escaping () -> Void,
    onWakeCommand: @escaping (String) -> Void
  ) {
    self.settings = settings.normalized
    self.onWakeDetected = onWakeDetected
    self.onWakeCommand = onWakeCommand
    wantsListening = true
    manualCaptureActive = false
    refreshCapture()
  }

  func update(settings: VoiceSettings) {
    self.settings = settings.normalized
    refreshCapture()
  }

  func deactivate() {
    wantsListening = false
    manualCaptureActive = false
    configurationGeneration += 1
    restartTask?.cancel()
    restartTask = nil
    stopCapture()
    onWakeDetected = nil
    onWakeCommand = nil
  }

  func pauseForManualCapture() {
    guard wantsListening else { return }
    manualCaptureActive = true
    configurationGeneration += 1
    restartTask?.cancel()
    restartTask = nil
    stopCapture()
  }

  func resumeAfterManualCapture() {
    guard wantsListening else { return }
    manualCaptureActive = false
    refreshCapture(after: 500_000_000)
  }

  /// Starts an endpoint-detected foreground command after the user interrupts
  /// a spoken reply from the Voice home surface.
  @discardableResult
  func beginTapToSpeak() -> Bool {
    guard wantsListening,
          settings.speechRecognitionEnabled,
          !isPreparing,
          !isCommandCapturing else {
      return false
    }
    manualCaptureActive = true
    configurationGeneration += 1
    restartTask?.cancel()
    restartTask = nil
    stopCapture()
    startTapToSpeakCapture(generation: configurationGeneration)
    return true
  }

  private var shouldListen: Bool {
    wantsListening && !manualCaptureActive && settings.wakeListeningEnabled &&
      settings.speechRecognitionEnabled
  }

  private func refreshCapture(after delayNanoseconds: UInt64 = 0) {
    configurationGeneration += 1
    guard shouldListen else {
      restartTask?.cancel()
      restartTask = nil
      stopCapture()
      return
    }
    guard !speech.isRecording && !isPreparing else { return }
    scheduleCaptureStart(after: delayNanoseconds, generation: configurationGeneration)
  }

  private func scheduleCaptureStart(after delayNanoseconds: UInt64, generation: Int) {
    restartTask?.cancel()
    restartTask = Task { @MainActor [weak self] in
      if delayNanoseconds > 0 {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
      }
      guard !Task.isCancelled else { return }
      self?.startCaptureIfNeeded(generation: generation)
    }
  }

  private func startCaptureIfNeeded(generation: Int) {
    guard generation == configurationGeneration, shouldListen, !speech.isRecording, !isPreparing else {
      return
    }
    isPreparing = true
    failureDescription = ""
    let captureSettings = settings
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      let granted = await speech.requestAuthorization(settings: captureSettings)
      guard generation == configurationGeneration, shouldListen else {
        isPreparing = false
        return
      }
      guard granted else {
        isPreparing = false
        failureDescription = "Microphone or speech permission is missing."
        VoiceRuntimeHealthRegistry.failure(.androidWakeASR, reason: failureDescription)
        return
      }
      do {
        speech.onVoiceCommand = { [weak self] command in
          Task { @MainActor in
            self?.handleVoiceCommand(command)
          }
        }
        try speech.start(settings: captureSettings, source: "ios_voice_wake")
        isPreparing = false
        isListening = true
        VoiceRuntimeHealthRegistry.begin(.androidWakeASR)
        observeCaptureEnd(generation: generation)
      } catch {
        isPreparing = false
        failureDescription = error.localizedDescription
        VoiceRuntimeHealthRegistry.failure(.androidWakeASR, reason: failureDescription)
      }
    }
  }

  private func startTapToSpeakCapture(generation: Int) {
    guard generation == configurationGeneration,
          wantsListening,
          manualCaptureActive,
          !speech.isRecording,
          !isPreparing else {
      return
    }
    isPreparing = true
    failureDescription = ""
    let captureSettings = settings
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      let granted = await speech.requestAuthorization(settings: captureSettings)
      guard generation == configurationGeneration,
            wantsListening,
            manualCaptureActive else {
        isPreparing = false
        return
      }
      guard granted else {
        isPreparing = false
        failureDescription = "Microphone or speech permission is missing."
        VoiceRuntimeHealthRegistry.failure(.androidWakeASR, reason: failureDescription)
        completeTapToSpeakCapture(after: 0)
        return
      }
      do {
        speech.onVoiceCommand = { [weak self] command in
          Task { @MainActor in
            self?.handleTapToSpeakCommand(command)
          }
        }
        try speech.start(settings: captureSettings, source: "ios_voice_wake_tap")
        isPreparing = false
        isListening = false
        isCommandCapturing = true
        VoiceRuntimeHealthRegistry.begin(.androidWakeASR)
        observeTapToSpeakCaptureEnd(generation: generation)
      } catch {
        isPreparing = false
        failureDescription = error.localizedDescription
        VoiceRuntimeHealthRegistry.failure(.androidWakeASR, reason: failureDescription)
        completeTapToSpeakCapture(after: 500_000_000)
      }
    }
  }

  private func observeCaptureEnd(generation: Int) {
    restartTask?.cancel()
    restartTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard let self = self, generation == configurationGeneration else { return }
        guard shouldListen else { return }
        if !speech.isRecording && !isPreparing {
          isListening = false
          scheduleCaptureStart(after: 250_000_000, generation: generation)
          return
        }
      }
    }
  }

  private func observeTapToSpeakCaptureEnd(generation: Int) {
    restartTask?.cancel()
    restartTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard let self = self, generation == configurationGeneration else { return }
        guard self.manualCaptureActive else { return }
        if !self.speech.isRecording && !self.isPreparing {
          self.completeTapToSpeakCapture(after: 500_000_000)
          return
        }
      }
    }
  }

  private func handleVoiceCommand(_ command: VoiceInteractionCommand) {
    guard case let .routeFinalTranscript(sessionId, transcript, _) = command else { return }
    _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: sessionId))
    guard WakeWordPolicy.commandText(from: transcript.text) != nil else {
      return
    }
    VoiceRuntimeHealthRegistry.success(.androidWakeASR)
    pauseForManualCapture()
    if let onWakeDetected {
      onWakeDetected()
    } else {
      _ = beginTapToSpeak()
    }
  }

  private func handleTapToSpeakCommand(_ command: VoiceInteractionCommand) {
    guard case let .routeFinalTranscript(_, transcript, _) = command else { return }
    let commandText = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !commandText.isEmpty else { return }
    VoiceRuntimeHealthRegistry.success(.androidWakeASR)
    onWakeCommand?(commandText)
  }

  private func completeTapToSpeakCapture(after delayNanoseconds: UInt64) {
    guard wantsListening else { return }
    isCommandCapturing = false
    manualCaptureActive = false
    refreshCapture(after: delayNanoseconds)
  }

  private func stopCapture() {
    speech.onVoiceCommand = nil
    if speech.isRecording {
      speech.stop()
    }
    isPreparing = false
    isCommandCapturing = false
    isListening = false
    VoiceRuntimeHealthRegistry.idle(.androidWakeASR)
  }
}
