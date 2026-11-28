import SwiftUI

@MainActor
struct GalaxySSIDesktopHistoryDeletionView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @EnvironmentObject private var store: GalaxySSIStore
  let link: ServerLink
  @State private var confirmation: ServerLink?
  @State private var owner = ""
  @State private var result: Bool?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        owner = store.profile.identityFingerprint; confirmation = link; result = nil
      } label: {
        Label(t("delete", "Delete local chat history"), systemImage: "trash")
          .foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
      }.frame(minHeight: 44).disabled(!link.paired)
      if let result {
        Text(result ? t("deleted", "Local chat history deleted") : t("failed", "History was not deleted. The identity, route or local storage may have changed."))
          .font(.caption).foregroundColor(.secondary)
      }
    }
    .alert(item: $confirmation) { captured in
      Alert(title: Text(t("delete", "Delete local chat history")),
        message: Text(String(format: t("confirmation", "Permanently delete chats with %@ and its Agents from this phone? Pairing and the computer's copy are not affected."), captured.desktopName)),
        primaryButton: .destructive(Text(t("delete", "Delete local chat history"))) {
          result = store.clearPairedDesktopLocalHistory(captured, owner: owner)
        }, secondaryButton: .cancel())
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.desktop_history." + key, fallback: fallback, language: language)
  }
}
