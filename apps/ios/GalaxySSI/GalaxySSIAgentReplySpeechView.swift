import SwiftUI

private struct AgentReplyParagraphSpeechActionKey: EnvironmentKey {
  static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
  var agentReplyParagraphSpeechAction: ((String) -> Void)? {
    get { self[AgentReplyParagraphSpeechActionKey.self] }
    set { self[AgentReplyParagraphSpeechActionKey.self] = newValue }
  }
}

struct GalaxySSIAgentReplySpeechButton: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  var enabled: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(enabled ? .galaxySSIAccent : .galaxySSITextSecondary)
        .frame(width: 34, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(
        t(
          enabled
            ? "galaxyssi.agent.reply_speech.disable"
            : "galaxyssi.agent.reply_speech.enable",
          enabled ? "Stop reading reply" : "Read reply aloud"
        )
      )
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
