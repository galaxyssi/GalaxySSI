import Combine
import SwiftUI

struct AgentReplyParagraphSpeechSelection: Equatable {
  var paragraph: String
  var sourceText: String
  var startOffset: Int
}

private struct AgentReplyParagraphSpeechActionKey: EnvironmentKey {
  static let defaultValue: ((AgentReplyParagraphSpeechSelection) -> Void)? = nil
}

private struct AgentReplySpeechProseKey: EnvironmentKey {
  static let defaultValue: AgentReplySpeechPresentationPolicy.Prose? = nil
}

private struct AgentReplySpeechBlankTapKey: EnvironmentKey {
  static let defaultValue: (() -> Void)? = nil
}

private struct AgentReplyNativeParagraphsKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var agentReplyParagraphSpeechAction: ((AgentReplyParagraphSpeechSelection) -> Void)? {
    get { self[AgentReplyParagraphSpeechActionKey.self] }
    set { self[AgentReplyParagraphSpeechActionKey.self] = newValue }
  }

  var agentReplySpeechProse: AgentReplySpeechPresentationPolicy.Prose? {
    get { self[AgentReplySpeechProseKey.self] }
    set { self[AgentReplySpeechProseKey.self] = newValue }
  }

  var agentReplySpeechBlankTap: (() -> Void)? {
    get { self[AgentReplySpeechBlankTapKey.self] }
    set { self[AgentReplySpeechBlankTapKey.self] = newValue }
  }

  var agentReplyNativeParagraphs: Bool {
    get { self[AgentReplyNativeParagraphsKey.self] }
    set { self[AgentReplyNativeParagraphsKey.self] = newValue }
  }
}

struct GalaxySSIAgentReplySpeechButton: View {
  static let height: CGFloat = 32
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
      .frame(height: Self.height)
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

@MainActor
struct GalaxySSIAgentReplySpeechFooter: View {
  let runtime: AgentReplySpeechRuntime
  let entryId: String
  let isLatest: Bool
  var additionalUpdates: AnyPublisher<AgentReplySpeechFooterState, Never>? = nil
  let action: () -> Void
  @State private var state = AgentReplySpeechFooterState()

  var body: some View {
    ZStack(alignment: .trailing) {
      Color.clear.allowsHitTesting(false).accessibilityHidden(true)
      if isLatest || state.active {
        HStack(spacing: 8) {
          Spacer(minLength: 0)
          if !state.error.isEmpty {
            Text(state.error)
              .font(.caption2)
              .foregroundColor(.red)
              .lineLimit(1)
              .accessibilityLabel(Text(state.error))
          }
          GalaxySSIAgentReplySpeechButton(enabled: state.playing, action: action)
        }
      }
    }
    .frame(height: GalaxySSIAgentReplySpeechButton.height)
    .onReceive(updates) { state = $0 }
  }

  private var updates: AnyPublisher<AgentReplySpeechFooterState, Never> {
    let foreground = runtime.footerUpdates(entryId: entryId)
    guard let additionalUpdates else { return foreground }
    return foreground.combineLatest(additionalUpdates) { foreground, background in
      AgentReplySpeechFooterState(active: foreground.active || background.active,
        playing: foreground.playing || background.playing, error: background.error.ifBlank(foreground.error))
    }.removeDuplicates().eraseToAnyPublisher()
  }
}
