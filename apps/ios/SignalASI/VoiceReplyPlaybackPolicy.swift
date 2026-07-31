import Foundation

struct VoiceReplyPlaybackRequest: Equatable {
  var sessionId: String
  var utteranceId: String
  var text: String
  var language: String
  var providerId: String
  var runtimeChannel: VoiceRuntimeChannel
  var voiceName: String
}

enum VoiceReplyPlaybackPolicy {
  static let maximumSpokenCharacters = 600

  static func request(
    message: ChatMessage,
    settings: VoiceSettings,
    languagePolicy: LanguagePolicySettings,
    activeSessionId: String,
    activeTargetContactId: String
  ) -> VoiceReplyPlaybackRequest? {
    let sessionId = activeSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetContactId = activeTargetContactId.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = String(
      message.content
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(maximumSpokenCharacters)
    )
    guard settings.speakReplies,
          settings.textToSpeechEnabled,
          !sessionId.isEmpty,
          !targetContactId.isEmpty,
          message.contactId == targetContactId,
          !message.isMine,
          !message.isSystem,
          !text.isEmpty else {
      return nil
    }
    return VoiceReplyPlaybackRequest(
      sessionId: sessionId,
      utteranceId: "signalasi_voice_\(message.id.uuidString)",
      text: text,
      language: LanguagePolicySettings.resolve(languagePolicy.ttsLanguage),
      providerId: settings.ttsProvider.rawValue,
      runtimeChannel: settings.ttsProvider.runtimeChannel,
      voiceName: voiceName(settings: settings, languagePolicy: languagePolicy)
    )
  }

  private static func voiceName(settings: VoiceSettings, languagePolicy: LanguagePolicySettings) -> String {
    guard settings.ttsProvider == .microsoftEdge else { return "" }
    return LanguagePolicySettings.microsoftVoice(
      languageTag: languagePolicy.ttsLanguage,
      configuredVoice: settings.microsoftVoice
    )
  }
}
