import AVFoundation
import Combine
import Foundation

final class VoiceReplySpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
  @Published private(set) var isSpeaking = false
  @Published private(set) var lastErrorDescription = ""

  private let synthesizer: AVSpeechSynthesizer
  private var activeRequest: VoiceReplyPlaybackRequest?
  private var onPlaybackStarted: ((VoiceReplyPlaybackRequest) -> Void)?
  private var onDone: ((VoiceReplyPlaybackRequest, Bool, String?) -> Void)?

  init(synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()) {
    self.synthesizer = synthesizer
    super.init()
    self.synthesizer.delegate = self
  }

  @MainActor
  func speak(
    _ request: VoiceReplyPlaybackRequest,
    onPlaybackStarted: @escaping (VoiceReplyPlaybackRequest) -> Void,
    onDone: @escaping (VoiceReplyPlaybackRequest, Bool, String?) -> Void
  ) {
    stop()
    let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      onDone(request, true, nil)
      return
    }
    activeRequest = request
    self.onPlaybackStarted = onPlaybackStarted
    self.onDone = onDone
    lastErrorDescription = ""
    VoiceRuntimeHealthRegistry.begin(request.runtimeChannel)

    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: request.language)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    synthesizer.speak(utterance)
  }

  @MainActor
  func stop() {
    guard synthesizer.isSpeaking else { return }
    synthesizer.stopSpeaking(at: .immediate)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    DispatchQueue.main.async {
      guard let request = self.activeRequest else { return }
      self.isSpeaking = true
      self.onPlaybackStarted?(request)
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    DispatchQueue.main.async {
      guard let request = self.activeRequest else { return }
      self.isSpeaking = false
      self.activeRequest = nil
      VoiceRuntimeHealthRegistry.success(request.runtimeChannel)
      self.onDone?(request, true, nil)
      self.onPlaybackStarted = nil
      self.onDone = nil
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    DispatchQueue.main.async {
      guard let request = self.activeRequest else { return }
      self.isSpeaking = false
      self.activeRequest = nil
      self.lastErrorDescription = "Speech playback was cancelled"
      VoiceRuntimeHealthRegistry.failure(request.runtimeChannel, reason: self.lastErrorDescription)
      self.onDone?(request, false, self.lastErrorDescription)
      self.onPlaybackStarted = nil
      self.onDone = nil
    }
  }
}
