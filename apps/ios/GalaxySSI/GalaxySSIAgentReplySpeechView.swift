import SwiftUI

struct AgentReplyParagraphSpeechSelection: Equatable {
  var paragraph: String
  var sourceText: String
  var startOffset: Int
}

private struct AgentReplyParagraphSpeechActionKey: EnvironmentKey {
  static let defaultValue: ((AgentReplyParagraphSpeechSelection) -> Void)? = nil
}

extension EnvironmentValues {
  var agentReplyParagraphSpeechAction: ((AgentReplyParagraphSpeechSelection) -> Void)? {
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
      HStack(spacing: 6) {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !enabled)) { context in
          let wave = (sin(context.date.timeIntervalSinceReferenceDate * 5.2) + 1) / 2
          Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 14, weight: .semibold))
            .opacity(enabled ? 0.55 + (wave * 0.45) : 1)
        }
        .frame(width: 18, height: 18)
        Text(
          t(
            enabled
              ? "galaxyssi.agent.reply_speech.playing_label"
              : "galaxyssi.agent.reply_speech.idle_label",
            enabled ? "Reading" : "Read"
          )
        )
        .font(.system(size: 12))
      }
      .foregroundColor(enabled ? .galaxySSIAccent : .galaxySSITextSecondary)
      .padding(.leading, 9)
      .padding(.trailing, 11)
      .frame(height: 32)
      .background(Color(.systemBackground))
      .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
