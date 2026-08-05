import SwiftUI

struct SignalASIDesktopControlView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var selectedDesktopId = ""
  private let initialDesktopId: String

  init(initialDesktopId: String = "") {
    self.initialDesktopId = initialDesktopId
    _selectedDesktopId = State(initialValue: initialDesktopId)
  }

  private var desktopLinks: [ServerLink] {
    store.serverLinks.filter(\.paired).sorted {
      $0.desktopName.localizedCaseInsensitiveCompare($1.desktopName) == .orderedAscending
    }
  }

  private var selectedLink: ServerLink? {
    let selected = selectedDesktopId.ifBlank(desktopLinks.first?.desktopId ?? "")
    return desktopLinks.first { $0.desktopId == selected }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("desktop_control_title", "Control Computer"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASIDesktopControlHero(
            title: t("desktop_control_title", "Control Computer"),
            subtitle: t("desktop_control_home_subtitle", "View the computer screen and send approved mouse or keyboard actions from this phone"),
            systemImage: "desktopcomputer",
            tint: .blue,
            badge: String(format: t("signalasi.device.count_devices", "%d devices"), desktopLinks.count)
          )
          pairedComputersSection
          if let link = selectedLink {
            SignalASIDesktopControlDetail(
              link: link,
              mqttConnected: coordinator.mqttClient.isConnected,
              t: t
            )
          } else {
            noPairedComputerSection
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      if !initialDesktopId.isEmpty, desktopLinks.contains(where: { $0.desktopId == initialDesktopId }) {
        selectedDesktopId = initialDesktopId
      } else if selectedDesktopId.isEmpty {
        selectedDesktopId = desktopLinks.first?.desktopId ?? ""
      }
    }
  }

  private var pairedComputersSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionTitle(t("desktop_control_computers", "Paired computers"))
      if desktopLinks.isEmpty {
        NavigationLink(destination: AddContactView(autoOpenScanner: true)) {
          SignalASIDesktopControlRow(
            title: t("signalasi.security.no_paired_pc", "No paired computer"),
            subtitle: t("signalasi.security.no_paired_pc_subtitle", "Scan a SignalASI Desktop QR code to pair this phone"),
            systemImage: "qrcode.viewfinder",
            tint: .orange,
            badge: t("signalasi.pairing.action_scan", "Scan"),
            showsDisclosure: true
          )
        }
        .buttonStyle(.plain)
      } else {
        ForEach(desktopLinks) { link in
          Button {
            selectedDesktopId = link.desktopId
          } label: {
            SignalASIDesktopControlRow(
              title: link.desktopName.ifBlank(t("desktop_control_title", "Control Computer")),
              subtitle: fingerprint(link.desktopFingerprint),
              systemImage: "desktopcomputer",
              tint: link.fullDesktopExecutor ? .signalASIAccent : .orange,
              badge: statusLabel(link),
              showsDisclosure: desktopLinks.count > 1
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var noPairedComputerSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionTitle(t("desktop_control_authorization", "Authorization"))
      SignalASIDesktopControlRow(
        title: t("desktop_control_authorization_required", "Re-pair with Desktop Executor access to authorize this app"),
        subtitle: t("desktop_control_picker_subtitle", "Choose a paired computer to view or control"),
        systemImage: "lock.shield",
        tint: .orange,
        badge: t("signalasi.status.needs_setup", "Needs Setup"),
        showsDisclosure: false
      )
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func statusLabel(_ link: ServerLink) -> String {
    guard link.paired else {
      return t("desktop_control_pending", "Pending")
    }
    if link.fullDesktopExecutor {
      return t("desktop_control_authorized", "Authorized")
    }
    return t("desktop_control_not_authorized", "Not authorized")
  }

  private func fingerprint(_ value: String) -> String {
    String(value.filter { $0.isLetter || $0.isNumber }.prefix(16))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIDesktopControlDetail: View {
  var link: ServerLink
  var mqttConnected: Bool
  var t: (String, String) -> String
  @State private var statusMessage = ""
  @State private var streamFps = 1

  private var authorized: Bool {
    link.paired && link.fullDesktopExecutor
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SignalASIDesktopControlHero(
        title: link.desktopName.ifBlank(t("desktop_control_title", "Control Computer")),
        subtitle: t("desktop_control_trusted_subtitle", "SignalASI Link encrypted remote session"),
        systemImage: "display",
        tint: authorized ? .signalASIAccent : .orange,
        badge: statusLabel
      )
      if !statusMessage.isEmpty {
        SignalASIDesktopControlRow(
          title: t("desktop_control_latest_action", "Latest action"),
          subtitle: statusMessage,
          systemImage: "checkmark.circle",
          tint: .signalASIAccent,
          badge: t("signalasi.status.ready", "Ready"),
          showsDisclosure: false
        )
      }
      surfacesSection
      displaySection
      actionsSection
      authorizationSection
      recentActivitySection
      Text(t("desktop_control_security_footer", "MQTT only transports data. Control actions are end-to-end encrypted, bound to device identity, replay-protected, and audited; live screen frames are signed, temporary, and not retained."))
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
        .padding(.horizontal, 4)
    }
  }

  private var surfacesSection: some View {
    section(t("desktop_control_surfaces", "Displays and windows")) {
      SignalASIDesktopControlRow(
        title: t("desktop_control_surface_select", "Select a display or window"),
        subtitle: t("desktop_control_surface_select_subtitle", "Load controllable surfaces from this computer"),
        systemImage: "rectangle.on.rectangle",
        tint: .blue,
        badge: t("desktop_control_surface_load", "Load"),
        showsDisclosure: false,
        enabled: authorized
      )
      SignalASIDesktopControlRow(
        title: t("desktop_control_surface_refresh", "Refresh surfaces"),
        subtitle: t("desktop_control_surface_refresh_subtitle", "Find connected displays and currently visible windows"),
        systemImage: "arrow.clockwise",
        tint: .blue,
        badge: t("desktop_control_surface_refresh_action", "Refresh"),
        showsDisclosure: false,
        enabled: authorized
      )
    }
  }

  private var displaySection: some View {
    section(t("desktop_control_live_display", "Remote display")) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.black.opacity(0.86))
        VStack(spacing: 10) {
          Image(systemName: authorized ? "display" : "lock.shield")
            .font(.system(size: 34, weight: .semibold))
            .foregroundColor(.signalASITextSecondary)
          Text(displayPlaceholder)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.signalASITextSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
        }
      }
      .frame(maxWidth: .infinity)
      .aspectRatio(16.0 / 10.0, contentMode: .fit)
      .accessibilityLabel(t("desktop_control_screen_content_description", "Encrypted desktop screenshot"))
      SignalASIDesktopControlActionRow(
        title: t("desktop_control_refresh_screen", "Refresh screen"),
        subtitle: t("desktop_control_refresh_screen_subtitle", "Capture a compressed desktop snapshot"),
        systemImage: "arrow.clockwise",
        tint: .signalASIAccent,
        badge: t("desktop_control_action_view_screen", "View screen"),
        enabled: authorized,
        action: markPendingAction
      )
      Menu {
        ForEach([1, 2, 3], id: \.self) { fps in
          Button(String(format: t("desktop_control_stream_rate", "%d FPS"), fps)) {
            streamFps = fps
            markPendingAction()
          }
        }
      } label: {
        SignalASIDesktopControlRow(
          title: t("desktop_control_stream_title", "Low-rate live view"),
          subtitle: t("desktop_control_stream_subtitle", "Encrypted adaptive refresh; pauses in the background"),
          systemImage: "dot.radiowaves.left.and.right",
          tint: .purple,
          badge: String(format: t("desktop_control_stream_rate", "%d FPS"), streamFps),
          showsDisclosure: true,
          enabled: authorized
        )
      }
      .buttonStyle(.plain)
      .disabled(!authorized)
      SignalASIDesktopControlActionRow(
        title: t("desktop_perception_title", "Screen perception"),
        subtitle: t("desktop_perception_subtitle", "Fuse UI controls, OCR, and screenshot evidence from the foreground window"),
        systemImage: "viewfinder",
        tint: .purple,
        badge: t("desktop_perception_capture_action", "Capture"),
        enabled: authorized,
        action: markPendingAction
      )
    }
  }

  private var actionsSection: some View {
    section(t("desktop_control_actions", "Controls")) {
      HStack(spacing: 8) {
        controlChip(t("desktop_control_scroll_up", "Scroll up"), "arrow.up", enabled: authorized)
        controlChip(t("desktop_control_scroll_down", "Scroll down"), "arrow.down", enabled: authorized)
      }
      HStack(spacing: 8) {
        controlChip(t("desktop_control_previous_window", "Previous window"), "arrow.left.square", enabled: authorized)
        controlChip(t("desktop_control_next_window", "Next window"), "arrow.right.square", enabled: authorized)
      }
      SignalASIDesktopControlActionRow(
        title: t("desktop_control_type_text", "Type text"),
        subtitle: t("desktop_control_type_text_subtitle", "Types into the focused app; do not use for passwords"),
        systemImage: "keyboard",
        tint: .blue,
        badge: t("desktop_control_action_type", "Type text"),
        enabled: authorized,
        action: markPendingAction
      )
      SignalASIDesktopControlActionRow(
        title: t("desktop_control_select_file", "Select Desktop file"),
        subtitle: t("desktop_control_select_file_subtitle", "Select an existing file in the active Windows file dialog"),
        systemImage: "folder",
        tint: .orange,
        badge: t("desktop_control_action_file_select", "Select file"),
        enabled: authorized,
        action: markPendingAction
      )
    }
  }

  private var authorizationSection: some View {
    section(t("desktop_control_authorization", "Authorization")) {
      SignalASIDesktopControlRow(
        title: t("desktop_control_access_profile", "Access profile"),
        subtitle: link.accessProfile.ifBlank(SignalASILinkProtocol.accessRestricted),
        systemImage: "lock.shield",
        tint: authorized ? .signalASIAccent : .orange,
        badge: link.fullDesktopExecutor
          ? t("signalasi.pairing.access_full", "Desktop Executor")
          : t("desktop_control_repair_executor_required", "Re-pair this phone with Start Desktop Executor enabled"),
        showsDisclosure: false
      )
      SignalASIDesktopControlRow(
        title: t("desktop_control_allowed_actions", "Allowed actions"),
        subtitle: allowedActions,
        systemImage: "checklist",
        tint: .blue,
        badge: String(format: t("desktop_control_allowed_action_count", "%d items"), link.accessScopes.count),
        showsDisclosure: false
      )
      SignalASIDesktopControlRow(
        title: t("desktop_control_grant_source", "Authorization source"),
        subtitle: link.fullDesktopExecutor
          ? t("desktop_control_grant_source_pairing", "Approved once while scanning the pairing QR")
          : t("desktop_control_authorization_required", "Re-pair with Desktop Executor access to authorize this app"),
        systemImage: "qrcode.viewfinder",
        tint: link.fullDesktopExecutor ? .signalASIAccent : .orange,
        badge: t("desktop_control_this_phone", "This phone"),
        showsDisclosure: false
      )
    }
  }

  private var recentActivitySection: some View {
    section(t("desktop_control_recent_activity", "Recent control activity")) {
      SignalASIDesktopControlRow(
        title: t("desktop_control_no_recent_activity", "No recent control activity"),
        subtitle: t("desktop_control_no_authorized_apps_subtitle", "This app has no Desktop execution record"),
        systemImage: "clock.arrow.circlepath",
        tint: .signalASITextSecondary,
        badge: mqttConnected ? t("signalasi.status.online", "Online") : t("signalasi.status.disconnected", "Disconnected"),
        showsDisclosure: false
      )
    }
  }

  private var displayPlaceholder: String {
    if authorized {
      return t("desktop_control_tap_refresh", "Refresh the screen to begin")
    }
    if !link.fullDesktopExecutor {
      return t("desktop_control_repair_executor_required", "Re-pair this phone with Start Desktop Executor enabled")
    }
    return t("desktop_control_authorization_required", "Re-pair with Desktop Executor access to authorize this app")
  }

  private var statusLabel: String {
    guard link.paired else {
      return t("desktop_control_pending", "Pending")
    }
    if authorized {
      return t("desktop_control_authorized", "Authorized")
    }
    if !link.fullDesktopExecutor {
      return t("desktop_control_repair_executor_required", "Re-pair this phone with Start Desktop Executor enabled")
    }
    return t("desktop_control_not_authorized", "Not authorized")
  }

  private var allowedActions: String {
    let labels = link.accessScopes.sorted().map { scope in
      switch scope {
      case SignalASILinkProtocol.scopeDesktopExecutor:
        return t("desktop_control_action_view_screen", "View screen")
      case SignalASILinkProtocol.scopeDesktopControl:
        return t("desktop_control_action_click", "Click")
      case SignalASILinkProtocol.scopeDesktopNativeTools:
        return t("desktop_control_action_type", "Type text")
      case SignalASILinkProtocol.scopeDesktopExternalFiles:
        return t("desktop_control_action_file_select", "Select file")
      case SignalASILinkProtocol.scopeAgentChat:
        return t("desktop_control_scope_agent_chat", "Agent chat")
      case SignalASILinkProtocol.scopeExplicitAttachments:
        return t("desktop_control_scope_explicit_attachments", "Explicit attachments")
      case SignalASILinkProtocol.scopeTaskWorkspace:
        return t("desktop_control_scope_task_workspace", "Task workspace")
      default:
        return scope
      }
    }
    return labels.isEmpty ? "-" : labels.joined(separator: " / ")
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
        .padding(.horizontal, 4)
        .padding(.top, 2)
      content()
    }
  }

  private func controlChip(_ title: String, _ systemImage: String, enabled: Bool) -> some View {
    Button(action: markPendingAction) {
      HStack(spacing: 7) {
        Image(systemName: systemImage)
          .font(.system(size: 14, weight: .semibold))
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.78)
      }
      .foregroundColor(enabled ? .signalASITextPrimary : .signalASITextSecondary)
      .frame(maxWidth: .infinity, minHeight: 42)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .opacity(enabled ? 1 : 0.58)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }

  private func markPendingAction() {
    statusMessage = t("desktop_control_request_sent", "Encrypted request sent")
  }
}

private struct SignalASIDesktopControlHero: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct SignalASIDesktopControlActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var enabled: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      SignalASIDesktopControlRow(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: false,
        enabled: enabled
      )
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}

private struct SignalASIDesktopControlRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool
  var enabled: Bool = true

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(enabled ? 0.16 : 0.08))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(enabled ? tint : .signalASITextSecondary)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(enabled ? .signalASITextPrimary : .signalASITextSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Text(badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(enabled ? tint : .signalASITextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(enabled ? 0.12 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .opacity(enabled ? 1 : 0.62)
  }
}
