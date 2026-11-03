import SwiftUI

struct GalaxySSIScreenAssistantSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.screen_assistant.title", "Screen assistant"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Toggle(isOn: Binding(
            get: { store.displaySettings.screenAssistantEnabled },
            set: { enabled in store.updateDisplaySettings { $0.screenAssistantEnabled = enabled } }
          )) {
            HStack(spacing: 12) {
              Image(systemName: "viewfinder")
                .font(.system(size: 21))
                .foregroundColor(.galaxySSIAccent)
                .frame(width: 44, height: 44)
                .background(Color.galaxySSIAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
              VStack(alignment: .leading, spacing: 5) {
                Text(t("galaxyssi.screen_assistant.enable", "Floating screen assistant"))
                  .font(.system(size: 16))
                  .foregroundColor(.galaxySSITextPrimary)
                Text(store.displaySettings.screenAssistantEnabled
                  ? t("galaxyssi.screen_assistant.enabled_ios", "On. The floating button is available inside GalaxySSI.")
                  : t("galaxyssi.screen_assistant.disabled", "Off"))
                  .font(.system(size: 13))
                  .foregroundColor(.galaxySSITextSecondary)
              }
              .fixedSize(horizontal: false, vertical: true)
            }
          }
          .toggleStyle(SwitchToggleStyle(tint: .galaxySSIAccent))
          .padding(16)
          .background(Color.galaxySSISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .accessibilityIdentifier("ios.screen-assistant.enabled")

          Text(t("galaxyssi.screen_assistant.privacy_ios",
            "Only content you select and send is shared with the selected Agent. Enabling this switch does not capture the screen or start a task. iOS does not allow this button above other apps."))
            .font(.system(size: 13))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        }
        .padding(12)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .accessibilityIdentifier("ios.screen-assistant.settings")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
