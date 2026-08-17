import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct SignalASIAppAdaptersView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var notificationsAuthorized = false
  @State private var snapshot = SignalASIAppAdapterSnapshot.empty
  @State private var statusMessage = ""

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("agent_app_adapters_title", "Specialized App Adapters"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("agent_app_adapters_hero_title", "App-specific Execution"),
            subtitle: t(
              "agent_app_adapters_hero_subtitle",
              "Each adapter uses verified iOS handoffs, UI grounding, and explicit confirmation at external side effects"
            ),
            systemImage: "rectangle.3.group",
            tint: .signalASIAccent,
            badge: String(format: t("agent_app_adapters_count", "%d adapters"), snapshot.operationalCount)
          )

          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.app_adapters.status", "Adapter Status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
            )
          }

          overviewSection
          adaptersSection
          boundariesSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
    .onChange(of: store.agentSafetySettings.screenObservationAllowed) { _ in
      refresh()
    }
  }

  private var overviewSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.app_adapters.section_overview", "Overview"))
      SignalASISecurityStatusRow(
        title: t("signalasi.app_adapters.operational", "Operational Adapters"),
        subtitle: t(
          "agent_app_adapters_subtitle",
          "Grounded workflows for communication, browser, and document apps"
        ),
        systemImage: "checkmark.seal",
        tint: .signalASIAccent,
        badge: "\(snapshot.operationalCount)/\(snapshot.statuses.count)"
      )
      SignalASISecurityNavigationRow(
        title: t("signalasi.on_device_agent.title", "On-device Agent Permissions"),
        subtitle: t(
          "signalasi.app_adapters.permissions_subtitle",
          "Screen understanding and notification prompts affect app-adapter readiness"
        ),
        systemImage: "shield",
        tint: .blue,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        OnDeviceAgentPermissionsView()
      }
    }
  }

  private var adaptersSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("agent_app_adapters_section", "Available Adapters"))
      ForEach(snapshot.statuses) { status in
        SignalASISecurityNavigationRow(
          title: adapterTitle(status.definition),
          subtitle: adapterSubtitle(status),
          systemImage: status.definition.systemImage,
          tint: availabilityTint(status.availability, fallback: adapterTint(status.definition.tone)),
          badge: appAdapterAvailabilityLabel(status.availability, language: interfaceLanguage)
        ) {
          SignalASIAppAdapterDetailView(status: status)
        }
      }
    }
  }

  private var boundariesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.app_adapters.section_boundaries", "Execution Boundaries"))
      SignalASISecurityNavigationRow(
        title: t("signalasi.native_tool_catalog.title", "Native Tools"),
        subtitle: t(
          "signalasi.native_tool_catalog.hero_subtitle",
          "Review iOS tool availability, risk, runtime scope, permissions, and consent boundaries"
        ),
        systemImage: "wrench.and.screwdriver",
        tint: .blue,
        badge: String(format: t("signalasi.native_tool_catalog.badge", "%d tools"), AgentPhoneNativeToolCatalog.descriptors().count)
      ) {
        SignalASINativeToolCatalogView()
      }
      SignalASISecurityStatusRow(
        title: t("signalasi.app_adapters.ios_boundary", "iOS Cross-app Boundary"),
        subtitle: t(
          "signalasi.app_adapters.ios_boundary_subtitle",
          "Adapters use URL handoffs, document pickers, foreground capture, and user-visible confirmations instead of silent cross-app control"
        ),
        systemImage: "lock.shield",
        tint: .orange,
        badge: t("signalasi.app_adapters.status_limited", "Limited")
      )
    }
  }

  private func refresh() {
    snapshot = SignalASIAppAdapterCatalog.snapshot(
      screenObservationAllowed: store.agentSafetySettings.screenObservationAllowed,
      notificationsAuthorized: notificationsAuthorized
    )
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let granted: Bool
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        granted = true
      case .notDetermined, .denied:
        granted = false
      @unknown default:
        granted = false
      }
      DispatchQueue.main.async {
        notificationsAuthorized = granted
        snapshot = SignalASIAppAdapterCatalog.snapshot(
          screenObservationAllowed: store.agentSafetySettings.screenObservationAllowed,
          notificationsAuthorized: granted
        )
        statusMessage = String(
          format: t("signalasi.app_adapters.summary", "%d operational / %d need setup"),
          snapshot.operationalCount,
          snapshot.needsSetupCount
        )
      }
    }
  }

  private func adapterTitle(_ definition: SignalASIAppAdapterDefinition) -> String {
    t(definition.titleKey, definition.titleFallback)
  }

  private func adapterSubtitle(_ status: SignalASIAppAdapterStatus) -> String {
    if status.definition.id == .wechat {
      let screen = store.agentSafetySettings.screenObservationAllowed
        ? t("signalasi.common.on", "On")
        : t("signalasi.common.off", "Off")
      let notifications = notificationsAuthorized
        ? t("signalasi.common.on", "On")
        : t("signalasi.common.off", "Off")
      return String(
        format: t(status.definition.subtitleKey, status.definition.subtitleFallback),
        screen,
        notifications
      )
    }
    return t(status.definition.subtitleKey, status.definition.subtitleFallback)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIAppAdapterDetailView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var statusMessage = ""
  @State private var fileImporterPresented = false
  var status: SignalASIAppAdapterStatus

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: adapterTitle(status.definition),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: adapterTitle(status.definition),
            subtitle: t(status.definition.detailKey, status.definition.detailFallback),
            systemImage: status.definition.systemImage,
            tint: adapterTint(status.definition.tone),
            badge: appAdapterAvailabilityLabel(status.availability, language: interfaceLanguage)
          )

          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.app_adapters.action_result", "Action Result"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
            )
          }

          actionSection
          readinessSection
          capabilitySection
          policySection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileImporter(
      isPresented: $fileImporterPresented,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        statusMessage = String(
          format: t("signalasi.app_adapters.files_selected", "Selected %d file handoff(s)"),
          urls.count
        )
      case .failure(let error):
        statusMessage = String(format: t("signalasi.app_adapters.files_failed", "File handoff failed: %@"), error.localizedDescription)
      }
    }
  }

  private var actionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.section.actions", "Actions"))
      if status.definition.id == .files {
        SignalASISecurityPrimaryButton(
          title: t("signalasi.app_adapters.select_files", "Select Files"),
          systemImage: "folder.badge.plus",
          tint: adapterTint(status.definition.tone)
        ) {
          fileImporterPresented = true
        }
      } else if let url = status.launchURL, status.availability != .unavailable {
        SignalASISecurityPrimaryButton(
          title: t("signalasi.app_adapters.open_handoff", "Open Handoff"),
          systemImage: "arrow.up.forward.app",
          tint: adapterTint(status.definition.tone)
        ) {
          open(url)
        }
      } else {
        SignalASISecurityPrimaryButton(
          title: t("signalasi.app_adapters.open_settings", "Open Settings"),
          systemImage: "gearshape",
          tint: .orange
        ) {
          openSettings()
        }
      }
    }
  }

  private var readinessSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.app_adapters.section_readiness", "Readiness"))
      SignalASISecurityStatusRow(
        title: t("signalasi.app_adapters.current_route", "Current Route"),
        subtitle: routeLabel(status.definition),
        systemImage: "arrow.triangle.turn.up.right.diamond",
        tint: adapterTint(status.definition.tone),
        badge: appAdapterAvailabilityLabel(status.availability, language: interfaceLanguage)
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.app_adapters.evidence", "Evidence"),
        subtitle: t(status.evidenceKey, status.evidenceFallback),
        systemImage: "checklist",
        tint: availabilityTint(status.availability, fallback: adapterTint(status.definition.tone)),
        badge: appAdapterAvailabilityLabel(status.availability, language: interfaceLanguage)
      )
      ForEach(status.checks) { check in
        SignalASISecurityStatusRow(
          title: t(check.titleKey, check.titleFallback),
          subtitle: t(check.detailKey, check.detailFallback),
          systemImage: availabilitySystemImage(check.availability),
          tint: availabilityTint(check.availability, fallback: adapterTint(status.definition.tone)),
          badge: appAdapterAvailabilityLabel(check.availability, language: interfaceLanguage)
        )
      }
    }
  }

  private var capabilitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.on_device_agent.section_capabilities", "Capability Access"))
      ForEach(status.definition.capabilityIds, id: \.self) { capabilityId in
        let boundary = AgentPhoneCapabilityCatalog.find(capabilityId)
        SignalASISecurityStatusRow(
          title: capabilityLabel(capabilityId),
          subtitle: capabilityDetail(capabilityId, fallback: boundary.limitation),
          systemImage: capabilityIcon(capabilityId),
          tint: capabilityTint(boundary.availability),
          badge: capabilityAvailabilityLabel(boundary.availability, language: interfaceLanguage)
        )
      }
    }
  }

  private var policySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.app_adapters.section_policy", "Policy"))
      SignalASISecurityStatusRow(
        title: t("signalasi.app_adapters.confirmation_policy", "Confirmation Policy"),
        subtitle: t(
          "signalasi.app_adapters.confirmation_policy_subtitle",
          "External side effects stay behind visible iOS UI or SignalASI confirmation before execution"
        ),
        systemImage: "hand.raised",
        tint: .orange,
        badge: t("signalasi.app_adapters.owner_controlled", "Owner")
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.app_adapters.data_boundary", "Data Boundary"),
        subtitle: t(
          "signalasi.app_adapters.data_boundary_subtitle",
          "Adapter observations are bounded to selected files, opened URLs, SignalASI-owned notifications, or explicit screen capture"
        ),
        systemImage: "lock.doc",
        tint: .blue,
        badge: riskLabel(.high, language: interfaceLanguage)
      )
    }
  }

  private func adapterTitle(_ definition: SignalASIAppAdapterDefinition) -> String {
    t(definition.titleKey, definition.titleFallback)
  }

  private func routeLabel(_ definition: SignalASIAppAdapterDefinition) -> String {
    switch definition.id {
    case .wechat:
      return t("signalasi.app_adapters.route_wechat", definition.routeFallback)
    case .sms:
      return t("signalasi.app_adapters.route_sms", definition.routeFallback)
    case .phone:
      return t("signalasi.app_adapters.route_phone", definition.routeFallback)
    case .browser:
      return t("signalasi.app_adapters.route_browser", definition.routeFallback)
    case .files:
      return t("signalasi.app_adapters.route_files", definition.routeFallback)
    }
  }

  private func open(_ url: URL) {
    UIApplication.shared.open(url, options: [:]) { success in
      DispatchQueue.main.async {
        statusMessage = success
          ? t("signalasi.app_adapters.handoff_opened", "Handoff opened")
          : t("signalasi.app_adapters.handoff_failed", "Handoff could not be opened")
      }
    }
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    open(url)
  }

  private func capabilityDetail(_ id: AgentPhoneCapabilityId, fallback: String) -> String {
    switch id {
    case .mediaProjectionOCR:
      return t("signalasi.capability.screen_capture_detail", fallback)
    case .notificationRead:
      return t("signalasi.capability.notification_read_detail", fallback)
    case .notificationReply:
      return t("signalasi.capability.notification_reply_detail", fallback)
    case .clipboard:
      return t("signalasi.capability.clipboard_detail", fallback)
    case .network:
      return t("signalasi.capability.network_detail", fallback)
    case .installedApps:
      return t("signalasi.capability.installed_apps_detail", fallback)
    case .intentLaunch:
      return t("signalasi.capability.intent_launch_detail", fallback)
    default:
      return fallback
    }
  }

  private func capabilityLabel(_ id: AgentPhoneCapabilityId) -> String {
    switch id {
    case .accessibilityUITree: return t("signalasi.capability.accessibility_tree", "Accessibility UI Tree")
    case .accessibilityGestures: return t("signalasi.capability.accessibility_gestures", "Accessibility Gestures")
    case .ownedAgentInput: return t("signalasi.capability.owned_agent_input", "Agent Composer Input")
    case .ownedAgentTranscript: return t("signalasi.capability.owned_agent_transcript", "Agent Transcript Navigation")
    case .ownedAgentControls: return t("signalasi.capability.owned_agent_controls", "Agent Home Controls")
    case .ownedAgentLongPress: return t("signalasi.capability.owned_agent_long_press", "Agent Home Long Press")
    case .ownedAgentNavigation: return t("signalasi.capability.owned_agent_navigation", "Agent Home Navigation")
    case .mediaProjectionOCR: return t("signalasi.capability.screen_capture", "Screen Capture OCR")
    case .notificationRead: return t("signalasi.capability.notification_read", "Notification Read")
    case .notificationReply: return t("signalasi.capability.notification_reply", "Notification Reply")
    case .clipboard: return t("signalasi.capability.clipboard", "Clipboard")
    case .camera: return t("signalasi.capability.camera", "Camera")
    case .microphone: return t("signalasi.capability.microphone", "Microphone")
    case .location: return t("signalasi.capability.location", "Location")
    case .sensors: return t("signalasi.capability.sensors", "Sensors")
    case .bluetooth: return t("signalasi.capability.bluetooth", "Bluetooth")
    case .nfc: return t("signalasi.capability.nfc", "NFC")
    case .battery: return t("signalasi.capability.battery", "Battery")
    case .deviceMemory: return t("signalasi.capability.device_memory", "Device Memory")
    case .network: return t("signalasi.capability.network", "Network")
    case .installedApps: return t("signalasi.capability.installed_apps", "Installed Apps")
    case .intentLaunch: return t("signalasi.capability.intent_launch", "App Handoff")
    case .systemSettings: return t("signalasi.capability.system_settings", "System Settings")
    case .packageInstallHandoff: return t("signalasi.capability.package_install", "Package Install")
    case .deviceOwner: return t("signalasi.capability.device_owner", "Device Owner")
    case .shizuku: return t("signalasi.capability.shizuku", "Shizuku")
    case .root: return t("signalasi.capability.root", "Root")
    case .homeAssistant: return t("signalasi.capability.home_assistant", "Home Assistant")
    case .mediaPlayback: return t("signalasi.capability.media_playback", "Media Playback")
    case .mediaTranscode: return t("signalasi.capability.media_transcode", "Media Transcode")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private func appAdapterAvailabilityLabel(_ availability: SignalASIAppAdapterAvailability, language: String) -> String {
  SignalASILocalization.string(availabilityKey(availability), fallback: availabilityFallback(availability), language: language)
}

private func availabilityKey(_ availability: SignalASIAppAdapterAvailability) -> String {
  switch availability {
  case .ready: return "signalasi.app_adapters.status_ready"
  case .limited: return "signalasi.app_adapters.status_limited"
  case .needsSetup: return "signalasi.permission.needs_setup"
  case .unavailable: return "signalasi.native_tool_catalog.status_unavailable"
  }
}

private func availabilityFallback(_ availability: SignalASIAppAdapterAvailability) -> String {
  switch availability {
  case .ready: return "Ready"
  case .limited: return "Limited"
  case .needsSetup: return "Needs setup"
  case .unavailable: return "Unavailable"
  }
}

private func adapterTint(_ tone: SignalASIAppAdapterTone) -> Color {
  switch tone {
  case .accent: return .signalASIAccent
  case .blue: return .blue
  case .teal: return .teal
  case .orange: return .orange
  case .purple: return .purple
  case .gray: return .signalASITextSecondary
  }
}

private func availabilityTint(_ availability: SignalASIAppAdapterAvailability, fallback: Color) -> Color {
  switch availability {
  case .ready: return fallback
  case .limited, .needsSetup: return .orange
  case .unavailable: return .signalASITextSecondary
  }
}

private func availabilitySystemImage(_ availability: SignalASIAppAdapterAvailability) -> String {
  switch availability {
  case .ready: return "checkmark.circle"
  case .limited: return "exclamationmark.circle"
  case .needsSetup: return "slider.horizontal.3"
  case .unavailable: return "xmark.circle"
  }
}

private func capabilityIcon(_ id: AgentPhoneCapabilityId) -> String {
  switch id {
  case .accessibilityUITree, .accessibilityGestures, .mediaProjectionOCR:
    return "text.viewfinder"
  case .ownedAgentInput:
    return "keyboard"
  case .ownedAgentTranscript:
    return "arrow.up.and.down.text.horizontal"
  case .ownedAgentControls:
    return "hand.tap"
  case .ownedAgentLongPress:
    return "hand.tap.fill"
  case .ownedAgentNavigation:
    return "arrow.left"
  case .notificationRead, .notificationReply:
    return "bell.badge"
  case .clipboard:
    return "doc.on.clipboard"
  case .camera:
    return "camera"
  case .microphone:
    return "mic"
  case .location:
    return "location"
  case .sensors:
    return "sensor.tag.radiowaves.forward"
  case .bluetooth:
    return "antenna.radiowaves.left.and.right"
  case .nfc:
    return "wave.3.right"
  case .battery:
    return "battery.75"
  case .deviceMemory:
    return "cpu"
  case .network:
    return "network"
  case .installedApps:
    return "square.grid.2x2"
  case .intentLaunch, .systemSettings, .packageInstallHandoff:
    return "arrow.up.forward.app"
  case .deviceOwner, .shizuku, .root:
    return "lock.shield"
  case .homeAssistant:
    return "house"
  case .mediaPlayback:
    return "play.circle"
  case .mediaTranscode:
    return "film"
  }
}

private func capabilityTint(_ availability: AgentPhoneCapabilityAvailability) -> Color {
  switch availability {
  case .ready:
    return .signalASIAccent
  case .limited, .needsRuntimePermission, .needsSpecialAccess, .needsUserConsent, .needsConfiguration:
    return .orange
  case .notImplemented, .privilegedOnly, .unsupported, .blockedByPolicy, .unknown:
    return .signalASITextSecondary
  }
}

private func capabilityAvailabilityLabel(_ availability: AgentPhoneCapabilityAvailability, language: String) -> String {
  switch availability {
  case .ready:
    return SignalASILocalization.string("signalasi.app_adapters.status_ready", fallback: "Ready", language: language)
  case .limited:
    return SignalASILocalization.string("signalasi.app_adapters.status_limited", fallback: "Limited", language: language)
  case .needsRuntimePermission, .needsSpecialAccess, .needsUserConsent, .needsConfiguration:
    return SignalASILocalization.string("signalasi.permission.needs_setup", fallback: "Needs setup", language: language)
  case .notImplemented:
    return SignalASILocalization.string("signalasi.app_adapters.status_not_implemented", fallback: "Not implemented", language: language)
  case .privilegedOnly:
    return SignalASILocalization.string("signalasi.app_adapters.status_privileged", fallback: "Privileged", language: language)
  case .unsupported:
    return SignalASILocalization.string("signalasi.app_adapters.status_unsupported", fallback: "Unsupported", language: language)
  case .blockedByPolicy:
    return SignalASILocalization.string("signalasi.app_adapters.status_blocked", fallback: "Blocked", language: language)
  case .unknown:
    return SignalASILocalization.string("signalasi.status.unknown", fallback: "Unknown", language: language)
  }
}

private func riskLabel(_ risk: AgentRisk, language: String) -> String {
  switch risk {
  case .low: return SignalASILocalization.string("signalasi.native_tool_catalog.risk_low", fallback: "Low", language: language)
  case .medium: return SignalASILocalization.string("signalasi.native_tool_catalog.risk_medium", fallback: "Medium", language: language)
  case .high: return SignalASILocalization.string("signalasi.native_tool_catalog.risk_high", fallback: "High", language: language)
  case .blocked: return SignalASILocalization.string("signalasi.native_tool_catalog.risk_blocked", fallback: "Blocked", language: language)
  }
}
