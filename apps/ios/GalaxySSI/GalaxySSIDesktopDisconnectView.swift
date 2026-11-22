import SwiftUI

@MainActor
struct GalaxySSIDesktopDisconnectView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var coordinator: MessageCoordinator
  let link: ServerLink
  @State private var confirmation: ServerLink?
  @State private var failed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        failed = false; confirmation = link
      } label: {
        Label(t("title", "Disconnect Desktop, keep history"), systemImage: "xmark.circle")
          .foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
      }.frame(minHeight: 44).disabled(!link.paired || !MqttRouteProtocol.hex(link.desktopFingerprint, count: 64))
      if failed { Text(t("failed", "Could not disconnect. The Desktop identity may have changed.")).font(.caption).foregroundColor(.secondary) }
    }
    .alert(item: $confirmation) { captured in
      Alert(title: Text(t("title", "Disconnect Desktop, keep history")),
        message: Text(String(format: t("confirmation", "Disconnect %@?\n\nFingerprint: %@\n\nMessages stay in Archived Conversations. Other computers are not affected."),
          captured.desktopName, GalaxySSISecurityFormatter.fingerprint(captured.desktopFingerprint, unknown: ""))),
        primaryButton: .destructive(Text(t("action", "Disconnect"))) {
          failed = !coordinator.disconnectDesktopKeepingHistory(desktopId: captured.desktopId, fingerprint: captured.desktopFingerprint)
        }, secondaryButton: .cancel())
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.desktop_disconnect." + key, fallback: fallback, language: language)
  }
}
