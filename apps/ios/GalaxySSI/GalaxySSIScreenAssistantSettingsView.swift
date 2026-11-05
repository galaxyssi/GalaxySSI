import SwiftUI

struct GalaxySSIScreenAssistantSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var capture = GalaxySSIScreenAssistantCapture.noWindow

  private var availability: GalaxySSIScreenAssistantAvailability {
    .resolve(enabled: store.displaySettings.screenAssistantEnabled, foreground: scenePhase == .active, capture: capture)
  }

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
                  ? t("galaxyssi.screen_assistant.preference_enabled", "On")
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

          VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
              Text(t("galaxyssi.screen_assistant.status", "Availability"))
              Spacer(minLength: 8)
              Text(availabilityTitle)
                .foregroundColor(.galaxySSITextSecondary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("ios.screen-assistant.availability")
            }
            if availability == .screenCaptured {
              Text(t("galaxyssi.screen_assistant.capture_recovery",
                "Stop recording or mirroring in Control Center to restore the launcher."))
                .font(.footnote)
                .foregroundColor(.galaxySSITextSecondary)
            }
            Divider()
            NavigationLink(destination: OnDeviceAgentPermissionsView()) {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(t("galaxyssi.screen_assistant.observation", "Automatic screen context"))
                Spacer(minLength: 0)
                Text(store.agentSafetySettings.screenObservationAllowed
                  ? t("galaxyssi.screen_assistant.observation_allowed", "Allowed")
                  : t("galaxyssi.screen_assistant.observation_blocked", "Not allowed"))
                  .foregroundColor(.galaxySSITextSecondary)
                Image(systemName: "chevron.right").font(.caption)
                  .foregroundColor(.galaxySSITextSecondary)
              }
              .foregroundColor(.galaxySSITextPrimary)
            }
          }
          .padding(16)
          .background(Color.galaxySSISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8))

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
    .background(GalaxySSIScreenCaptureProbe(capture: $capture))
    .navigationBarHidden(true)
    .accessibilityIdentifier("ios.screen-assistant.settings")
  }

  private var availabilityTitle: String {
    switch availability {
    case .disabled: return t("galaxyssi.screen_assistant.disabled", "Off")
    case .inactive: return t("galaxyssi.screen_assistant.inactive", "App inactive")
    case .waitingForWindow: return t("galaxyssi.screen_assistant.waiting_window", "Waiting for an active window")
    case .screenCaptured: return t("galaxyssi.screen_assistant.capture_paused", "Paused during recording or mirroring")
    case .available: return t("galaxyssi.screen_assistant.available_in_app", "Available on the Agent page")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
