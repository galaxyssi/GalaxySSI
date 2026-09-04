import SwiftUI
import UIKit

struct ContactDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var remarkName = ""
  @State private var remarkEditorExpanded = false
  @State private var deleteMessagesWhenDeleting = false
  @State private var showingDeleteConfirmation = false
  @State private var statusText = ""
  @State private var statusIsError = false
  var contactId: String

  private var contact: GalaxySSIContact? {
    store.contact(id: contactId)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("contact_detail_title", "Contact Profile"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let contact {
            ContactDetailHeroView(
              contact: contact,
              displayName: contactDisplayName(contact),
              galaxySSIId: hidesTechnicalIdentity(contact) ? "" : galaxySSIId(for: contact),
              statusBadge: deliveryBadge(for: contact)
            )
            primaryChatButton(contact)
            identitySection(contact)
            phoneContactSecuritySection(contact)
            deviceSection(contact)
            routeSection(contact)
            cloudModelSection(contact)
            manageSection(contact)
          } else {
            ContactDetailEmptyView(
              title: t("galaxyssi.contact_detail.not_found_title", "Contact not found."),
              subtitle: t(
                "galaxyssi.contact_detail.not_found_subtitle",
                "This contact may have been deleted or restored from an older backup."
              )
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: syncRemarkName)
    .onChange(of: contact?.displayName ?? "") { _ in
      syncRemarkName()
    }
    .alert(t("delete_contact_title", "Delete Contact"), isPresented: $showingDeleteConfirmation) {
      Button(role: .destructive) {
        deleteContact()
      } label: {
        Text(t("common_delete", "Delete"))
      }
      Button(role: .cancel) {
      } label: {
        Text(t("common_cancel", "Cancel"))
      }
    } message: {
      Text(
        deleteMessagesWhenDeleting
          ? t(
            "galaxyssi.contact_detail.delete_with_chat_message",
            "The contact and chat history will be removed from this device."
          )
          : t("delete_contact_subtitle", "Add and verify this contact again before communicating.")
      )
    }
  }

  private func primaryChatButton(_ contact: GalaxySSIContact) -> some View {
    NavigationLink(destination: GalaxySSIContactMessagingDestination(contactId: contact.id)) {
      HStack(spacing: 8) {
        Image(systemName: "bubble.left.and.bubble.right")
          .font(.system(size: 16, weight: .semibold))
        Text(t("contact_send_message", "Message"))
          .font(.system(size: 17, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(Color.galaxySSIAccent)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func identitySection(_ contact: GalaxySSIContact) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("contact_section_identity", "Identity"))
      GalaxySSISecurityActionRow(
        title: t("contact_remark_name", "Remark Name"),
        subtitle: contact.displayName,
        systemImage: "pencil",
        tint: .galaxySSIAccent,
        badge: t("common_edit", "Edit")
      ) {
        remarkEditorExpanded.toggle()
      }
      if remarkEditorExpanded {
        ContactDetailRemarkEditor(
          remarkName: $remarkName,
          title: t("contact_edit_remark_title", "Edit Remark"),
          placeholder: t("contact_remark_name", "Remark Name"),
          saveTitle: t("common_save", "Save"),
          disabled: remarkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            remarkName == contact.displayName
        ) {
          saveRemark()
        }
      }
      if contact.deliveryMode != .cloudAPI {
        ContactDetailCopyRow(
          title: t("settings_galaxyssi_id", "GalaxySSI ID"),
          value: galaxySSIId(for: contact),
          systemImage: "link",
          tint: .blue,
          badge: t("common_copy", "Copy"),
          copiedTitle: t("galaxyssi.contact_detail.copied_id", "GalaxySSI ID copied"),
          onCopy: setStatus
        )
      }
      statusRowIfNeeded
    }
  }

  private func hidesTechnicalIdentity(_ contact: GalaxySSIContact) -> Bool {
    contact.deliveryMode == .cloudAPI ||
      contact.deliveryMode == .pcConnector ||
      !contact.agentKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  @ViewBuilder
  private func phoneContactSecuritySection(_ contact: GalaxySSIContact) -> some View {
    if isPhoneDirectContact(contact) {
      VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.contact_detail.secure_direct", "Secure Direct Connection"))
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.contact_detail.signal_session", "Signal Protected"),
        subtitle: t(
          "galaxyssi.contact_detail.signal_session_subtitle",
          "Verified QR identity with end-to-end encrypted messages through this contact's private inbox."
        ),
        systemImage: "lock.shield.fill",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.contact_detail.identity_verified", "Verified")
      )
      }
    }
  }

  @ViewBuilder
  private func deviceSection(_ contact: GalaxySSIContact) -> some View {
    let hasDeviceMetadata = [
      contact.deviceName,
      contact.deviceManufacturer,
      contact.deviceModel,
      contact.devicePlatform,
      contact.devicePlatformVersion,
      contact.deviceProfileName,
      contact.deviceHostName
    ].contains { value in
      !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    if contact.type == "device" || hasDeviceMetadata {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("galaxyssi.contact_detail.device_section", "Device"))
        if let deviceName = contact.deviceName?.nonEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.device_name", "Device Name"),
            subtitle: deviceName,
            systemImage: "iphone",
            tint: .blue,
            badge: t("galaxyssi.contact_detail.device", "Device")
          )
        }
        if let model = contact.deviceModel?.nonEmpty {
          let manufacturer = contact.deviceManufacturer?.nonEmpty
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.device_model", "Model"),
            subtitle: manufacturer.map { "\($0) \(model)" } ?? model,
            systemImage: "cpu",
            tint: .teal,
            badge: t("galaxyssi.contact_detail.hardware", "Hardware")
          )
        }
        if let platform = contact.devicePlatform?.nonEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.platform", "Platform"),
            subtitle: platform,
            systemImage: "globe",
            tint: .teal,
            badge: t("galaxyssi.contact_detail.device", "Device")
          )
        }
        if let version = contact.devicePlatformVersion?.nonEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.platform_version", "Platform Version"),
            subtitle: version,
            systemImage: "gearshape",
            tint: .orange,
            badge: contact.deviceProfileName?.nonEmpty ?? t("galaxyssi.contact_detail.platform", "Platform")
          )
        }
        if let hostName = contact.deviceHostName?.nonEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.host_name", "Host Name"),
            subtitle: hostName,
            systemImage: "network",
            tint: .indigo,
            badge: t("galaxyssi.contact_detail.host", "Host")
          )
        }
      }
    }
  }

  @ViewBuilder
  private func connectorSection(_ contact: GalaxySSIContact) -> some View {
    if contact.deliveryMode.isGalaxySSILinkFamily {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("contact_connector_section", "Connector"))
        GalaxySSISecurityStatusRow(
          title: t("common_status", "Status"),
          subtitle: contact.setupDetail
            .ifBlank(contact.connectorSetupNextStep)
            .ifBlank(setupStatusText(for: contact)),
          systemImage: "person.crop.circle.badge.checkmark",
          tint: setupTint(for: contact),
          badge: setupStatusText(for: contact)
        )
        if !contact.connectorAgentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContactDetailCopyRow(
            title: t("galaxyssi.contact_detail.agent_id", "Agent ID"),
            value: contact.connectorAgentId,
            systemImage: "number.circle",
            tint: .teal,
            badge: t("common_copy", "Copy"),
            copiedTitle: t("galaxyssi.contact_detail.copied_agent_id", "Agent ID copied"),
            monospacedSubtitle: true,
            onCopy: setStatus
          )
        }
        if !contact.connectorSetupNextStep.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("common_next_step", "Next Step"),
            subtitle: contact.connectorSetupNextStep,
            systemImage: "arrow.right.circle",
            tint: .orange,
            badge: t("galaxyssi.common.view", "View")
          )
        }
        if !contact.connectorDesktopAccessProfile.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.access_profile", "Access Profile"),
            subtitle: contact.connectorDesktopAccessProfile,
            systemImage: "lock.shield",
            tint: .purple,
            badge: t("galaxyssi.contact_detail.desktop_access", "Desktop Access"),
            monospacedSubtitle: true
          )
        }
        if !contact.connectorDesktopAccessScopes.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.contact_detail.access_scopes", "Access Scopes"),
            subtitle: contact.connectorDesktopAccessScopes.joined(separator: ", "),
            systemImage: "list.bullet",
            tint: .blue,
            badge: String(
              format: t("galaxyssi.contact_detail.scope_count", "%d scopes"),
              contact.connectorDesktopAccessScopes.count
            ),
            monospacedSubtitle: true
          )
        }
        if !contact.desktopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           !contact.desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContactDetailCopyRow(
            title: t("galaxyssi.pairing.section_desktop", "Desktop"),
            value: contact.desktopName.ifBlank(contact.desktopId),
            copyValue: contact.desktopId.ifBlank(contact.desktopName),
            systemImage: "desktopcomputer",
            tint: .galaxySSIInsightText,
            badge: t("common_copy", "Copy"),
            copiedTitle: t("galaxyssi.contact_detail.copied_desktop", "Desktop copied"),
            onCopy: setStatus
          )
        }
      }
    }
  }

  @ViewBuilder
  private func routeSection(_ contact: GalaxySSIContact) -> some View {
    if hasRouteDetails(contact) {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("galaxyssi.contact_detail.route", "Route"))
        if let mqttTopic = contact.mqttTopic, !mqttTopic.isEmpty {
          ContactDetailCopyRow(
            title: t("galaxyssi.contact_detail.topic", "Topic"),
            value: mqttTopic,
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .purple,
            badge: t("common_copy", "Copy"),
            copiedTitle: t("galaxyssi.contact_detail.copied_topic", "Topic copied"),
            monospacedSubtitle: true,
            onCopy: setStatus
          )
        }
        if let mqttInboxTopic = contact.mqttInboxTopic, !mqttInboxTopic.isEmpty {
          ContactDetailCopyRow(
            title: t("galaxyssi.contact_detail.inbox", "Inbox"),
            value: mqttInboxTopic,
            systemImage: "tray.and.arrow.down",
            tint: .teal,
            badge: t("common_copy", "Copy"),
            copiedTitle: t("galaxyssi.contact_detail.copied_inbox", "Inbox copied"),
            monospacedSubtitle: true,
            onCopy: setStatus
          )
        }
        if let signalBundleRef = contact.signalBundleRef, !signalBundleRef.isEmpty {
          ContactDetailCopyRow(
            title: t("galaxyssi.contact_detail.bundle", "Bundle"),
            value: signalBundleRef,
            systemImage: "shippingbox",
            tint: .orange,
            badge: t("common_copy", "Copy"),
            copiedTitle: t("galaxyssi.contact_detail.copied_bundle", "Bundle copied"),
            monospacedSubtitle: true,
            onCopy: setStatus
          )
        }
      }
    }
  }

  @ViewBuilder
  private func cloudModelSection(_ contact: GalaxySSIContact) -> some View {
    if contact.deliveryMode == .cloudAPI {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("galaxyssi.status.cloud_model", "Cloud Model"))
        GalaxySSISecurityStatusRow(
          title: contact.cloudProvider.ifBlank(t("galaxyssi.status.cloud_model", "Cloud Model")),
          subtitle: t("galaxyssi.contact_detail.cloud_provider_subtitle", "Configured cloud model provider"),
          systemImage: "cloud",
          tint: .purple,
          badge: t("galaxyssi.status.ready", "Ready")
        )
        if contact.cloudModels.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("cloud_no_models", "No Models"),
            subtitle: t("cloud_no_models_subtitle", "Add a model configuration first"),
            systemImage: "exclamationmark.triangle",
            tint: .orange,
            badge: t("galaxyssi.status.needs_setup", "Needs Setup")
          )
        } else {
          ForEach(contact.cloudModels) { model in
            GalaxySSISecurityStatusRow(
              title: model.displayName,
              subtitle: model.modelId,
              systemImage: model.modelId == contact.selectedCloudModelId ? "checkmark.circle.fill" : "cpu",
              tint: model.modelId == contact.selectedCloudModelId ? .galaxySSIAccent : .blue,
              badge: model.modelId == contact.selectedCloudModelId
                ? t("section_current", "Current")
                : t("galaxyssi.common.available", "Available"),
              monospacedSubtitle: true
            )
          }
        }
      }
    }
  }

  private func manageSection(_ contact: GalaxySSIContact) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.common.manage", "Manage"))
      GalaxySSISecurityActionRow(
        title: t("delete_chat_title", "Delete Chat"),
        subtitle: t("delete_chat_subtitle", "Only local chat history is deleted. Contacts are not affected."),
        systemImage: "trash",
        tint: .orange,
        badge: t("common_delete", "Delete")
      ) {
        store.deleteMessages(for: contact.id)
        setStatus(t("delete_chat_toast", "Chat deleted"), isError: false)
      }
      ContactDetailToggleRow(
        title: t("galaxyssi.contact_detail.also_delete_chat", "Also Delete Chat History"),
        subtitle: t(
          "galaxyssi.contact_detail.delete_contact_chat_subtitle",
          "Apply when deleting the contact itself"
        ),
        systemImage: "bubble.left.and.bubble.right",
        tint: .orange,
        isOn: $deleteMessagesWhenDeleting
      )
      if contact.type == "device",
         let desktopId = contact.desktopId.nonEmpty,
         store.serverLinks.contains(where: { $0.paired && $0.desktopId == desktopId }) {
        GalaxySSISecurityNavigationRow(
          title: t("galaxyssi.security_center.revoke_this_pc", "Revoke this computer"),
          subtitle: t(
            "galaxyssi.security_center.revoke_this_pc_subtitle",
            "Delete this computer's Agent trust and sessions; scan again to connect"
          ),
          systemImage: "trash",
          tint: .red,
          badge: t("galaxyssi.security_center.revoke", "Revoke")
        ) {
          GalaxySSIRevokeDevicePairingView(desktopId: desktopId)
        }
      }
      GalaxySSISecurityActionRow(
        title: t("delete_contact_title", "Delete Contact"),
        subtitle: t("delete_contact_subtitle", "Add and verify this contact again before communicating."),
        systemImage: "person.crop.circle.badge.xmark",
        tint: .red,
        badge: t("common_delete", "Delete")
      ) {
        showingDeleteConfirmation = true
      }
    }
  }

  @ViewBuilder
  private var statusRowIfNeeded: some View {
    if !statusText.isEmpty {
      GalaxySSISecurityStatusRow(
        title: t("common_status", "Status"),
        subtitle: statusText,
        systemImage: statusIsError ? "xmark.circle" : "checkmark.circle",
        tint: statusIsError ? .red : .galaxySSIAccent,
        badge: statusIsError
          ? t("galaxyssi.status.needs_setup", "Needs Setup")
          : t("common_saved", "Saved")
      )
    }
  }

  private func hasRouteDetails(_ contact: GalaxySSIContact) -> Bool {
    [contact.mqttTopic, contact.mqttInboxTopic, contact.signalBundleRef].contains { value in
      !(value ?? "").isEmpty
    }
  }

  private func isPhoneDirectContact(_ contact: GalaxySSIContact) -> Bool {
    contact.type.caseInsensitiveCompare("person") == .orderedSame &&
      contact.isCommunicable &&
      contact.desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !(contact.mqttInboxTopic ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func syncRemarkName() {
    remarkName = contact?.displayName ?? ""
  }

  private func saveRemark() {
    if store.renameContact(id: contactId, displayName: remarkName) {
      remarkEditorExpanded = false
      setStatus(t("contact_remark_saved", "Remark updated"), isError: false)
    } else {
      setStatus(t("galaxyssi.contact_detail.remark_save_failed", "Unable to save this remark."), isError: true)
    }
  }

  private func deleteContact() {
    guard let contact else { return }
    if contact.type == "device", let desktopId = contact.desktopId.nonEmpty {
      Task { @MainActor in
        _ = await coordinator.revokeDesktopPairing(
          desktopId: desktopId,
          deleteMessages: deleteMessagesWhenDeleting
        )
        dismiss()
      }
    } else if store.deleteContact(id: contact.id, deleteMessages: deleteMessagesWhenDeleting) {
      dismiss()
    } else {
      setStatus(t("galaxyssi.contact_detail.delete_failed", "Unable to delete this contact."), isError: true)
    }
  }

  private func galaxySSIId(for contact: GalaxySSIContact) -> String {
    contact.galaxySSIId.ifBlank(contact.id)
  }

  private func deliveryBadge(for contact: GalaxySSIContact) -> String {
    switch contact.deliveryMode {
    case .cloudAPI:
      return t("galaxyssi.status.cloud_model", "Cloud Model")
    case .link, .pcConnector:
      return setupStatusText(for: contact)
    case .local:
      return t("galaxyssi.status.ready", "Ready")
    }
  }

  private func setupStatusText(for contact: GalaxySSIContact) -> String {
    let normalized = contact.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "ready":
      return t("galaxyssi.status.ready", "Ready")
    case "pairing", "pending":
      return t("galaxyssi.pairing.status_pending", "Pending")
    case "paired":
      return t("common_paired", "Paired")
    case "needs_setup", "needs_pairing", "unverified":
      return t("galaxyssi.status.needs_setup", "Needs Setup")
    case "deleted":
      return t("galaxyssi.security_center.status_revoked", "Revoked")
    default:
      return contact.setupStatus.ifBlank(t("galaxyssi.status.unknown", "Unknown"))
    }
  }

  private func setupTint(for contact: GalaxySSIContact) -> Color {
    switch contact.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "ready", "paired":
      return .galaxySSIAccent
    case "pairing", "pending":
      return .orange
    case "deleted":
      return .red
    default:
      return .galaxySSITextSecondary
    }
  }

  private func setStatus(_ message: String, isError: Bool = false) {
    statusText = message
    statusIsError = isError
  }

  private func contactDisplayName(_ contact: GalaxySSIContact) -> String {
    switch contact.id {
    case "system":
      return t("chat_system_notice", "System Notifications")
    case "me":
      return store.profile.name.ifBlank(GalaxySSIDeviceIdentityName.current(profile: store.profile))
    default:
      return contact.displayName
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct ContactDetailHeroView: View {
  var contact: GalaxySSIContact
  var displayName: String
  var galaxySSIId: String
  var statusBadge: String

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      AvatarView(contact: contact, size: 72)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(displayName)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(statusBadge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.galaxySSIAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(galaxySSIId)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        if !contact.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(contact.setupDetail)
            .font(.system(size: 13))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct ContactDetailRemarkEditor: View {
  @Binding var remarkName: String
  var title: String
  var placeholder: String
  var saveTitle: String
  var disabled: Bool
  var onSave: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
      TextField(placeholder, text: $remarkName)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled(true)
        .font(.system(size: 16))
        .foregroundColor(.galaxySSITextPrimary)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.galaxySSISearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Button(action: onSave) {
        Label(saveTitle, systemImage: "checkmark")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(disabled ? Color.galaxySSITextSecondary : Color.galaxySSIAccent)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(disabled)
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct ContactDetailCopyRow: View {
  var title: String
  var value: String
  var copyValue: String? = nil
  var systemImage: String
  var tint: Color
  var badge: String
  var copiedTitle: String
  var monospacedSubtitle: Bool = false
  var onCopy: (String, Bool) -> Void

  var body: some View {
    Button {
      let copied = (copyValue ?? value).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !copied.isEmpty else { return }
      UIPasteboard.general.string = copied
      onCopy(copiedTitle, false)
    } label: {
      GalaxySSISecurityRowContent(
        title: title,
        subtitle: value.ifBlank("-"),
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        monospacedSubtitle: monospacedSubtitle,
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

private struct ContactDetailToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn)
        .labelsHidden()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct ContactDetailEmptyView: View {
  var title: String
  var subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: "person.crop.circle.badge.questionmark")
        .font(.system(size: 34, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
      Text(title)
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.galaxySSITextPrimary)
      Text(subtitle)
        .font(.system(size: 14))
        .foregroundColor(.galaxySSITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
