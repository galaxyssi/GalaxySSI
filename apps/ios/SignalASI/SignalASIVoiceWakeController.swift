import Foundation
import SwiftUI

/// Foreground-only wake listening for the Voice tab. iOS cannot keep a general
/// microphone listener alive after the app leaves the foreground, so the owner
/// explicitly starts and stops this controller with the selected root tab.
@MainActor
final class SignalASIVoiceWakeController: ObservableObject {
  @Published private(set) var isListening = false
  @Published private(set) var isPreparing = false
  @Published private(set) var failureDescription = ""

  private let speech = SpeechCaptureService()
  private var settings = VoiceSettings.default
  private var wantsListening = false
  private var manualCaptureActive = false
  private var configurationGeneration = 0
  private var restartTask: Task<Void, Never>?
  private var onWakeCommand: ((String) -> Void)?

  deinit {
    restartTask?.cancel()
  }

  func activate(settings: VoiceSettings, onWakeCommand: @escaping (String) -> Void) {
    self.settings = settings.normalized
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
      let granted = await speech.requestAuthorization(
        localeIdentifier: captureSettings.preferredLocaleIdentifier
      )
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
            self?.handleVoiceCommand(command, settings: captureSettings)
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

  private func handleVoiceCommand(_ command: VoiceInteractionCommand, settings: VoiceSettings) {
    guard case let .routeFinalTranscript(sessionId, transcript, _) = command else { return }
    _ = VoiceInteractionCoordinatorRegistry.coordinator.dispatch(.completed(sessionId: sessionId))
    guard let commandText = WakeWordPolicy.commandText(
      from: transcript.text,
      removing: settings.wakeWords
    ), !commandText.isEmpty else {
      return
    }
    VoiceRuntimeHealthRegistry.success(.androidWakeASR)
    onWakeCommand?(commandText)
  }

  private func stopCapture() {
    speech.onVoiceCommand = nil
    if speech.isRecording {
      speech.stop()
    }
    isPreparing = false
    isListening = false
    VoiceRuntimeHealthRegistry.idle(.androidWakeASR)
  }
}
