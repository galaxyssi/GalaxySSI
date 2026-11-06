import Combine
import UIKit

@MainActor
final class AgentCompletedReplyPlayback: ObservableObject {
  static let shared = AgentCompletedReplyPlayback()

  enum Phase { case idle, preparing, playing, paused }
  @Published private(set) var selection: AgentCompletedReplyPlaybackSelection?
  @Published private(set) var phase = Phase.idle
  @Published private(set) var lastErrorDescription = ""
  @Published private(set) var failedMessageID: UUID?

  private lazy var speech = VoiceProgressiveReplySpeechService()
  private var loadTask: Task<Void, Never>?
  private var sessionID = ""
  private let media = AppSpokenMediaSession.shared

  private init() {}

  func footerUpdates(messageId: UUID) -> AnyPublisher<AgentReplySpeechFooterState, Never> {
    Publishers.CombineLatest3($selection, $failedMessageID, $lastErrorDescription)
      .map { selection, failed, error in
        let selected = selection?.messageID == messageId
        return AgentReplySpeechFooterState(active: selected || failed == messageId, playing: selected,
          error: failed == messageId ? error : "")
      }
      .removeDuplicates()
      .eraseToAnyPublisher()
  }

  func play(
    _ selection: AgentCompletedReplyPlaybackSelection,
    database: GalaxySSIChatHistoryDatabase,
    settings: VoiceSettings,
    languagePolicy: LanguagePolicySettings,
    isAllowed: @escaping () -> Bool
  ) {
    stop()
    lastErrorDescription = ""
    failedMessageID = nil
    guard settings.textToSpeechEnabled, isAllowed(), UIApplication.shared.applicationState == .active else { return }
    media.reserve(self, controls: .init(
      title: GalaxySSILocalization.string("galaxyssi.agent.reply_speech.now_playing", fallback: "Agent reply"),
      resume: { [weak self] in self?.resume() },
      pause: { [weak self] in self?.pause() },
      stop: { [weak self] in self?.stop() },
      relinquish: { [weak self] in self?.stop() }
    ))
    let id = UUID().uuidString
    sessionID = id
    self.selection = selection
    phase = .preparing
    loadTask = Task { [weak self] in
      let text = await Task.detached(priority: .userInitiated) {
        selection.resolve(database.message(id: selection.messageID))
      }.value
      guard let self, !Task.isCancelled, self.sessionID == id else { return }
      self.loadTask = nil
      guard isAllowed(), UIApplication.shared.applicationState == .active else { self.stop(); return }
      guard let text else { self.fail(); return }
      self.start(text: text, sessionID: id, settings: settings, languagePolicy: languagePolicy)
    }
  }

  func stop() {
    guard !sessionID.isEmpty || media.owns(self) || loadTask != nil else { return }
    loadTask?.cancel()
    loadTask = nil
    sessionID = ""
    _ = speech.stop()
    phase = .idle
    selection = nil
    media.release(self)
  }

  private func start(text: String, sessionID: String, settings: VoiceSettings, languagePolicy: LanguagePolicySettings) {
    guard media.activate(self) else {
      fail()
      return
    }
    let language = LanguagePolicySettings.resolve(languagePolicy.ttsLanguage)
    let request = VoiceReplyPlaybackRequest(
      sessionId: sessionID, utteranceId: "completed-agent-reply:\(sessionID)", text: "",
      language: language, providerId: settings.ttsProvider.rawValue, runtimeChannel: settings.ttsProvider.runtimeChannel,
      voiceName: settings.ttsProvider == .microsoftEdge
        ? LanguagePolicySettings.microsoftVoice(languageTag: language, configuredVoice: settings.microsoftVoice)
        : ""
    )
    speech.beginProgressive(request, onPlaybackStarted: { [weak self] request in
      guard let self, self.sessionID == request.sessionId else { return }
      self.phase = .playing
      self.media.setPlaying(true, owner: self)
    }, onDone: { [weak self] request, success, _ in
      guard let self, self.sessionID == request.sessionId else { return }
      if success { self.stop() }
      else { self.fail() }
    })
    speech.appendProgressive(text, isFinal: true)
  }

  private func pause() {
    guard phase == .playing, speech.pauseProgressive() else { return }
    phase = .paused
    media.suspend(self)
  }

  private func resume() {
    guard phase == .paused else { return }
    guard media.activate(self) else { fail(); return }
    phase = .playing
    if speech.resumeProgressive(), phase == .playing { media.setPlaying(true, owner: self) }
  }

  private func fail() {
    failedMessageID = selection?.messageID
    stop()
    lastErrorDescription = GalaxySSILocalization.string("galaxyssi.agent.reply_speech.failed", fallback: "Reply speech failed.")
  }

}
