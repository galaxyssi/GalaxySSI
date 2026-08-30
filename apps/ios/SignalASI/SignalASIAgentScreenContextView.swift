import Foundation
import SwiftUI
import UIKit

struct SignalASIAgentScreenDetailRow: Identifiable, Equatable {
  var id: String
  var title: String
  var detail: String
  var systemImage: String
  var command: String?
  var isNotice: Bool

  init(
    id: String,
    title: String,
    detail: String = "",
    systemImage: String = "circle",
    command: String? = nil,
    isNotice: Bool = false
  ) {
    self.id = id
    self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    self.systemImage = systemImage
    let cleanCommand = command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.command = cleanCommand.isEmpty ? nil : cleanCommand
    self.isNotice = isNotice
  }

  var searchText: String {
    [title, detail, command ?? ""].joined(separator: " ")
  }
}

struct SignalASIAgentScreenDetailSection: Identifiable, Equatable {
  var id: String
  var title: String
  var rows: [SignalASIAgentScreenDetailRow]

  init(id: String, title: String, rows: [SignalASIAgentScreenDetailRow]) {
    self.id = id
    self.title = title
    self.rows = rows.filter { !$0.title.isEmpty || !$0.detail.isEmpty }
  }
}

struct SignalASIAgentScreenContextSnapshot: Equatable {
  var screen: AgentScreenContext
  var sections: [SignalASIAgentScreenDetailSection]
}

enum SignalASIAgentScreenContextSnapshotBuilder {
  static func make(
    messages: [ChatMessage],
    draft: String,
    attachments: [SignalASIDraftAttachment],
    unreadTotal: Int,
    screenObservationAllowed: Bool,
    snapshotAgeMillis: Int64 = 0,
    t: (String, String) -> String,
    clipboard: AgentClipboardContext = AgentClipboardContext(),
    notifications: AgentNotificationContext = AgentNotificationContext(),
    deviceStatus: AgentDeviceStatusContext = AgentDeviceStatusContext()
  ) -> SignalASIAgentScreenContextSnapshot {
    let resolvedClipboard = screenObservationAllowed ? clipboard : AgentClipboardContext()
    let resolvedDeviceStatus = screenObservationAllowed ? deviceStatus : AgentDeviceStatusContext()
    let visibleTexts = screenObservationAllowed
      ? visibleTextValues(
        messages: messages,
        draft: draft,
        attachments: attachments,
        unreadTotal: unreadTotal,
        t: t
      )
      : []
    let actionRows = screenObservationAllowed ? actionRows(t: t) : []
    let inputRows = screenObservationAllowed ? inputRows(t: t) : []
    let scrollRows = screenObservationAllowed ? scrollRows(t: t) : []
    let launchRows = screenObservationAllowed ? launchRows(t: t) : []
    let visibleNotifications = screenObservationAllowed ? notifications : AgentNotificationContext()
    let clickableElements = screenObservationAllowed
      ? elementInventory(actionRows + launchRows, className: "Button", visualRole: .button)
      : []
    let inputElements = screenObservationAllowed
      ? elementInventory(inputRows, className: "TextField", visualRole: .input)
      : []
    let scrollableElements = screenObservationAllowed
      ? elementInventory(scrollRows, className: "ScrollView", visualRole: .listItem)
      : []
    let sensitiveFlags = screenObservationAllowed ? sensitiveFlags(for: visibleTexts) : []
    let screen = AgentScreenContext(
      foregroundApp: "SignalASI iOS",
      activityName: "AgentHomeView",
      pageTitle: t("signalasi.tab.agent", "Agent"),
      visibleTextCount: visibleTexts.count,
      clickableNodeCount: clickableElements.count,
      inputFieldCount: inputElements.count,
      scrollableRegionCount: scrollableElements.count,
      sensitiveFlagCount: sensitiveFlags.count,
      visibleTexts: visibleTexts,
      selectedText: "",
      notifications: visibleNotifications,
      clipboard: resolvedClipboard,
      focusedInputField: inputElements.first,
      clickableElements: clickableElements,
      inputFields: inputElements,
      scrollableRegions: scrollableElements,
      sensitiveFlags: sensitiveFlags,
      deviceStatus: resolvedDeviceStatus,
      isAccessibilityEnabled: screenObservationAllowed,
      snapshotAgeMillis: snapshotAgeMillis
    )
    guard screenObservationAllowed else {
      return SignalASIAgentScreenContextSnapshot(screen: screen, sections: [])
    }
    return SignalASIAgentScreenContextSnapshot(
      screen: screen,
      sections: detailSections(
        visibleTexts: visibleTexts,
        actionRows: actionRows,
        inputRows: inputRows,
        scrollRows: scrollRows,
        launchRows: launchRows,
        notifications: visibleNotifications,
        clipboard: resolvedClipboard,
        deviceStatus: resolvedDeviceStatus,
        t: t
      )
    )
  }

  private static func detailSections(
    visibleTexts: [String],
    actionRows: [SignalASIAgentScreenDetailRow],
    inputRows: [SignalASIAgentScreenDetailRow],
    scrollRows: [SignalASIAgentScreenDetailRow],
    launchRows: [SignalASIAgentScreenDetailRow],
    notifications: AgentNotificationContext,
    clipboard: AgentClipboardContext,
    deviceStatus: AgentDeviceStatusContext,
    t: (String, String) -> String
  ) -> [SignalASIAgentScreenDetailSection] {
    let visibleRows = visibleTexts.prefix(8).enumerated().map { index, value in
      SignalASIAgentScreenDetailRow(
        id: "visible-\(index)",
        title: value,
        systemImage: "text.alignleft",
        command: "save note \(value)"
      )
    }
    let focusedInputRows = [
      SignalASIAgentScreenDetailRow(
        id: "focused-agent-goal",
        title: t("agent_screen_field_agent_goal", "Agent goal input"),
        detail: t("agent_screen_field_agent_goal_detail", "type text into Agent goal input"),
        systemImage: "keyboard",
        command: "type text into Agent goal input"
      )
    ]
    let sections = [
      SignalASIAgentScreenDetailSection(
        id: "focused-input",
        title: t("agent_screen_focused_input", "Focused Input"),
        rows: focusedInputRows
      ),
      SignalASIAgentScreenDetailSection(
        id: "clipboard",
        title: t("agent_screen_clipboard", "Clipboard"),
        rows: clipboard.hasText ? [
          SignalASIAgentScreenDetailRow(
            id: "clipboard-paste",
            title: t("agent_screen_clipboard", "Clipboard"),
            detail: clipboardDetail(clipboard, t: t),
            systemImage: "doc.on.clipboard",
            command: "paste clipboard"
          )
        ] : []
      ),
      SignalASIAgentScreenDetailSection(
        id: "notifications",
        title: t("agent_screen_notifications", "Notifications"),
        rows: notificationRows(notifications, t: t)
      ),
      SignalASIAgentScreenDetailSection(
        id: "device-status",
        title: t("agent_screen_device_status", "Device Status"),
        rows: [
          SignalASIAgentScreenDetailRow(
            id: "device-status-current",
            title: t("agent_screen_device_status", "Device Status"),
            detail: deviceStatusDetail(deviceStatus, t: t),
            systemImage: "battery.100",
            command: "device status"
          )
        ]
      ),
      SignalASIAgentScreenDetailSection(
        id: "visual-grounding",
        title: t("agent_screen_visual_grounding", "On-device Visual Grounding"),
        rows: [
          SignalASIAgentScreenDetailRow(
            id: "visual-summary",
            title: t("agent_screen_visual_grounding", "On-device Visual Grounding"),
            detail: String(
              format: t("agent_screen_visual_summary_ios", "%@ / %d elements / %d actions / %d fields"),
              "SignalASI iOS",
              visibleTexts.count,
              actionRows.count,
              inputRows.count
            ),
            systemImage: "viewfinder",
            command: "read current screen"
          )
        ]
      ),
      SignalASIAgentScreenDetailSection(
        id: "launchable-apps",
        title: t("agent_screen_launchable_apps", "Launchable Apps"),
        rows: launchRows
      ),
      SignalASIAgentScreenDetailSection(
        id: "visible-text",
        title: t("agent_screen_texts", "Visible Text"),
        rows: visibleRows
      ),
      SignalASIAgentScreenDetailSection(
        id: "actions",
        title: t("agent_screen_actions", "Actions"),
        rows: actionRows
      ),
      SignalASIAgentScreenDetailSection(
        id: "fields",
        title: t("agent_screen_fields", "Input Fields"),
        rows: inputRows
      ),
      SignalASIAgentScreenDetailSection(
        id: "scrollable",
        title: t("agent_screen_scrollable_regions", "Scrollable Regions"),
        rows: scrollRows
      )
    ]
    return sections.filter { !$0.rows.isEmpty }
  }

  private static func notificationRows(
    _ notifications: AgentNotificationContext,
    t: (String, String) -> String
  ) -> [SignalASIAgentScreenDetailRow] {
    guard notifications.hasAccess else {
      return [
        SignalASIAgentScreenDetailRow(
          id: "notifications-limited",
          title: t("agent_screen_notifications_locked", "Notification access is not enabled"),
          systemImage: "bell.slash",
          isNotice: true
        )
      ]
    }
    guard !notifications.items.isEmpty else {
      return [
        SignalASIAgentScreenDetailRow(
          id: "notifications-empty",
          title: t("agent_screen_notifications_empty_ios", "No SignalASI notifications available"),
          systemImage: "bell",
          isNotice: true
        )
      ]
    }
    return notifications.items.prefix(3).enumerated().map { index, item in
      let sensitive = !item.sensitiveFlags.isEmpty
      let replyAvailable = item.canReply && !sensitive
      let title = sensitive
        ? t("agent_screen_notification_sensitive_ios", "Sensitive notification / content hidden")
        : item.title.ifBlank(item.packageName.ifBlank(t("agent_screen_notifications", "Notification")))
      let baseDetail = sensitive
        ? String(format: t("agent_screen_notification_sensitive_detail_ios", "%d sensitive flags"), item.sensitiveFlags.count)
        : [item.packageName, item.textPreview].filter { !$0.isEmpty }.joined(separator: " / ")
      let detail = replyAvailable
        ? [
            baseDetail,
            t("agent_screen_notification_reply_available_ios", "Reply available")
          ].filter { !$0.isEmpty }.joined(separator: " / ")
        : baseDetail
      return SignalASIAgentScreenDetailRow(
        id: "notification-\(index)-\(item.key)",
        title: title,
        detail: detail,
        systemImage: sensitive ? "bell.badge" : "bell",
        command: sensitive
          ? nil
          : replyAvailable
            ? "reply notification \(item.packageName.ifBlank("SignalASI")) :: "
            : "read notifications",
        isNotice: sensitive
      )
    }
  }

  private static func clipboardDetail(
    _ clipboard: AgentClipboardContext,
    t: (String, String) -> String
  ) -> String {
    if !clipboard.sensitiveFlags.isEmpty {
      return String(
        format: t("agent_screen_clipboard_sensitive_ios", "%d chars / sensitive content"),
        clipboard.textLength
      )
    }
    return String(
      format: t("agent_screen_clipboard_summary_ios", "%d chars / %@"),
      clipboard.textLength,
      clipboard.preview.ifBlank(clipboard.textHash)
    )
  }

  private static func elementInventory(
    _ rows: [SignalASIAgentScreenDetailRow],
    className: String,
    visualRole: AgentVisualRole
  ) -> [AgentScreenElement] {
    rows.map { row in
      AgentScreenElement(
        label: row.title,
        viewId: "ios.agent.\(row.id)",
        className: className,
        bounds: "logical://AgentHomeView/\(row.id)",
        origin: .manual,
        confidence: 1,
        visualRole: visualRole,
        actionable: row.command != nil
      )
    }
  }

  private static func sensitiveFlags(for values: [String]) -> [String] {
    let normalized = values.joined(separator: " ").lowercased()
    guard !normalized.isEmpty else { return [] }
    let terms = [
      ("password", "password"),
      ("passcode", "passcode"),
      ("verification code", "verification_code"),
      ("otp", "otp"),
      ("private key", "private_key"),
      ("secret", "secret"),
      ("token", "token"),
      ("密码", "password"),
      ("验证码", "verification_code"),
      ("私钥", "private_key"),
      ("支付", "payment")
    ]
    var flags: [String] = []
    for (term, flag) in terms where normalized.contains(term) {
      if !flags.contains(flag) {
        flags.append(flag)
      }
    }
    if normalized.range(of: #"\b(?:\d[ -]?){13,19}\b"#, options: .regularExpression) != nil,
       !flags.contains("financial") {
      flags.append("financial")
    }
    return Array(flags.prefix(12))
  }

  private static func visibleTextValues(
    messages: [ChatMessage],
    draft: String,
    attachments: [SignalASIDraftAttachment],
    unreadTotal: Int,
    t: (String, String) -> String
  ) -> [String] {
    var values: [String] = [
      "SignalASI",
      t("signalasi.agent.brand.subtitle", "Super Agent"),
      t("signalasi.agent.session.new", "New session"),
      unreadTotal > 0 ? String(format: t("signalasi.agent.unread", "%d unread"), unreadTotal) : t("signalasi.agent.tab.subtitle", "Phone-native super agent"),
      t("agent_section_screen_details", "Screen Details"),
      t("signalasi.agent.section.process", "Process"),
      t("signalasi.agent.step.observe", "Read current screen structure"),
      t("signalasi.agent.step.analyze", "Analyze user goal"),
      t("signalasi.agent.step.plan", "Generate executable plan"),
      t("signalasi.agent.step.act", "Execute after confirmation"),
      t("signalasi.agent.section.info", "Info"),
      String(format: t("signalasi.agent.current_app", "Current App: %@"), "SignalASI iOS")
    ]
    values.append(contentsOf: messages.suffix(6).map(\.content))
    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      values.append(String(format: t("agent_screen_visible_draft", "Draft: %@"), draft))
    }
    values.append(contentsOf: attachments.map(\.label))
    return uniqueValues(values).prefix(16).map { $0 }
  }

  private static func actionRows(t: (String, String) -> String) -> [SignalASIAgentScreenDetailRow] {
    [
      commandRow(
        id: "new-session",
        title: t("agent_attachment_new_task", "New session"),
        detail: t("agent_screen_action_new_session_detail", "new session"),
        systemImage: "square.and.pencil",
        command: "new session"
      ),
      commandRow(
        id: "sessions",
        title: t("agent_attachment_sessions", "Sessions"),
        detail: t("agent_screen_action_sessions_detail", "show agent sessions"),
        systemImage: "tray.full",
        command: "show agent sessions"
      ),
      commandRow(
        id: "scan",
        title: t("agent_attachment_scan", "Scan"),
        detail: t("agent_screen_action_scan_detail", "scan agent QR code"),
        systemImage: "qrcode.viewfinder",
        command: "scan agent QR code"
      ),
      commandRow(
        id: "take-photo",
        title: t("agent_attachment_take_photo", "Take photo"),
        detail: t("agent_screen_action_photo_detail", "take a photo"),
        systemImage: "camera",
        command: "take a photo"
      ),
      commandRow(
        id: "add-photos",
        title: t("agent_attachment_add_photos", "Add photos"),
        detail: t("agent_screen_action_photos_detail", "attach photos from the library"),
        systemImage: "photo.on.rectangle",
        command: "attach photos"
      ),
      commandRow(
        id: "add-file",
        title: t("agent_attachment_add_file", "Add file"),
        detail: t("agent_screen_action_file_detail", "attach a file"),
        systemImage: "doc",
        command: "attach a file"
      ),
      commandRow(
        id: "model-selection",
        title: t("agent_screen_action_model_selection", "Model selection"),
        detail: t("agent_screen_action_model_selection_detail", "choose the Agent model or route"),
        systemImage: "arrow.triangle.2.circlepath",
        command: "choose Agent model"
      ),
      commandRow(
        id: "native-tools",
        title: t("agent_screen_action_native_tools", "Native tools"),
        detail: t("agent_screen_action_native_tools_detail", "show available phone-native tools"),
        systemImage: "wrench.and.screwdriver",
        command: "show native tools"
      ),
      commandRow(
        id: "memory",
        title: t("agent_screen_action_memory", "Memory"),
        detail: t("agent_screen_action_memory_detail", "open Agent memory"),
        systemImage: "brain",
        command: "open Agent memory"
      ),
      commandRow(
        id: "knowledge",
        title: t("agent_screen_action_knowledge", "Knowledge"),
        detail: t("agent_screen_action_knowledge_detail", "open Agent knowledge"),
        systemImage: "books.vertical",
        command: "open Agent knowledge"
      ),
      commandRow(
        id: "screen-context",
        title: t("agent_screen_action_screen_context", "Screen context"),
        detail: t("agent_screen_action_screen_context_detail", "inspect current screen context"),
        systemImage: "rectangle.on.rectangle",
        command: "show screen context"
      ),
      commandRow(
        id: "refresh-screen-context",
        title: t("agent_screen_refresh", "Refresh context"),
        detail: t(
          "agent_screen_action_refresh_screen_detail",
          "refresh the current screen context"
        ),
        systemImage: "arrow.clockwise",
        command: "refresh screen context"
      ),
      commandRow(
        id: "insights",
        title: t("agent_screen_action_insights", "New insights"),
        detail: t("agent_screen_action_insights_detail", "open new Agent findings"),
        systemImage: "sparkles",
        command: "show new Agent insights"
      ),
      commandRow(
        id: "recent-tasks",
        title: t("agent_screen_action_recent_tasks", "Recent tasks"),
        detail: t("agent_screen_action_recent_tasks_detail", "open recent Agent tasks"),
        systemImage: "clock.arrow.circlepath",
        command: "show recent Agent tasks"
      ),
      commandRow(
        id: "permission-mode",
        title: t("agent_screen_action_permission_mode", "Permission mode"),
        detail: t("agent_screen_action_permission_mode_detail", "cycle Agent permission mode"),
        systemImage: "checklist",
        command: "cycle Agent permission mode"
      ),
      commandRow(
        id: "task-execution-mode",
        title: t("agent_screen_action_task_execution_mode", "Task execution mode"),
        detail: t(
          "agent_screen_action_task_execution_mode_detail",
          "cycle Agent plan-only or auto-complete mode"
        ),
        systemImage: "play.rectangle",
        command: "cycle Agent task execution mode"
      ),
      commandRow(
        id: "high-risk-guard",
        title: t("agent_screen_action_high_risk_guard", "High-risk guard"),
        detail: t("agent_screen_action_high_risk_guard_detail", "toggle high-risk action protection"),
        systemImage: "shield.lefthalf.filled",
        command: "toggle Agent high-risk guard"
      ),
      commandRow(
        id: "memory-capture",
        title: t("agent_screen_action_memory_capture", "Memory capture"),
        detail: t("agent_screen_action_memory_capture_detail", "toggle Agent memory capture"),
        systemImage: "brain",
        command: "toggle Agent memory capture"
      ),
      commandRow(
        id: "execution-paused",
        title: t("agent_screen_action_execution", "Execution"),
        detail: t("agent_screen_action_execution_detail", "toggle Agent execution pause"),
        systemImage: "pause.circle",
        command: "toggle Agent execution pause"
      ),
      commandRow(
        id: "permissions",
        title: t("cc_permissions_title", "Permissions & Audit"),
        detail: t("agent_screen_action_permissions_detail", "open permissions"),
        systemImage: "hand.raised",
        command: "open permissions"
      ),
      commandRow(
        id: "settings",
        title: t("signalasi.tab.settings", "Settings"),
        detail: t("agent_screen_action_settings_detail", "open settings"),
        systemImage: "gearshape",
        command: "open settings"
      )
    ]
  }

  private static func inputRows(t: (String, String) -> String) -> [SignalASIAgentScreenDetailRow] {
    [
      commandRow(
        id: "agent-goal-input",
        title: t("agent_screen_field_agent_goal", "Agent goal input"),
        detail: t("agent_screen_field_agent_goal_detail", "type text into Agent goal input"),
        systemImage: "keyboard",
        command: "type text into Agent goal input"
      )
    ]
  }

  private static func scrollRows(t: (String, String) -> String) -> [SignalASIAgentScreenDetailRow] {
    [
      commandRow(
        id: "agent-transcript",
        title: t("agent_screen_scroll_agent_transcript", "Agent transcript"),
        detail: t("agent_screen_scroll_agent_transcript_detail", "swipe up"),
        systemImage: "arrow.up.and.down",
        command: "swipe up"
      )
    ]
  }

  private static func launchRows(t: (String, String) -> String) -> [SignalASIAgentScreenDetailRow] {
    [
      launchRow(id: "agent", title: t("signalasi.tab.agent", "Agent"), command: "open Agent", t: t),
      launchRow(id: "messages", title: t("signalasi.agent_sessions.title", "Sessions"), command: "open Messages", t: t),
      launchRow(id: "contacts", title: t("signalasi.tab.contacts", "Contacts"), command: "open Contacts", t: t),
      launchRow(id: "discover", title: t("signalasi.tab.discover", "Discover"), command: "open Discover", t: t),
      launchRow(id: "settings", title: t("signalasi.tab.settings", "Settings"), command: "open Settings", t: t)
    ]
  }

  private static func commandRow(
    id: String,
    title: String,
    detail: String,
    systemImage: String,
    command: String
  ) -> SignalASIAgentScreenDetailRow {
    SignalASIAgentScreenDetailRow(
      id: id,
      title: title,
      detail: detail,
      systemImage: systemImage,
      command: command
    )
  }

  private static func launchRow(
    id: String,
    title: String,
    command: String,
    t: (String, String) -> String
  ) -> SignalASIAgentScreenDetailRow {
    SignalASIAgentScreenDetailRow(
      id: "launch-\(id)",
      title: title,
      detail: String(format: t("agent_screen_launchable_app_summary_ios", "%@ / open"), "SignalASI"),
      systemImage: "app",
      command: command
    )
  }

  static func currentDeviceStatus() -> AgentDeviceStatusContext {
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let batteryPercent = device.batteryLevel >= 0
      ? Int((device.batteryLevel * 100).rounded())
      : -1
    let charging = device.batteryState == .charging || device.batteryState == .full
    let probe = AgentMediaNetworkDetector.shared.currentProbe
    let network: String
    if !probe.networkPresent {
      network = "offline"
    } else if let transport = probe.transports.first(where: { !$0.isEmpty }) {
      network = transport
    } else if probe.cellular {
      network = "cellular"
    } else if probe.internetCapable {
      network = "internet"
    } else {
      network = "unknown"
    }
    let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
    let totalStorage = (attributes?[.systemSize] as? NSNumber)?.int64Value ?? 0
    let freeStorage = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    let thermal: String
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:
      thermal = "nominal"
    case .fair:
      thermal = "fair"
    case .serious:
      thermal = "serious"
    case .critical:
      thermal = "critical"
    @unknown default:
      thermal = "unknown"
    }
    return AgentDeviceStatusContext(
      batteryPercent: batteryPercent,
      charging: charging,
      powerSaveMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
      network: network,
      freeStorageMb: freeStorage / (1024 * 1024),
      totalStorageMb: totalStorage / (1024 * 1024),
      thermalState: thermal
    )
  }

  private static func deviceStatusDetail(
    _ status: AgentDeviceStatusContext,
    t: (String, String) -> String
  ) -> String {
    let battery: String
    if status.batteryPercent >= 0 {
      battery = "\(status.batteryPercent)%"
    } else {
      battery = t("common_unknown", "Unknown")
    }
    let power: String
    if status.powerSaveMode {
      power = t("agent_screen_power_low", "power save")
    } else if status.charging {
      power = t("agent_screen_power_charging", "charging")
    } else {
      power = t("agent_screen_power_battery", "battery")
    }
    let thermal = thermalStateLabel(status.thermalState, t: t)
    let network = status.network.ifBlank(t("common_unknown", "Unknown"))
    let storage = status.freeStorageMb > 0
      ? ByteCountFormatter.string(fromByteCount: status.freeStorageMb * 1024 * 1024, countStyle: .file)
      : t("common_unknown", "Unknown")
    return String(
      format: t("agent_screen_device_status_summary_ios_v2", "Battery %@ / %@ / %@ / %@ / %@ free"),
      battery,
      power,
      thermal,
      network,
      storage
    )
  }

  private static func thermalStateLabel(
    _ state: String,
    t: (String, String) -> String
  ) -> String {
    switch state.lowercased() {
    case "nominal":
      return t("agent_screen_thermal_nominal", "normal")
    case "fair":
      return t("agent_screen_thermal_fair", "warm")
    case "serious":
      return t("agent_screen_thermal_serious", "hot")
    case "critical":
      return t("agent_screen_thermal_critical", "critical")
    default:
      return t("common_unknown", "Unknown")
    }
  }

  private static func uniqueValues(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanValue.isEmpty else { return nil }
      let key = cleanValue.lowercased()
      guard !seen.contains(key) else { return nil }
      seen.insert(key)
      return cleanValue
    }
  }
}

struct SignalASIAgentScreenContextCard: View {
  var screen: AgentScreenContext
  var sections: [SignalASIAgentScreenDetailSection]
  var onCommand: (String) -> Void
  var t: (String, String) -> String
  var onRefresh: () -> Void = {}
  var expandedByDefault: Bool = false

  @State private var expanded = false
  @State private var query = ""

  private var normalizedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var pageTitle: String {
    screen.pageTitle.ifBlank(screen.foregroundApp).ifBlank("SignalASI iOS")
  }

  private var ageSeconds: Int {
    Int(max(0, screen.snapshotAgeMillis / 1000))
  }

  private var summaryText: String {
    String(
      format: t("agent_screen_context_value", "Screen: %d text / %d actions / %d fields"),
      max(screen.visibleTextCount, screen.visibleTexts.count),
      screen.clickableNodeCount,
      screen.inputFieldCount
    )
  }

  private var filteredSections: [SignalASIAgentScreenDetailSection] {
    sections.compactMap { section in
      let rows = section.rows.filter { row in
        matches(section.title) || matches(row.searchText)
      }
      guard !rows.isEmpty else { return nil }
      return SignalASIAgentScreenDetailSection(id: section.id, title: section.title, rows: Array(rows.prefix(8)))
    }
  }

  private var disabled: Bool {
    !screen.isAccessibilityEnabled && sections.isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Button {
          withAnimation(.easeOut(duration: 0.16)) {
            expanded.toggle()
          }
        } label: {
          HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.signalASIAccent)
              .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
              Text(t("agent_section_screen_details", "Screen Details"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.signalASITextPrimary)
                .lineLimit(1)
              Text(summaryText)
                .font(.system(size: 11))
                .foregroundColor(.signalASITextSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(.signalASITextSecondary)
          }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)

        Button(action: onRefresh) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.signalASITextSecondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(t("agent_screen_refresh", "Refresh screen context")))
      }

      if expanded {
        if disabled {
          emptyRow(t("agent_screen_disabled", "Enable screen access to inspect this page"))
        } else {
          searchField
          summaryRow
          if filteredSections.isEmpty {
            emptyRow(t("agent_screen_empty", "No matching screen items"))
          } else {
            ForEach(filteredSections) { section in
              screenSection(section)
            }
          }
        }
      }
    }
    .padding(12)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .onAppear {
      if expandedByDefault {
        expanded = true
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
      TextField(t("agent_screen_search_hint", "Search screen text, actions, or fields"), text: $query)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
    }
    .padding(.horizontal, 10)
    .frame(height: 38)
    .background(Color.signalASISearchBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var summaryRow: some View {
    Text(String(format: t("agent_screen_summary", "Page: %@ / age: %ds"), pageTitle, ageSeconds))
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextPrimary)
      .lineLimit(1)
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, 14)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func screenSection(_ section: SignalASIAgentScreenDetailSection) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(section.title)
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(.signalASITextSecondary)
        .padding(.top, 4)
      ForEach(section.rows) { row in
        screenRow(row)
      }
    }
  }

  @ViewBuilder
  private func screenRow(_ row: SignalASIAgentScreenDetailRow) -> some View {
    if let command = row.command {
      Button {
        onCommand(command)
      } label: {
        rowContent(row, commandable: true)
      }
      .buttonStyle(.plain)
    } else {
      rowContent(row, commandable: false)
    }
  }

  private func rowContent(_ row: SignalASIAgentScreenDetailRow, commandable: Bool) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: row.systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(row.isNotice ? .signalASITextSecondary : .signalASIAccent)
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 3) {
        if !row.title.isEmpty {
          Text(row.title)
            .font(.system(size: 13))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(2)
        }
        if !row.detail.isEmpty {
          Text(row.detail)
            .font(.system(size: 11))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 8)
      if commandable {
        Image(systemName: "arrow.down.left.circle")
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
          .padding(.top, 2)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func emptyRow(_ text: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "info.circle")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
      Text(text)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func matches(_ value: String) -> Bool {
    guard !normalizedQuery.isEmpty else { return true }
    return value.range(
      of: normalizedQuery,
      options: [.caseInsensitive, .diacriticInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    ) != nil
  }
}

struct SignalASIAgentScreenContextDetailView: View {
  var screen: AgentScreenContext
  var sections: [SignalASIAgentScreenDetailSection]
  var onCommand: (String) -> Void
  var t: (String, String) -> String
  var onRefresh: () -> Void = {}

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        SignalASIAgentScreenContextCard(
          screen: screen,
          sections: sections,
          onCommand: onCommand,
          t: t,
          onRefresh: onRefresh,
          expandedByDefault: true
        )

        if !screen.isAccessibilityEnabled {
          NavigationLink(destination: OnDeviceAgentPermissionsView()) {
            HStack(spacing: 8) {
              Image(systemName: "eye.slash")
                .foregroundColor(.orange)
              Text(t("agent_accessibility_status_disabled", "Screen access: needs permission"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
              Spacer(minLength: 4)
              Text(t("signalasi.common.manage", "Manage"))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.orange)
              Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.signalASISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(12)
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationTitle(t("agent_section_screen_details", "Screen Details"))
    .navigationBarTitleDisplayMode(.inline)
  }
}
