import SwiftUI
import UIKit

struct GalaxySSIProfileIdentityView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var statusMessage = ""
  @State private var showingQRCode = false
  @State private var showingAvatarPicker = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_profile_title", "My GalaxySSI"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("galaxyssi.status.ready", "Ready"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.ready", "Ready")
            )
          }
          identitySection
          statusSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $showingQRCode) {
      MyContactQRCodeView()
    }
    .sheet(isPresented: $showingAvatarPicker) {
      PhotoLibraryPickerView { attachment in
        guard let avatarData = profileAvatarData(from: attachment.data),
              store.updateProfileAvatar(data: avatarData) else {
          statusMessage = t("galaxyssi.profile.avatar_failed", "Profile photo could not be saved")
          return
        }
        statusMessage = t("galaxyssi.profile.avatar_saved", "Profile photo updated")
      }
    }
  }

  private var hero: some View {
    HStack(alignment: .center, spacing: 12) {
      Button { showingAvatarPicker = true } label: {
        GalaxySSIProfileAvatar(
          data: store.profile.avatarData,
          size: 58,
          fingerprint: store.profile.identityFingerprint
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("galaxyssi.profile.avatar_edit", "Change profile photo")))
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(store.profile.name.ifBlank(t("galaxyssi.settings.profile", "Profile")))
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(agentBadge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(agentTint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(agentTint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(t("cc_profile_subtitle_ios", "Identity protected by the iOS security boundary"))
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private func profileAvatarData(from data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let longestSide = max(image.size.width, image.size.height)
    let scale = min(1, 1_024 / max(longestSide, 1))
    let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    let rendered = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
    return rendered.jpegData(compressionQuality: 0.78) ?? rendered.jpegData(compressionQuality: 0.55)
  }

  private var identitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_identity", "Identity"))
      GalaxySSIProfileNicknameRow(
        title: t("cc_nickname_title", "Nickname"),
        subtitle: t("cc_nickname_subtitle", "Shown to verified contacts"),
        badge: store.profile.name.ifBlank(t("galaxyssi.settings.profile", "Profile")),
        text: Binding(
          get: { store.profile.name },
          set: { store.updateProfileName($0) }
        ),
        onSubmit: publishProfileUpdate
      )
      GalaxySSISecurityActionRow(
        title: t("galaxyssi.profile.avatar", "Profile Photo"),
        subtitle: t("galaxyssi.profile.avatar_subtitle", "Shown with your outgoing messages"),
        systemImage: "person.crop.circle",
        tint: .blue,
        badge: t("common_edit", "Edit")
      ) {
        showingAvatarPicker = true
      }
      if store.profile.avatarData != nil {
        GalaxySSISecurityActionRow(
          title: t("galaxyssi.profile.avatar_remove", "Remove Profile Photo"),
          subtitle: t("galaxyssi.profile.avatar_remove_subtitle", "Restore the default identity image"),
          systemImage: "trash",
          tint: .red,
          badge: t("galaxyssi.common.remove", "Remove")
        ) {
          store.updateProfileAvatar(data: nil)
          statusMessage = t("galaxyssi.profile.avatar_removed", "Profile photo removed")
        }
      }
      GalaxySSISecurityActionRow(
        title: t("settings_galaxyssi_id", "GalaxySSI ID"),
        subtitle: store.profile.galaxySSIId.ifBlank(t("galaxyssi.status.unknown", "Unknown")),
        systemImage: "link",
        tint: .blue,
        badge: t("common_copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(store.profile.galaxySSIId, message: t("galaxyssi.security_center.copied_galaxyssi_id", "GalaxySSI ID copied"))
      }
      GalaxySSISecurityActionRow(
        title: t("galaxyssi.discover.my_qr_title", "My QR Code"),
        subtitle: t("galaxyssi.discover.my_qr_subtitle", "Show this device identity"),
        systemImage: "qrcode",
        tint: .purple,
        badge: t("common_view", "View")
      ) {
        showingQRCode = true
      }
    }
  }

  private func publishProfileUpdate() {
    Task {
      let delivered = await coordinator.publishProfileUpdates()
      let saved = t("galaxyssi.profile.name_saved", "Profile updated")
      statusMessage = delivered > 0
        ? String(
          format: t("galaxyssi.profile.updated_notified", "Profile updated and shared with %d verified contacts"),
          delivered
        )
        : saved
    }
  }

  private var statusSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("common_status", "Status"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_agent_identity_title", "Agent Identity"),
        subtitle: t("cc_agent_identity_subtitle", "This device can execute autonomous tasks"),
        systemImage: "cpu",
        tint: agentTint,
        badge: agentBadge
      ) {
        AgentSafetySettingsView()
      }
      GalaxySSISecurityStatusRow(
        title: t("cc_device_info_title", "Device Information"),
        subtitle: deviceInfo,
        systemImage: "iphone",
        tint: .blue,
        badge: t("cc_device_profile_phone", "Phone profile")
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_section_connected_devices", "Connected devices"),
        subtitle: String(
          format: t("cc_trusted_devices_badge", "%d trusted devices"),
          store.serverLinks.count
        ),
        systemImage: "desktopcomputer",
        tint: store.serverLinks.isEmpty ? .orange : .galaxySSIAccent,
        badge: "\(store.serverLinks.count)"
      )
    }
  }

  private var agentBadge: String {
    store.agentSafetySettings.executionPaused
      ? t("on_device_agent_status_paused", "Paused")
      : t("status_enabled", "Enabled")
  }

  private var agentTint: Color {
    store.agentSafetySettings.executionPaused ? .orange : .galaxySSIAccent
  }

  private var deviceInfo: String {
    "\(UIDevice.current.model) - iOS \(UIDevice.current.systemVersion) - \(t("cc_device_profile_phone", "Phone profile"))"
  }

  private func copy(_ value: String, message: String) {
    UIPasteboard.general.string = value
    statusMessage = message
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIIdentityRecoveryExportView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var password = ""
  @State private var backupDocument: GalaxySSIBackupDocument?
  @State private var backupExportPresented = false
  @State private var statusMessage = ""
  @State private var statusIsError = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_identity_recovery_title", "Identity Recovery Package"),
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
            title: t("cc_identity_recovery_title", "Identity Recovery Package"),
            subtitle: t("cc_identity_recovery_subtitle", "Export encrypted identity and trust relationships"),
            systemImage: "square.and.arrow.up",
            tint: .orange,
            badge: t("cc_status_secure", "Secure")
          )
          GalaxySSISecuritySectionTitle(title: t("cc_section_identity", "Identity"))
          GalaxySSISecurityStatusRow(
            title: t("settings_galaxyssi_id", "GalaxySSI ID"),
            subtitle: store.profile.galaxySSIId.ifBlank(t("galaxyssi.status.unknown", "Unknown")),
            systemImage: "link",
            tint: .blue,
            badge: t("cc_identity_verified", "Identity verified"),
            monospacedSubtitle: true
          )
          GalaxySSISecurityStatusRow(
            title: t("cc_section_connected_devices", "Connected devices"),
            subtitle: String(
              format: t("cc_trusted_devices_badge", "%d trusted devices"),
              store.serverLinks.count
            ),
            systemImage: "desktopcomputer",
            tint: store.serverLinks.isEmpty ? .orange : .galaxySSIAccent,
            badge: "\(store.serverLinks.count)"
          )
          GalaxySSISecuritySectionTitle(title: t("cc_identity_recovery_title", "Identity Recovery Package"))
          SecureField(t("galaxyssi.settings.password", "Password"), text: $password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(.system(size: 15))
            .foregroundColor(.galaxySSITextPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(Color.galaxySSISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          GalaxySSISecurityPrimaryButton(
            title: t("galaxyssi.common.export", "Export"),
            systemImage: "square.and.arrow.up",
            tint: .galaxySSIAccent
          ) {
            exportIdentityRecovery()
          }
          .disabled(password.count < GalaxySSIBackupManager.minimumPasswordLength)
          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("galaxyssi.status.ready", "Ready"),
              subtitle: statusMessage,
              systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
              tint: statusIsError ? .red : .galaxySSIAccent,
              badge: statusIsError ? t("cc_status_degraded", "Degraded") : t("cc_status_ready", "Ready")
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
    .fileExporter(
      isPresented: $backupExportPresented,
      document: backupDocument,
      contentType: .data,
      defaultFilename: GalaxySSIBackupManager.defaultFilename()
    ) { result in
      switch result {
      case .success:
        setStatus(t("galaxyssi.backup.exported", "Backup exported."), isError: false)
      case .failure(let error):
        setStatus(error.localizedDescription, isError: true)
      }
    }
  }

  private func exportIdentityRecovery() {
    let payload = store.exportBackupPayload(includeContacts: true, includeMessages: false)
    setStatus(t("galaxyssi.backup.preparing", "Preparing backup..."), isError: false)
    do {
      let data = try GalaxySSIBackupManager.encryptPayload(payload, password: password)
      backupDocument = GalaxySSIBackupDocument(data: data)
      backupExportPresented = true
      setStatus(t("galaxyssi.backup.ready", "Backup ready."), isError: false)
    } catch {
      setStatus(error.localizedDescription, isError: true)
    }
  }

  private func setStatus(_ value: String, isError: Bool) {
    statusMessage = value
    statusIsError = isError
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIProfileAvatar: View {
  var data: Data?
  var size: CGFloat
  var fingerprint: String = ""

  var body: some View {
    Group {
      if let data, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else if fingerprint.count == 64 {
        GalaxySSIIdenticonView(
          pattern: GalaxySSIIdenticon.fromIdentityFingerprint(fingerprint)
        )
      } else {
        GalaxySSILogoView(size: size, cornerRadius: 10)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct GalaxySSIProfileNicknameRow: View {
  var title: String
  var subtitle: String
  var badge: String
  @Binding var text: String
  var onSubmit: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecurityStatusRow(
        title: title,
        subtitle: subtitle,
        systemImage: "person.crop.circle",
        tint: .blue,
        badge: badge
      )
      TextField(title, text: $text)
        .font(.system(size: 15))
        .foregroundColor(.galaxySSITextPrimary)
        .textInputAutocapitalization(.words)
        .disableAutocorrection(true)
        .onSubmit { onSubmit() }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }
}
