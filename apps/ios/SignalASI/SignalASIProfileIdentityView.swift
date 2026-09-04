import SwiftUI
import UIKit

struct SignalASIProfileIdentityView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var statusMessage = ""
  @State private var showingQRCode = false
  @State private var showingAvatarPicker = false

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_profile_title", "My SignalASI"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.status.ready", "Ready"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $showingQRCode) {
      MyContactQRCodeView()
    }
    .sheet(isPresented: $showingAvatarPicker) {
      PhotoLibraryPickerView { attachment in
        guard let avatarData = profileAvatarData(from: attachment.data),
              store.updateProfileAvatar(data: avatarData) else {
          statusMessage = t("signalasi.profile.avatar_failed", "Profile photo could not be saved")
          return
        }
        statusMessage = t("signalasi.profile.avatar_saved", "Profile photo updated")
      }
    }
  }

  private var hero: some View {
    HStack(alignment: .center, spacing: 12) {
      Button { showingAvatarPicker = true } label: {
        SignalASIProfileAvatar(
          data: store.profile.avatarData,
          size: 58,
          fingerprint: store.profile.identityFingerprint
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("signalasi.profile.avatar_edit", "Change profile photo")))
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(store.profile.name.ifBlank(t("signalasi.settings.profile", "Profile")))
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
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
          .foregroundColor(.signalASITextSecondary)
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
      SignalASISecuritySectionTitle(title: t("cc_section_identity", "Identity"))
      SignalASIProfileNicknameRow(
        title: t("cc_nickname_title", "Nickname"),
        subtitle: t("cc_nickname_subtitle", "Shown to verified contacts"),
        badge: store.profile.name.ifBlank(t("signalasi.settings.profile", "Profile")),
        text: Binding(
          get: { store.profile.name },
          set: { store.updateProfileName($0) }
        ),
        onSubmit: publishProfileUpdate
      )
      SignalASISecurityActionRow(
        title: t("signalasi.profile.avatar", "Profile Photo"),
        subtitle: t("signalasi.profile.avatar_subtitle", "Shown with your outgoing messages"),
        systemImage: "person.crop.circle",
        tint: .blue,
        badge: t("common_edit", "Edit")
      ) {
        showingAvatarPicker = true
      }
      if store.profile.avatarData != nil {
        SignalASISecurityActionRow(
          title: t("signalasi.profile.avatar_remove", "Remove Profile Photo"),
          subtitle: t("signalasi.profile.avatar_remove_subtitle", "Restore the default identity image"),
          systemImage: "trash",
          tint: .red,
          badge: t("signalasi.common.remove", "Remove")
        ) {
          store.updateProfileAvatar(data: nil)
          statusMessage = t("signalasi.profile.avatar_removed", "Profile photo removed")
        }
      }
      SignalASISecurityActionRow(
        title: t("settings_signalasi_id", "SignalASI ID"),
        subtitle: store.profile.signalASIId.ifBlank(t("signalasi.status.unknown", "Unknown")),
        systemImage: "link",
        tint: .blue,
        badge: t("common_copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(store.profile.signalASIId, message: t("signalasi.security_center.copied_signalasi_id", "SignalASI ID copied"))
      }
      SignalASISecurityActionRow(
        title: t("signalasi.discover.my_qr_title", "My QR Code"),
        subtitle: t("signalasi.discover.my_qr_subtitle", "Show this device identity"),
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
      let saved = t("signalasi.profile.name_saved", "Profile updated")
      statusMessage = delivered > 0
        ? String(
          format: t("signalasi.profile.updated_notified", "Profile updated and shared with %d verified contacts"),
          delivered
        )
        : saved
    }
  }

  private var statusSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("common_status", "Status"))
      SignalASISecurityNavigationRow(
        title: t("cc_agent_identity_title", "Agent Identity"),
        subtitle: t("cc_agent_identity_subtitle", "This device can execute autonomous tasks"),
        systemImage: "cpu",
        tint: agentTint,
        badge: agentBadge
      ) {
        AgentSafetySettingsView()
      }
      SignalASISecurityStatusRow(
        title: t("cc_device_info_title", "Device Information"),
        subtitle: deviceInfo,
        systemImage: "iphone",
        tint: .blue,
        badge: t("cc_device_profile_phone", "Phone profile")
      )
      SignalASISecurityStatusRow(
        title: t("cc_section_connected_devices", "Connected devices"),
        subtitle: String(
          format: t("cc_trusted_devices_badge", "%d trusted devices"),
          store.serverLinks.count
        ),
        systemImage: "desktopcomputer",
        tint: store.serverLinks.isEmpty ? .orange : .signalASIAccent,
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
    store.agentSafetySettings.executionPaused ? .orange : .signalASIAccent
  }

  private var deviceInfo: String {
    "\(UIDevice.current.model) - iOS \(UIDevice.current.systemVersion) - \(t("cc_device_profile_phone", "Phone profile"))"
  }

  private func copy(_ value: String, message: String) {
    UIPasteboard.general.string = value
    statusMessage = message
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIIdentityRecoveryExportView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var password = ""
  @State private var backupDocument: SignalASIBackupDocument?
  @State private var backupExportPresented = false
  @State private var statusMessage = ""
  @State private var statusIsError = false

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_identity_recovery_title", "Identity Recovery Package"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("cc_identity_recovery_title", "Identity Recovery Package"),
            subtitle: t("cc_identity_recovery_subtitle", "Export encrypted identity and trust relationships"),
            systemImage: "square.and.arrow.up",
            tint: .orange,
            badge: t("cc_status_secure", "Secure")
          )
          SignalASISecuritySectionTitle(title: t("cc_section_identity", "Identity"))
          SignalASISecurityStatusRow(
            title: t("settings_signalasi_id", "SignalASI ID"),
            subtitle: store.profile.signalASIId.ifBlank(t("signalasi.status.unknown", "Unknown")),
            systemImage: "link",
            tint: .blue,
            badge: t("cc_identity_verified", "Identity verified"),
            monospacedSubtitle: true
          )
          SignalASISecurityStatusRow(
            title: t("cc_section_connected_devices", "Connected devices"),
            subtitle: String(
              format: t("cc_trusted_devices_badge", "%d trusted devices"),
              store.serverLinks.count
            ),
            systemImage: "desktopcomputer",
            tint: store.serverLinks.isEmpty ? .orange : .signalASIAccent,
            badge: "\(store.serverLinks.count)"
          )
          SignalASISecuritySectionTitle(title: t("cc_identity_recovery_title", "Identity Recovery Package"))
          SecureField(t("signalasi.settings.password", "Password"), text: $password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(.system(size: 15))
            .foregroundColor(.signalASITextPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(Color.signalASISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          SignalASISecurityPrimaryButton(
            title: t("signalasi.common.export", "Export"),
            systemImage: "square.and.arrow.up",
            tint: .signalASIAccent
          ) {
            exportIdentityRecovery()
          }
          .disabled(password.count < SignalASIBackupManager.minimumPasswordLength)
          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.status.ready", "Ready"),
              subtitle: statusMessage,
              systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
              tint: statusIsError ? .red : .signalASIAccent,
              badge: statusIsError ? t("cc_status_degraded", "Degraded") : t("cc_status_ready", "Ready")
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileExporter(
      isPresented: $backupExportPresented,
      document: backupDocument,
      contentType: .data,
      defaultFilename: SignalASIBackupManager.defaultFilename()
    ) { result in
      switch result {
      case .success:
        setStatus(t("signalasi.backup.exported", "Backup exported."), isError: false)
      case .failure(let error):
        setStatus(error.localizedDescription, isError: true)
      }
    }
  }

  private func exportIdentityRecovery() {
    let payload = store.exportBackupPayload(includeContacts: true, includeMessages: false)
    setStatus(t("signalasi.backup.preparing", "Preparing backup..."), isError: false)
    do {
      let data = try SignalASIBackupManager.encryptPayload(payload, password: password)
      backupDocument = SignalASIBackupDocument(data: data)
      backupExportPresented = true
      setStatus(t("signalasi.backup.ready", "Backup ready."), isError: false)
    } catch {
      setStatus(error.localizedDescription, isError: true)
    }
  }

  private func setStatus(_ value: String, isError: Bool) {
    statusMessage = value
    statusIsError = isError
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIProfileAvatar: View {
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
        SignalASIIdenticonView(
          pattern: SignalASIIdenticon.fromIdentityFingerprint(fingerprint)
        )
      } else {
        SignalASILogoView(size: size, cornerRadius: 10)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct SignalASIProfileNicknameRow: View {
  var title: String
  var subtitle: String
  var badge: String
  @Binding var text: String
  var onSubmit: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecurityStatusRow(
        title: title,
        subtitle: subtitle,
        systemImage: "person.crop.circle",
        tint: .blue,
        badge: badge
      )
      TextField(title, text: $text)
        .font(.system(size: 15))
        .foregroundColor(.signalASITextPrimary)
        .textInputAutocapitalization(.words)
        .disableAutocorrection(true)
        .onSubmit { onSubmit() }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(Color.signalASISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }
}
