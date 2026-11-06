import SwiftUI

struct GalaxySSIPublicNewsSpeechControls: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var store: GalaxySSIStore
  @ObservedObject var playback: PublicNewsSpeechPlayback
  var showTitle = false

  var body: some View {
    HStack(spacing: 2) {
      if showTitle {
        Text(t("public_news_speech_title", "News reading"))
          .font(.subheadline)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 8)
      }
      if playback.queue.isActive {
        control("pause.fill", t("public_news_speech_pause", "Pause")) { playback.pause() }
      } else {
        control("play.fill", t("public_news_speech_resume", "Resume")) {
          playback.resume(settings: store.voiceSettings, languagePolicy: store.languagePolicy)
        }
        .disabled(!store.voiceSettings.textToSpeechEnabled)
      }
      control("forward.end.fill", t("public_news_speech_next", "Next article")) { playback.next() }
        .disabled(!store.voiceSettings.textToSpeechEnabled ||
          playback.queue.bookmark.index + 1 >= playback.queue.bookmark.items.count)
      control("stop.fill", t("public_news_speech_stop", "Stop reading")) { playback.stop() }
    }
    .buttonStyle(.plain)
  }

  private func control(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon).frame(width: 44, height: 44)
    }
    .accessibilityLabel(Text(label))
    .help(label)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
