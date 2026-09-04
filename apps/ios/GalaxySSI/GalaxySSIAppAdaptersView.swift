import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

struct GalaxySSIAppAdaptersView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var notificationsAuthorized = false
  @State private var snapshot = GalaxySSIAppAdapterSnapshot.empty
  @State private var statusMessage = ""

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("agent_app_adapters_title", "Specialized App Adapters"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("agent_app_adapters_hero_title", "App-specific Execution"),
            subtitle: t(
              "agent_app_adapters_hero_subtitle",
              "Each adapter uses verified iOS handoffs, UI grounding, and explicit confirmation at external side effects"
            ),
            systemImage: "rectangle.3.group",
            tint: .galaxySSIAccent,
            badge: String(format: t("agent_app_adapters_count", "%d adapters"), snapshot.operationalCount)
          )

          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("galaxyssi.app_adapters.status", "Adapter Status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.ready", "Ready")
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
    .onChange(of: store.agentSafetySettings.screenObservationAllowed) { _ in
      refresh()
    }
  }

  private var overviewSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.app_adapters.section_overview", "Overview"))
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.app_adapters.operational", "Operational Adapters"),
        subtitle: t(
          "agent_app_adapters_subtitle",
          "Grounded workflows for communication, browser, and document apps"
        ),
        systemImage: "checkmark.seal",
        tint: .galaxySSIAccent,
        badge: "\(snapshot.operationalCount)/\(snapshot.statuses.count)"
      )
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.on_device_agent.title", "On-device Agent Permissions"),
        subtitle: t(
          "galaxyssi.app_adapters.permissions_subtitle",
          "Screen understanding and notification prompts affect app-adapter readiness"
        ),
        systemImage: "shield",
        tint: .blue,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        OnDeviceAgentPermissionsView()
      }
    }
  }

  private var adaptersSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_app_adapters_section", "Available Adapters"))
      ForEach(snapshot.statuses) { status in
        GalaxySSISecurityNavigationRow(
          title: adapterTitle(status.definition),
          subtitle: adapterSubtitle(status),
          systemImage: status.definition.systemImage,
          tint: availabilityTint(status.availability, fallback: adapterTint(status.definition.tone)),
          badge: appAdapterAvailabilityLabel(status.availability, language: interfaceLanguage)
        ) {
          GalaxySSIAppAdapterDetailView(status: status)
        }
      }
    }
  }

  private var boundariesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.app_adapters.section_boundaries", "Execution Boundaries"))
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.native_tool_catalog.title", "Native Tools"),
        subtitle: t(
          "galaxyssi.native_tool_catalog.hero_subtitle",
          "Review iOS tool availability, risk, runtime scope, permissions, and consent boundaries"
        ),
        systemImage: "wrench.and.screwdriver",
        tint: .blue,
        badge: String(format: t("galaxyssi.native_tool_catalog.badge", "%d tools"), AgentPhoneNativeToolCatalog.descriptors().count)
      ) {
        GalaxySSINativeToolCatalogView()
      }
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.app_adapters.ios_boundary", "iOS Cross-app Boundary"),
        subtitle: t(
          "galaxyssi.app_adapters.ios_boundary_subtitle",
          "Adapters use URL handoffs, document pickers, foreground capture, and user-visible confirmations instead of silent cross-app control"
        ),
        systemImage: "lock.shield",
        tint: .orange,
        badge: t("galaxyssi.app_adapters.status_limited", "Limited")
      )
    }
  }

  private func refresh() {
    snapshot = GalaxySSIAppAdapterCatalog.snapshot(
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
        snapshot = GalaxySSIAppAdapterCatalog.snapshot(
          screenObservationAllowed: store.agentSafetySettings.screenObservationAllowed,
          notificationsAuthorized: granted
        )
        statusMessage = String(
          format: t("galaxyssi.app_adapters.summary", "%d operational / %d need setup"),
          snapshot.operationalCount,
          snapshot.needsSetupCount
        )
      }
    }
  }

  private func adapterTitle(_ definition: GalaxySSIAppAdapterDefinition) -> String {
    t(definition.titleKey, definition.titleFallback)
  }

  private func adapterSubtitle(_ status: GalaxySSIAppAdapterStatus) -> String {
    if status.definition.id == .wechat {
      let screen = store.agentSafetySettings.screenObservationAllowed
        ? t("galaxyssi.common.on", "On")
        : t("galaxyssi.common.off", "Off")
      let notifications = notificationsAuthorized
        ? t("galaxyssi.common.on", "On")
        : t("galaxyssi.common.off", "Off")
      return String(
        format: t(status.definition.subtitleKey, status.definition.subtitleFallback),
        screen,
        notifications
      )
    }
    return t(status.definition.subtitleKey, status.definition.subtitleFallback)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIAppAdapterDetailView: View {
  private enum BrowserHandoffMode: String, CaseIterable, Identifiable {
    case url
    case search

    var id: String { rawValue }
  }

  private enum FileHandoffMode: String, CaseIterable, Identifiable {
    case files
    case images
    case pdf

    var id: String { rawValue }

    var contentTypes: [UTType] {
      switch self {
      case .files:
        return [.item]
      case .images:
        return [.image]
      case .pdf:
        return [.pdf]
      }
    }
  }

  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var statusMessage = ""
  @State private var fileImporterPresented = false
  @State private var smsRecipient = ""
  @State private var smsBody = ""
  @State private var phoneNumber = ""
  @State private var wechatContact = ""
  @State private var wechatDraft = ""
  @State private var browserHandoffMode: BrowserHandoffMode = .url
  @State private var browserInput = ""
  @State private var fileHandoffMode: FileHandoffMode = .files
  var status: GalaxySSIAppAdapterStatus

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: adapterTitle(status.definition),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: adapterTitle(status.definition),
            subtitle: t(status.definition.detailKey, status.definition.detailFallback),
            systemImage: status.definition.systemImage,
            tint: adapterTint(status.definition.tone),
            badge: appAdapterAvailabilityLabel(status.availability, language: interfaceLanguage)
          )

          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("galaxyssi.app_adapters.action_result", "Action Result"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.ready", "Ready")
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .fileImporter(
      isPresented: $fileImporterPresented,
      allowedContentTypes: fileHandoffMode.contentTypes,
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        statusMessage = String(
          format: t("galaxyssi.app_adapters.files_selected", "Selected %d file handoff(s)"),
          urls.count
        )
      case .failure(let error):
        statusMessage = String(format: t("galaxyssi.app_adapters.files_failed", "File handoff failed: %@"), error.localizedDescription)
      }
    }
  }

  private var actionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.section.actions", "Actions"))
      if status.definition.id == .wechat {
        wechatDraftAction
      } else if status.definition.id == .sms {
        smsComposeAction
      } else if status.definition.id == .phone {
        phoneDialAction
      } else if status.definition.id == .browser {
        browserHandoffAction
      } else if status.definition.id == .files {
        filePickerAction
      } else if let url = status.launchURL, status.availability != .unavailable {
        GalaxySSISecurityPrimaryButton(
          title: t("galaxyssi.app_adapters.open_handoff", "Open Handoff"),
          systemImage: "arrow.up.forward.app",
          tint: adapterTint(status.definition.tone)
        ) {
          open(url)
        }
      } else {
        GalaxySSISecurityPrimaryButton(
          title: t("galaxyssi.app_adapters.open_settings", "Open Settings"),
          systemImage: "gearshape",
          tint: .orange
        ) {
          openSettings()
        }
      }
    }
  }

  private var wechatDraftAction: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField(t("galaxyssi.app_adapters.wechat_recipient", "WeChat Contact"), text: $wechatContact)
        .textContentType(.name)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled(true)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      TextEditor(text: $wechatDraft)
        .font(.system(size: 15))
        .frame(minHeight: 88, maxHeight: 120)
        .padding(8)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(t("galaxyssi.app_adapters.wechat_message", "Message"))
      GalaxySSISecurityPrimaryButton(
        title: t("galaxyssi.app_adapters.open_wechat_draft", "Copy Draft and Open WeChat"),
        systemImage: "doc.on.clipboard",
        tint: adapterTint(status.definition.tone)
      ) {
        openWeChatDraft()
      }
    }
  }

  private var smsComposeAction: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField(t("galaxyssi.app_adapters.sms_recipient", "Recipient"), text: $smsRecipient)
        .keyboardType(.phonePad)
        .textContentType(.telephoneNumber)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      TextEditor(text: $smsBody)
        .font(.system(size: 15))
        .frame(minHeight: 88, maxHeight: 120)
        .padding(8)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(t("galaxyssi.app_adapters.sms_body", "Message"))
      GalaxySSISecurityPrimaryButton(
        title: t("galaxyssi.app_adapters.open_sms_composer", "Open Message Composer"),
        systemImage: "message",
        tint: adapterTint(status.definition.tone)
      ) {
        guard AgentIOSNativeToolHandoffPresenter.openSMSCompose(
          phoneNumber: smsRecipient,
          body: smsBody
        ) else {
          statusMessage = t("galaxyssi.app_adapters.sms_invalid_recipient", "Enter a valid recipient phone number")
          return
        }
        statusMessage = t("galaxyssi.app_adapters.sms_composer_opened", "Message composer opened for your review")
      }
    }
  }

  private var phoneDialAction: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField(t("galaxyssi.app_adapters.phone_number", "Phone Number"), text: $phoneNumber)
        .keyboardType(.phonePad)
        .textContentType(.telephoneNumber)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      GalaxySSISecurityPrimaryButton(
        title: t("galaxyssi.app_adapters.open_dialer", "Open Dialer"),
        systemImage: "phone",
        tint: adapterTint(status.definition.tone)
      ) {
        guard AgentIOSNativeToolHandoffPresenter.openDialer(phoneNumber: phoneNumber) else {
          statusMessage = t("galaxyssi.app_adapters.phone_invalid_number", "Enter a valid phone number")
          return
        }
        statusMessage = t("galaxyssi.app_adapters.dialer_opened", "Dialer opened for your confirmation")
      }
    }
  }

  private var browserHandoffAction: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker(
        t("galaxyssi.app_adapters.browser_mode", "Browser Mode"),
        selection: $browserHandoffMode
      ) {
        Text(t("galaxyssi.app_adapters.browser_open_url", "Open URL")).tag(BrowserHandoffMode.url)
        Text(t("galaxyssi.app_adapters.browser_search", "Search Web")).tag(BrowserHandoffMode.search)
      }
      .pickerStyle(.segmented)
      TextField(browserPlaceholder, text: $browserInput)
        .keyboardType(browserHandoffMode == .url ? .URL : .webSearch)
        .textContentType(browserHandoffMode == .url ? .URL : nil)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      GalaxySSISecurityPrimaryButton(
        title: browserActionTitle,
        systemImage: browserHandoffMode == .url ? "safari" : "magnifyingglass",
        tint: adapterTint(status.definition.tone)
      ) {
        openBrowserHandoff()
      }
    }
  }

  private var filePickerAction: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker(
        t("galaxyssi.app_adapters.file_type", "File Type"),
        selection: $fileHandoffMode
      ) {
        Text(t("galaxyssi.app_adapters.file_type_all", "Files")).tag(FileHandoffMode.files)
        Text(t("galaxyssi.app_adapters.file_type_images", "Images")).tag(FileHandoffMode.images)
        Text(t("galaxyssi.app_adapters.file_type_pdf", "PDF")).tag(FileHandoffMode.pdf)
      }
      .pickerStyle(.segmented)
      GalaxySSISecurityPrimaryButton(
        title: filePickerTitle,
        systemImage: filePickerIcon,
        tint: adapterTint(status.definition.tone)
      ) {
        fileImporterPresented = true
      }
    }
  }

  private var browserPlaceholder: String {
    switch browserHandoffMode {
    case .url:
      return t("galaxyssi.app_adapters.browser_url_placeholder", "example.com or https://example.com")
    case .search:
      return t("galaxyssi.app_adapters.browser_search_placeholder", "Search the web")
    }
  }

  private var browserActionTitle: String {
    switch browserHandoffMode {
    case .url:
      return t("galaxyssi.app_adapters.browser_open", "Open Browser")
    case .search:
      return t("galaxyssi.app_adapters.browser_search_action", "Search in Browser")
    }
  }

  private var filePickerTitle: String {
    switch fileHandoffMode {
    case .files:
      return t("galaxyssi.app_adapters.select_files", "Select Files")
    case .images:
      return t("galaxyssi.app_adapters.select_images", "Select Images")
    case .pdf:
      return t("galaxyssi.app_adapters.select_pdf", "Select PDF")
    }
  }

  private var filePickerIcon: String {
    switch fileHandoffMode {
    case .files:
      return "folder.badge.plus"
    case .images:
      return "photo.badge.plus"
    case .pdf:
      return "doc.badge.plus"
    }
  }
  private var readinessSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.app_adapters.section_readiness", "Readiness"))
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.app_adapters.current_route", "Current Route"),
        subtitle: routeLabel(status.definition),
        systemImage: "arrow.triangle.turn.up.right.diamond",
        tint: adapterTint(status.definition.tone),
        badge: appAdapterAvailabilityLabel(status.availability, language: interfaceLanguage)
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.app_adapters.evidence", "Evidence"),
        subtitle: t(status.evidenceKey, status.evidenceFallback),
        systemImage: "checklist",
        tint: availabilityTint(status.availability, fallback: adapterTint(status.definition.tone)),
        badge: appAdapterAvailabilityLabel(status.availability, language: interfaceLanguage)
      )
      ForEach(status.checks) { check in
        GalaxySSISecurityStatusRow(
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
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.on_device_agent.section_capabilities", "Capability Access"))
      ForEach(status.definition.capabilityIds, id: \.self) { capabilityId in
        let boundary = AgentPhoneCapabilityCatalog.find(capabilityId)
        GalaxySSISecurityStatusRow(
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
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.app_adapters.section_policy", "Policy"))
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.app_adapters.confirmation_policy", "Confirmation Policy"),
        subtitle: t(
          "galaxyssi.app_adapters.confirmation_policy_subtitle",
          "External side effects stay behind visible iOS UI or GalaxySSI confirmation before execution"
        ),
        systemImage: "hand.raised",
        tint: .orange,
        badge: t("galaxyssi.app_adapters.owner_controlled", "Owner")
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.app_adapters.data_boundary", "Data Boundary"),
        subtitle: t(
          "galaxyssi.app_adapters.data_boundary_subtitle",
          "Adapter observations are bounded to selected files, opened URLs, GalaxySSI-owned notifications, or explicit screen capture"
        ),
        systemImage: "lock.doc",
        tint: .blue,
        badge: riskLabel(.high, language: interfaceLanguage)
      )
    }
  }

  private func adapterTitle(_ definition: GalaxySSIAppAdapterDefinition) -> String {
    t(definition.titleKey, definition.titleFallback)
  }

  private func routeLabel(_ definition: GalaxySSIAppAdapterDefinition) -> String {
    switch definition.id {
    case .wechat:
      return t("galaxyssi.app_adapters.route_wechat", definition.routeFallback)
    case .sms:
      return t("galaxyssi.app_adapters.route_sms", definition.routeFallback)
    case .phone:
      return t("galaxyssi.app_adapters.route_phone", definition.routeFallback)
    case .browser:
      return t("galaxyssi.app_adapters.route_browser", definition.routeFallback)
    case .files:
      return t("galaxyssi.app_adapters.route_files", definition.routeFallback)
    }
  }

  private func open(_ url: URL) {
    UIApplication.shared.open(url, options: [:]) { success in
      DispatchQueue.main.async {
        statusMessage = success
          ? t("galaxyssi.app_adapters.handoff_opened", "Handoff opened")
          : t("galaxyssi.app_adapters.handoff_failed", "Handoff could not be opened")
      }
    }
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    open(url)
  }

  private func openWeChatDraft() {
    let contact = String(wechatContact.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    guard !contact.isEmpty else {
      statusMessage = t("galaxyssi.app_adapters.wechat_invalid_recipient", "Enter a WeChat contact")
      return
    }
    let draft = String(wechatDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
    guard !draft.isEmpty else {
      statusMessage = t("galaxyssi.app_adapters.wechat_invalid_draft", "Enter a message draft")
      return
    }
    UIPasteboard.general.string = draft
    guard let url = status.launchURL else {
      statusMessage = t("galaxyssi.app_adapters.wechat_draft_copied", "Draft copied. Select the contact in WeChat and paste to send.")
      return
    }
    UIApplication.shared.open(url, options: [:]) { success in
      DispatchQueue.main.async {
        statusMessage = success
          ? String(
            format: t(
              "galaxyssi.app_adapters.wechat_draft_opened",
              "Draft copied for %@. Choose the contact in WeChat and paste to send."
            ),
            contact
          )
          : t("galaxyssi.app_adapters.wechat_draft_copied", "Draft copied. Select the contact in WeChat and paste to send.")
      }
    }
  }

  private func openBrowserHandoff() {
    let url: URL?
    switch browserHandoffMode {
    case .url:
      url = normalizedBrowserURL(browserInput)
    case .search:
      url = browserSearchURL(browserInput)
    }
    guard let url else {
      statusMessage = browserHandoffMode == .url
        ? t("galaxyssi.app_adapters.browser_invalid_url", "Enter a valid HTTP or HTTPS URL")
        : t("galaxyssi.app_adapters.browser_empty_search", "Enter a search query")
      return
    }
    open(url)
  }

  private func normalizedBrowserURL(_ rawValue: String) -> URL? {
    let value = String(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_048))
    guard !value.isEmpty else { return nil }
    let candidate = value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://")
      ? value
      : "https://\(value)"
    guard let url = URL(string: candidate),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          let host = url.host,
          !host.isEmpty else {
      return nil
    }
    return url
  }

  private func browserSearchURL(_ rawValue: String) -> URL? {
    let query = String(rawValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
    guard !query.isEmpty else { return nil }
    var components = URLComponents(string: "https://www.google.com/search")
    components?.queryItems = [URLQueryItem(name: "q", value: query)]
    return components?.url
  }

  private func capabilityDetail(_ id: AgentPhoneCapabilityId, fallback: String) -> String {
    switch id {
    case .mediaProjectionOCR:
      return t("galaxyssi.capability.screen_capture_detail", fallback)
    case .notificationRead:
      return t("galaxyssi.capability.notification_read_detail", fallback)
    case .notificationReply:
      return t("galaxyssi.capability.notification_reply_detail", fallback)
    case .clipboard:
      return t("galaxyssi.capability.clipboard_detail", fallback)
    case .network:
      return t("galaxyssi.capability.network_detail", fallback)
    case .installedApps:
      return t("galaxyssi.capability.installed_apps_detail", fallback)
    case .intentLaunch:
      return t("galaxyssi.capability.intent_launch_detail", fallback)
    default:
      return fallback
    }
  }

  private func capabilityLabel(_ id: AgentPhoneCapabilityId) -> String {
    switch id {
    case .accessibilityUITree: return t("galaxyssi.capability.accessibility_tree", "Accessibility UI Tree")
    case .accessibilityGestures: return t("galaxyssi.capability.accessibility_gestures", "Accessibility Gestures")
    case .ownedAgentInput: return t("galaxyssi.capability.owned_agent_input", "Agent Composer Input")
    case .ownedAgentTranscript: return t("galaxyssi.capability.owned_agent_transcript", "Agent Transcript Navigation")
    case .ownedAgentControls: return t("galaxyssi.capability.owned_agent_controls", "Agent Home Controls")
    case .ownedAgentLongPress: return t("galaxyssi.capability.owned_agent_long_press", "Agent Home Long Press")
    case .ownedAgentNavigation: return t("galaxyssi.capability.owned_agent_navigation", "Agent Home Navigation")
    case .mediaProjectionOCR: return t("galaxyssi.capability.screen_capture", "Screen Capture OCR")
    case .notificationRead: return t("galaxyssi.capability.notification_read", "Notification Read")
    case .notificationReply: return t("galaxyssi.capability.notification_reply", "Notification Reply")
    case .clipboard: return t("galaxyssi.capability.clipboard", "Clipboard")
    case .camera: return t("galaxyssi.capability.camera", "Camera")
    case .microphone: return t("galaxyssi.capability.microphone", "Microphone")
    case .location: return t("galaxyssi.capability.location", "Location")
    case .sensors: return t("galaxyssi.capability.sensors", "Sensors")
    case .bluetooth: return t("galaxyssi.capability.bluetooth", "Bluetooth")
    case .nfc: return t("galaxyssi.capability.nfc", "NFC")
    case .battery: return t("galaxyssi.capability.battery", "Battery")
    case .deviceMemory: return t("galaxyssi.capability.device_memory", "Device Memory")
    case .network: return t("galaxyssi.capability.network", "Network")
    case .installedApps: return t("galaxyssi.capability.installed_apps", "Installed Apps")
    case .intentLaunch: return t("galaxyssi.capability.intent_launch", "App Handoff")
    case .systemSettings: return t("galaxyssi.capability.system_settings", "System Settings")
    case .packageInstallHandoff: return t("galaxyssi.capability.package_install", "Package Install")
    case .deviceOwner: return t("galaxyssi.capability.device_owner", "Device Owner")
    case .shizuku: return t("galaxyssi.capability.shizuku", "Shizuku")
    case .root: return t("galaxyssi.capability.root", "Root")
    case .homeAssistant: return t("galaxyssi.capability.home_assistant", "Home Assistant")
    case .mediaPlayback: return t("galaxyssi.capability.media_playback", "Media Playback")
    case .mediaTranscode: return t("galaxyssi.capability.media_transcode", "Media Transcode")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private func appAdapterAvailabilityLabel(_ availability: GalaxySSIAppAdapterAvailability, language: String) -> String {
  GalaxySSILocalization.string(availabilityKey(availability), fallback: availabilityFallback(availability), language: language)
}

private func availabilityKey(_ availability: GalaxySSIAppAdapterAvailability) -> String {
  switch availability {
  case .ready: return "galaxyssi.app_adapters.status_ready"
  case .limited: return "galaxyssi.app_adapters.status_limited"
  case .needsSetup: return "galaxyssi.permission.needs_setup"
  case .unavailable: return "galaxyssi.native_tool_catalog.status_unavailable"
  }
}

private func availabilityFallback(_ availability: GalaxySSIAppAdapterAvailability) -> String {
  switch availability {
  case .ready: return "Ready"
  case .limited: return "Limited"
  case .needsSetup: return "Needs setup"
  case .unavailable: return "Unavailable"
  }
}

private func adapterTint(_ tone: GalaxySSIAppAdapterTone) -> Color {
  switch tone {
  case .accent: return .galaxySSIAccent
  case .blue: return .blue
  case .teal: return .teal
  case .orange: return .orange
  case .purple: return .purple
  case .gray: return .galaxySSITextSecondary
  }
}

private func availabilityTint(_ availability: GalaxySSIAppAdapterAvailability, fallback: Color) -> Color {
  switch availability {
  case .ready: return fallback
  case .limited, .needsSetup: return .orange
  case .unavailable: return .galaxySSITextSecondary
  }
}

private func availabilitySystemImage(_ availability: GalaxySSIAppAdapterAvailability) -> String {
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
    return .galaxySSIAccent
  case .limited, .needsRuntimePermission, .needsSpecialAccess, .needsUserConsent, .needsConfiguration:
    return .orange
  case .notImplemented, .privilegedOnly, .unsupported, .blockedByPolicy, .unknown:
    return .galaxySSITextSecondary
  }
}

private func capabilityAvailabilityLabel(_ availability: AgentPhoneCapabilityAvailability, language: String) -> String {
  switch availability {
  case .ready:
    return GalaxySSILocalization.string("galaxyssi.app_adapters.status_ready", fallback: "Ready", language: language)
  case .limited:
    return GalaxySSILocalization.string("galaxyssi.app_adapters.status_limited", fallback: "Limited", language: language)
  case .needsRuntimePermission, .needsSpecialAccess, .needsUserConsent, .needsConfiguration:
    return GalaxySSILocalization.string("galaxyssi.permission.needs_setup", fallback: "Needs setup", language: language)
  case .notImplemented:
    return GalaxySSILocalization.string("galaxyssi.app_adapters.status_not_implemented", fallback: "Not implemented", language: language)
  case .privilegedOnly:
    return GalaxySSILocalization.string("galaxyssi.app_adapters.status_privileged", fallback: "Privileged", language: language)
  case .unsupported:
    return GalaxySSILocalization.string("galaxyssi.app_adapters.status_unsupported", fallback: "Unsupported", language: language)
  case .blockedByPolicy:
    return GalaxySSILocalization.string("galaxyssi.app_adapters.status_blocked", fallback: "Blocked", language: language)
  case .unknown:
    return GalaxySSILocalization.string("galaxyssi.status.unknown", fallback: "Unknown", language: language)
  }
}

private func riskLabel(_ risk: AgentRisk, language: String) -> String {
  switch risk {
  case .low: return GalaxySSILocalization.string("galaxyssi.native_tool_catalog.risk_low", fallback: "Low", language: language)
  case .medium: return GalaxySSILocalization.string("galaxyssi.native_tool_catalog.risk_medium", fallback: "Medium", language: language)
  case .high: return GalaxySSILocalization.string("galaxyssi.native_tool_catalog.risk_high", fallback: "High", language: language)
  case .blocked: return GalaxySSILocalization.string("galaxyssi.native_tool_catalog.risk_blocked", fallback: "Blocked", language: language)
  }
}
