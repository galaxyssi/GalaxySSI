import Combine
import Foundation

@MainActor
final class AgentReplySpeechRuntime: ObservableObject {
  @Published private(set) var revision = 0
  @Published private(set) var lastErrorDescription = ""

  private let controller: AgentReplySpeechController
  private let speech: VoiceProgressiveReplySpeechService
  private var commitTask: Task<Void, Never>?
  private var activePlaybackSessionId = ""
  private var cancelledSessionIds: Set<String> = []
  private var activeTarget: AgentReplySpeechTarget?
  private var activeSettings = VoiceSettings.default
  private var activeLanguagePolicy = LanguagePolicySettings.default

  init(
    controller: AgentReplySpeechController = AgentReplySpeechController(),
    speech: VoiceProgressiveReplySpeechService = VoiceProgressiveReplySpeechService()
  ) {
    self.controller = controller
    self.speech = speech
  }

  func observe(
    _ target: AgentReplySpeechTarget?,
    settings: VoiceSettings,
    languagePolicy: LanguagePolicySettings
  ) {
    activeTarget = target
    activeSettings = settings.normalized
    activeLanguagePolicy = languagePolicy
    execute(controller.observe(target), target: target)
  }

  func toggle(
    _ target: AgentReplySpeechTarget,
    settings: VoiceSettings,
    languagePolicy: LanguagePolicySettings
  ) {
    activeTarget = target
    activeSettings = settings.normalized
    activeLanguagePolicy = languagePolicy
    execute(controller.toggle(target), target: target)
  }

  func readFromParagraph(
    _ selection: AgentReplyParagraphSpeechSelection,
    target: AgentReplySpeechTarget,
    settings: VoiceSettings,
    languagePolicy: LanguagePolicySettings
  ) {
    activeTarget = target
    activeSettings = settings.normalized
    activeLanguagePolicy = languagePolicy
    execute(
      controller.readFromParagraph(
        target,
        paragraph: selection.paragraph,
        sourceText: selection.sourceText,
        startOffset: selection.startOffset
      ),
      target: target
    )
  }

  func isEnabled(_ target: AgentReplySpeechTarget) -> Bool {
    _ = revision
    return controller.isEnabled(target)
  }

  func isActive(_ target: AgentReplySpeechTarget) -> Bool {
    controller.isActive(target)
  }

  func stop() {
    commitTask?.cancel()
    commitTask = nil
    execute(controller.observe(nil), target: nil)
  }

  @discardableResult
  func stopPlaybackIfActive() -> Bool {
    guard controller.isPlaying else { return false }
    commitTask?.cancel()
    commitTask = nil
    execute(controller.stop(), target: activeTarget)
    return true
  }

  private func execute(_ command: AgentReplySpeechCommand, target: AgentReplySpeechTarget?) {
    guard command != AgentReplySpeechCommand() else { return }
    if !command.cancelSessionId.isEmpty {
      commitTask?.cancel()
      commitTask = nil
      cancelledSessionIds.insert(command.cancelSessionId)
      _ = speech.stop()
      if activePlaybackSessionId == command.cancelSessionId {
        activePlaybackSessionId = ""
      }
    }
    if !command.beginSessionId.isEmpty, let target {
      guard activeSettings.textToSpeechEnabled else {
        lastErrorDescription = GalaxySSILocalization.string(
          "galaxyssi.agent.reply_speech.tts_disabled",
          fallback: "Enable text-to-speech in Voice settings to read replies."
        )
        _ = controller.disable(sessionId: command.beginSessionId)
        revision &+= 1
        return
      }
      lastErrorDescription = ""
      let request = playbackRequest(
        sessionId: command.beginSessionId,
        target: target,
        text: ""
      )
      if !activePlaybackSessionId.isEmpty {
        cancelledSessionIds.insert(activePlaybackSessionId)
      }
      speech.beginProgressive(
        request,
        onPlaybackStarted: { _ in },
        onDone: { [weak self] request, success, error in
          guard let self else { return }
          if self.cancelledSessionIds.remove(request.sessionId) != nil { return }
          if self.activePlaybackSessionId == request.sessionId {
            self.activePlaybackSessionId = ""
          }
          _ = self.controller.disable(sessionId: request.sessionId)
          if !success {
            self.lastErrorDescription = error ?? GalaxySSILocalization.string(
              "galaxyssi.agent.reply_speech.failed",
              fallback: "Reply speech failed."
            )
          }
          self.revision &+= 1
        }
      )
      activePlaybackSessionId = command.beginSessionId
    }
    if !command.appendedText.isEmpty {
      speech.appendProgressive(command.appendedText, isFinal: false)
    }
    if !command.finishSessionId.isEmpty {
      commitTask?.cancel()
      commitTask = nil
      speech.finishProgressive()
    } else if !command.scheduleCommitSessionId.isEmpty {
      scheduleCommit(sessionId: command.scheduleCommitSessionId)
    }
    if !command.changedEntryIds.isEmpty {
      revision &+= 1
    }
  }

  private func scheduleCommit(sessionId: String) {
    commitTask?.cancel()
    commitTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 525_000_000)
      guard !Task.isCancelled, let self else { return }
      guard self.activeTarget.map(self.controller.isEnabled) == true else { return }
      self.speech.commitProgressive()
    }
  }

  private func playbackRequest(
    sessionId: String,
    target: AgentReplySpeechTarget,
    text: String
  ) -> VoiceReplyPlaybackRequest {
    let language = LanguagePolicySettings.resolve(activeLanguagePolicy.ttsLanguage)
    let voiceName = activeSettings.ttsProvider == .microsoftEdge
      ? LanguagePolicySettings.microsoftVoice(
        languageTag: language,
        configuredVoice: activeSettings.microsoftVoice
      )
      : ""
    return VoiceReplyPlaybackRequest(
      sessionId: sessionId,
      utteranceId: "galaxyssi_agent_reply_\(target.entryId)",
      text: text,
      language: language,
      providerId: activeSettings.ttsProvider.rawValue,
      runtimeChannel: activeSettings.ttsProvider.runtimeChannel,
      voiceName: voiceName
    )
  }
}
