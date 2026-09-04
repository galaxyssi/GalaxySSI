import SwiftUI

struct GalaxySSIResetDataView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.presentationMode) private var presentationMode
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var showingConfirmation = false
  @State private var confirmationPhrase = ""
  @State private var confirmationError = ""
  @State private var statusMessage = ""

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("destroy_data_title", "Reset Data"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("destroy_data_hero_title", "Dangerous Operation"),
            subtitle: t(
              "destroy_data_hero_subtitle",
              "This deletes identity, contacts, chat history, keys, cache, and backup data."
            ),
            systemImage: "trash",
            tint: .red,
            badge: t("destroy_data_badge", "Irreversible")
          )
          scopeSection
          confirmationSection
          footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .alert(t("cc_reset_dialog_title", "Reset GalaxySSI?"), isPresented: $showingConfirmation) {
      TextField(t("cc_reset_input_hint", "Type RESET"), text: $confirmationPhrase)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled(true)
      Button(t("common_cancel", "Cancel"), role: .cancel) {
        confirmationPhrase = ""
        confirmationError = ""
      }
      Button(t("destroy_data_title", "Reset Data"), role: .destructive) {
        confirmReset()
      }
    } message: {
      Text(t(
        "cc_reset_dialog_message",
        "This permanently removes local identity, keys, contacts, conversations, Agent data, knowledge, settings, cache, and exported backups stored by GalaxySSI. Type RESET to continue."
      ))
    }
  }

  private var scopeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("destroy_data_scope", "Clear Scope"))
      GalaxySSISecurityStatusRow(
        title: t("destroy_data_regenerate_identity", "Regenerate Identity"),
        subtitle: t("destroy_data_regenerate_identity_subtitle", "Create a new GalaxySSI ID and identity fingerprint"),
        systemImage: "checkmark.shield",
        tint: .red,
        badge: removedLabel
      )
      GalaxySSISecurityStatusRow(
        title: t("destroy_data_contacts", "Contacts"),
        subtitle: t("destroy_data_contacts_subtitle", "Deleted contacts must be added again before communication"),
        systemImage: "person.2",
        tint: .red,
        badge: removedLabel
      )
      GalaxySSISecurityStatusRow(
        title: t("destroy_data_messages", "Chat History"),
        subtitle: t("destroy_data_messages_subtitle", "Clear message history and temporary files"),
        systemImage: "trash",
        tint: .red,
        badge: removedLabel
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_reset_agent_data_title", "Agent data"),
        subtitle: t("cc_reset_agent_data_subtitle", "Tasks, workspaces, memories, knowledge, Skills, workflows, and audit history"),
        systemImage: "person.crop.circle.badge.gearshape",
        tint: .red,
        badge: removedLabel
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_reset_settings_assets_title", "Settings and downloaded assets"),
        subtitle: t("cc_reset_settings_assets_subtitle", "Language, text size, voice models, connectors, caches, and internal backups"),
        systemImage: "gearshape",
        tint: .red,
        badge: removedLabel
      )
    }
  }

  private var confirmationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_reset_confirmation_section", "Final Confirmation"))
      GalaxySSISecurityActionRow(
        title: t("cc_reset_begin_title", "Review and reset GalaxySSI"),
        subtitle: t("cc_reset_begin_subtitle", "Requires an explicit confirmation phrase before any data is removed"),
        systemImage: "exclamationmark.triangle",
        tint: .red,
        badge: t("cc_reset_irreversible", "Irreversible")
      ) {
        confirmationPhrase = ""
        confirmationError = ""
        showingConfirmation = true
      }
      if !confirmationError.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_reset_dialog_title", "Reset GalaxySSI?"),
          subtitle: confirmationError,
          systemImage: "xmark.circle",
          tint: .red,
          badge: t("galaxyssi.status.needs_setup", "Needs Setup")
        )
      }
      if !statusMessage.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("destroy_data_title", "Reset Data"),
          subtitle: statusMessage,
          systemImage: "checkmark.circle",
          tint: .galaxySSIAccent,
          badge: t("galaxyssi.status.ready", "Ready")
        )
      }
    }
  }

  private var footer: some View {
    Text(t(
      "cc_reset_footer",
      "Create an encrypted backup first if you may need this identity, trust graph, or history again."
    ))
    .font(.system(size: 12))
    .foregroundColor(.galaxySSITextSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.horizontal, 4)
    .padding(.top, 2)
  }

  private var removedLabel: String {
    t("cc_reset_removed_status", "Removed")
  }

  private func confirmReset() {
    guard confirmationPhrase.trimmingCharacters(in: .whitespacesAndNewlines) == "RESET" else {
      confirmationError = t("cc_reset_input_error", "Enter RESET exactly to continue")
      confirmationPhrase = ""
      return
    }
    store.destroyAllPrivateData()
    statusMessage = t("destroy_data_success", "All data cleared. Reinitializing now.")
    confirmationPhrase = ""
    confirmationError = ""
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      presentationMode.wrappedValue.dismiss()
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
