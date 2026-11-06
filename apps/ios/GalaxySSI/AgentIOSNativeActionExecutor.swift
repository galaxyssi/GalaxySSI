import Foundation
import UIKit
import UserNotifications
#if canImport(MessageUI)
import MessageUI
#endif

protocol AgentIOSNativeActionHandoffProviding {
  func open(_ url: URL) -> Bool
}

struct AgentIOSDefaultNativeActionHandoffProvider: AgentIOSNativeActionHandoffProviding {
  func open(_ url: URL) -> Bool {
    if Thread.isMainThread {
      return openOnMain(url)
    }
    var opened = false
    DispatchQueue.main.sync {
      opened = openOnMain(url)
    }
    return opened
  }

  private func openOnMain(_ url: URL) -> Bool {
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    return true
  }
}

enum AgentIOSNativeToolHandoffPresenter {
  @discardableResult
  static func openSMSCompose(phoneNumber: String, body: String) -> Bool {
    guard let normalized = normalizedPhoneNumber(phoneNumber) else { return false }
    presentSMSCompose(AgentIOSSMSComposeRequest(
      phoneNumber: normalized,
      body: String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000)),
      fallbackURL: "sms:\(normalized)"
    ))
    return true
  }

  @discardableResult
  static func openDialer(phoneNumber: String) -> Bool {
    guard let normalized = normalizedPhoneNumber(phoneNumber) else { return false }
    let encodedNumber = normalized.addingPercentEncoding(
      withAllowedCharacters: .decimalDigits.union(CharacterSet(charactersIn: "+*,"))
    ) ?? normalized
    open(rawURL: "tel:\(encodedNumber)")
    return true
  }

  static func openIfNeeded(_ result: AgentActionResult) {
    guard result.success,
          let rawOutput = result.metadata["native_tool_output"],
          let data = rawOutput.data(using: .utf8),
          let output = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      return
    }
    openIfNeeded(output)
  }

  static func openIfNeeded(_ result: AgentNativeToolResult) {
    guard result.isSuccess else { return }
    openIfNeeded(result.output)
  }

  private static func openIfNeeded(_ output: AgentMcpJSONObject) {
    if let request = smsComposeRequest(in: .object(output)) {
      presentSMSCompose(request)
      return
    }
    guard let rawURL = handoffURL(in: .object(output)) else { return }
    open(rawURL: rawURL)
  }

  private static func smsComposeRequest(in value: AgentMcpJSONValue) -> AgentIOSSMSComposeRequest? {
    switch value {
    case .object(let object):
      guard object["requires_user_action"]?.boolValue == true,
            object["handoff_kind"]?.stringValue == "sms_compose",
            let phoneNumber = normalizedPhoneNumber(object["phone_number"]?.stringValue),
            let fallbackURL = object["url"]?.stringValue else {
        return object.values.lazy.compactMap(smsComposeRequest(in:)).first
      }
      return AgentIOSSMSComposeRequest(
        phoneNumber: phoneNumber,
        body: String((object["prefill_body"]?.stringValue ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .prefix(2_000)),
        fallbackURL: fallbackURL
      )
    case .array(let values):
      return values.lazy.compactMap(smsComposeRequest(in:)).first
    case .string, .int, .double, .bool, .null:
      return nil
    }
  }

  private static func handoffURL(in value: AgentMcpJSONValue) -> String? {
    switch value {
    case .object(let object):
      if object["requires_user_action"]?.boolValue == true,
         let handoffKind = object["handoff_kind"]?.stringValue,
         ["dial", "sms_compose", "settings"].contains(handoffKind),
         let rawURL = object["url"]?.stringValue {
        return rawURL
      }
      return object.values.lazy.compactMap { handoffURL(in: $0) }.first
    case .array(let values):
      return values.lazy.compactMap { handoffURL(in: $0) }.first
    case .string, .int, .double, .bool, .null:
      return nil
    }
  }

  private static func open(rawURL: String) {
    let openBlock = {
      let url: URL
      if rawURL == "app-settings:" {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        url = settingsURL
      } else {
        guard let candidate = URL(string: rawURL),
              ["tel", "sms"].contains(candidate.scheme?.lowercased() ?? "") else {
          return
        }
        url = candidate
      }

      AgentIOSDefaultNativeActionHandoffProvider().open(url)
    }
    if Thread.isMainThread {
      openBlock()
    } else {
      DispatchQueue.main.async(execute: openBlock)
    }
  }

  private static func presentSMSCompose(_ request: AgentIOSSMSComposeRequest) {
    let present = {
      #if canImport(MessageUI)
      guard MFMessageComposeViewController.canSendText(),
            let presenter = topViewController() else {
        open(rawURL: request.fallbackURL)
        return
      }
      guard AgentIOSMessageComposePresenter.shared.present(request, from: presenter) else {
        open(rawURL: request.fallbackURL)
        return
      }
      #else
      open(rawURL: request.fallbackURL)
      #endif
    }
    if Thread.isMainThread {
      present()
    } else {
      DispatchQueue.main.async(execute: present)
    }
  }

  private static func topViewController() -> UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    guard let root = windows.first(where: \.isKeyWindow)?.rootViewController
      ?? windows.first?.rootViewController else {
      return nil
    }
    var current = root
    while let presented = current.presentedViewController, !presented.isBeingDismissed {
      current = presented
    }
    return current
  }

  private static func normalizedPhoneNumber(_ value: String?) -> String? {
    var normalized = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    for removable in [" ", "-", "(", ")", "."] {
      normalized = normalized.replacingOccurrences(of: removable, with: "")
    }
    guard !normalized.isEmpty,
          normalized.count <= 64,
          normalized.range(of: #"^[+0-9*#,;]+$"#, options: .regularExpression) != nil else {
      return nil
    }
    return normalized
  }
}

private struct AgentIOSSMSComposeRequest {
  var phoneNumber: String
  var body: String
  var fallbackURL: String
}

#if canImport(MessageUI)
private final class AgentIOSMessageComposePresenter: NSObject, MFMessageComposeViewControllerDelegate {
  static let shared = AgentIOSMessageComposePresenter()
  private weak var activeComposer: MFMessageComposeViewController?

  func present(_ request: AgentIOSSMSComposeRequest, from presenter: UIViewController) -> Bool {
    guard activeComposer == nil else { return false }
    let composer = MFMessageComposeViewController()
    composer.recipients = [request.phoneNumber]
    composer.body = request.body
    composer.messageComposeDelegate = self
    activeComposer = composer
    presenter.present(composer, animated: true)
    return true
  }

  func messageComposeViewController(
    _ controller: MFMessageComposeViewController,
    didFinishWith result: MessageComposeResult
  ) {
    controller.dismiss(animated: true)
    activeComposer = nil
  }
}
#endif

struct AgentIOSNativeActionExecutor: AgentActionExecutor {
  var handoffProvider: AgentIOSNativeActionHandoffProviding
  var notificationCenter: UNUserNotificationCenter
  var nowMillis: () -> Int64
  var knowledgeStore: ((AgentKnowledgeItem) -> AgentKnowledgeItem)?
  var webKnowledgeImporter: ((String, String) -> AgentIOSWebKnowledgeImportResult)?
  var timerStore: AgentIOSTimerCheckpointStore

  init(
    handoffProvider: AgentIOSNativeActionHandoffProviding = AgentIOSDefaultNativeActionHandoffProvider(),
    notificationCenter: UNUserNotificationCenter = .current(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    knowledgeStore: ((AgentKnowledgeItem) -> AgentKnowledgeItem)? = nil,
    webKnowledgeImporter: ((String, String) -> AgentIOSWebKnowledgeImportResult)? = nil,
    timerStore: AgentIOSTimerCheckpointStore = .shared
  ) {
    self.handoffProvider = handoffProvider
    self.notificationCenter = notificationCenter
    self.nowMillis = nowMillis
    self.knowledgeStore = knowledgeStore
    self.webKnowledgeImporter = webKnowledgeImporter
    self.timerStore = timerStore
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    switch action.kind {
    case .importWebKnowledge:
      return importWebKnowledge(action)
    case .draftPlan:
      return draftPlan(action)
    case .saveScreenKnowledge:
      return saveScreenKnowledge(action, screen: screen)
    case .readScreen:
      return readScreen(action, screen: screen)
    case .copyScreenText:
      return copyScreenText(action, screen: screen)
    case .openURL:
      return openURL(action)
    case .openApp:
      return openApp(action)
    case .setAlarm:
      return scheduleAlarmOrTimer(action)
    case .createNotification:
      return createNotification(action)
    case .typeText, .deleteText, .pasteText:
      return composerInput(action, screen: screen)
    case .back:
      return backOwnedAgentHome(action, screen: screen)
    case .swipe:
      return swipeOwnedAgentTranscript(action, screen: screen)
    case .tap:
      return tapOwnedAgentHomeElement(action, screen: screen)
    case .longPress:
      return longPressOwnedAgentHomeElement(action, screen: screen)
    default:
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "This iOS action requires a capability that normal apps cannot provide.",
        metadata: [
          "platform": "ios",
          "action_kind": action.kind.rawValue,
          "completion_verified": "false",
          "ios_boundary": "normal_app_process"
        ]
      )
    }
  }

  private func composerInput(_ action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    let composerField = screen.inputFields.first { field in
      field.viewId == "ios.agent.agent-goal-input"
    } ?? screen.focusedInputField
    guard let composerField,
          composerField.viewId == "ios.agent.agent-goal-input",
          composerField.origin == .manual else {
      return failure(
        action,
        "This iOS input action requires the GalaxySSI Agent composer.",
        code: "IOS_AGENT_COMPOSER_ONLY"
      )
    }

    let requestedOrigin = clean(action.parameters["field_origin"] ?? "")
    guard requestedOrigin.isEmpty || requestedOrigin == AgentElementOrigin.manual.rawValue else {
      return failure(
        action,
        "iOS can edit only the GalaxySSI Agent composer input on this device.",
        code: "IOS_AGENT_COMPOSER_ONLY"
      )
    }
    let requestedBounds = clean(action.parameters["field_bounds"] ?? "")
    guard requestedBounds.isEmpty || requestedBounds == composerField.bounds else {
      return failure(
        action,
        "The requested input field is not the GalaxySSI Agent composer.",
        code: "IOS_AGENT_COMPOSER_FIELD_MISMATCH"
      )
    }
    return AgentIOSComposerInputBridge.shared.execute(action: action)
  }

  private func backOwnedAgentHome(
    _ action: AgentAction,
    screen: AgentScreenContext
  ) -> AgentActionResult {
    guard screen.activityName == "AgentHomeView" else {
      return failure(
        action,
        "This iOS back action is limited to the GalaxySSI Agent home page.",
        code: "IOS_AGENT_HOME_NAVIGATION_ONLY"
      )
    }
    return AgentIOSAgentHomeActionBridge.shared.executeBack(action: action)
  }

  private func swipeOwnedAgentTranscript(
    _ action: AgentAction,
    screen: AgentScreenContext
  ) -> AgentActionResult {
    let direction = AgentIOSAgentSwipeDirection.resolve(parameters: action.parameters)
    guard let direction else {
      return failure(
        action,
        "The iOS Agent transcript swipe direction is invalid.",
        code: "IOS_AGENT_TRANSCRIPT_DIRECTION_INVALID"
      )
    }
    guard direction == .up || direction == .down else {
      return failure(
        action,
        "The iOS Agent transcript supports only vertical swipes.",
        code: "IOS_AGENT_TRANSCRIPT_VERTICAL_ONLY"
      )
    }
    let transcript = screen.scrollableRegions.first { element in
      element.viewId == "ios.agent.agent-transcript" &&
        element.origin == .manual &&
        element.bounds == "logical://AgentHomeView/agent-transcript"
    }
    guard screen.activityName == "AgentHomeView", transcript != nil else {
      return failure(
        action,
        "This iOS swipe action is limited to the visible GalaxySSI Agent transcript.",
        code: "IOS_AGENT_TRANSCRIPT_ONLY"
      )
    }
    return AgentIOSAgentHomeSwipeBridge.shared.execute(action: action)
  }

  private func tapOwnedAgentHomeElement(
    _ action: AgentAction,
    screen: AgentScreenContext
  ) -> AgentActionResult {
    let requestedBounds = clean(action.parameters["bounds"] ?? "")
    let requestedLabel = clean(action.parameters["matched_label"] ?? "")
    let element = screen.clickableElements.first { candidate in
      candidate.viewId.hasPrefix("ios.agent.") &&
        ((requestedBounds.isEmpty && !requestedLabel.isEmpty && candidate.label == requestedLabel) ||
          (!requestedBounds.isEmpty && candidate.bounds == requestedBounds))
    }
    guard let element,
          element.origin == .manual,
          element.bounds.hasPrefix("logical://AgentHomeView/") else {
      return failure(
        action,
        "This iOS tap action is limited to GalaxySSI-owned Agent home controls.",
        code: "IOS_AGENT_HOME_ONLY"
      )
    }
    let requestedOrigin = clean(action.parameters["element_origin"] ?? "")
    guard requestedOrigin.isEmpty || requestedOrigin == AgentElementOrigin.manual.rawValue else {
      return failure(
        action,
        "iOS cannot inject taps into other apps or protected system surfaces.",
        code: "IOS_AGENT_HOME_ONLY"
      )
    }
    return AgentIOSAgentHomeActionBridge.shared.executeTap(action: action)
  }

  private func longPressOwnedAgentHomeElement(
    _ action: AgentAction,
    screen: AgentScreenContext
  ) -> AgentActionResult {
    let requestedBounds = clean(action.parameters["bounds"] ?? "")
    let requestedLabel = clean(action.parameters["matched_label"] ?? "")
    let element = screen.clickableElements.first { candidate in
      candidate.viewId.hasPrefix("ios.agent.") &&
        ((requestedBounds.isEmpty && !requestedLabel.isEmpty && candidate.label == requestedLabel) ||
          (!requestedBounds.isEmpty && candidate.bounds == requestedBounds))
    }
    guard let element,
          element.origin == .manual,
          element.bounds.hasPrefix("logical://AgentHomeView/") else {
      return failure(
        action,
        "This iOS long-press action is limited to GalaxySSI-owned Agent home controls.",
        code: "IOS_AGENT_HOME_LONG_PRESS_ONLY"
      )
    }
    let requestedOrigin = clean(action.parameters["element_origin"] ?? "")
    guard requestedOrigin.isEmpty || requestedOrigin == AgentElementOrigin.manual.rawValue else {
      return failure(
        action,
        "iOS cannot inject long presses into other apps or protected system surfaces.",
        code: "IOS_AGENT_HOME_LONG_PRESS_ONLY"
      )
    }
    return AgentIOSAgentHomeActionBridge.shared.executeLongPress(action: action)
  }

  private func importWebKnowledge(_ action: AgentAction) -> AgentActionResult {
    guard action.parameters["_galaxyssi_long_term_write_allowed"] != "false" else {
      return failure(action, "Private sessions cannot import long-term knowledge.", code: "private_session_knowledge_blocked")
    }
    let url = clean(action.parameters["url"] ?? "")
    guard !url.isEmpty else {
      return failure(action, "No web page URL was provided.", code: "missing_web_url")
    }
    guard let webKnowledgeImporter else {
      return failure(action, "The iOS web knowledge importer is unavailable.", code: "web_importer_unavailable")
    }
    let result = webKnowledgeImporter(url, action.id)
    return AgentActionResult(
      actionId: action.id,
      success: result.success,
      message: result.message,
      metadata: result.metadata
    )
  }

  private func draftPlan(_ action: AgentAction) -> AgentActionResult {
    let isComplete = clean(action.target).caseInsensitiveCompare("task-complete") == .orderedSame
    return success(
      action,
      message: isComplete ? clean(action.description).ifBlank("Task completed") : "",
      metadata: [
        "plan_action": "draft",
        "completion_verified": isComplete.description
      ]
    )
  }

  private func saveScreenKnowledge(_ action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    guard action.parameters["_galaxyssi_long_term_write_allowed"] != "false" else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "Private sessions cannot save long-term screen knowledge."
      )
    }
    guard screen.sensitiveFlagCount == 0 else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "Screen contains sensitive content; knowledge save skipped."
      )
    }
    guard screen.clipboard.sensitiveFlags.isEmpty else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "Clipboard contains sensitive content; knowledge save skipped."
      )
    }
    guard screen.notifications.sensitiveFlags.isEmpty,
          !screen.notifications.items.contains(where: { !$0.sensitiveFlags.isEmpty }) else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "Notifications contain sensitive content; knowledge save skipped."
      )
    }
    guard let knowledgeStore else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "The iOS Agent knowledge store is unavailable."
      )
    }

    let title = clean(screen.pageTitle)
      .ifBlank(clean(screen.foregroundApp))
      .ifBlank("Screen snapshot")
    let content = screenKnowledgeContent(screen, title: title)
    let item = AgentKnowledgeItem(
      kind: .screen,
      title: title,
      content: content,
      source: "screen:\(clean(screen.foregroundApp).ifBlank("ios"))",
      tags: ["screen", clean(screen.foregroundApp), title].filter { !$0.isEmpty },
      summary: String(content.prefix(500))
    )
    _ = knowledgeStore(item)
    return AgentActionResult(
      actionId: action.id,
      success: true,
      message: "Saved screen snapshot to Agent knowledge.",
      metadata: [
        "knowledge_kind": AgentKnowledgeKind.screen.rawValue,
        "knowledge_source": item.source,
        "completion_verified": "true"
      ]
    )
  }

  private func screenKnowledgeContent(_ screen: AgentScreenContext, title: String) -> String {
    var lines = [
      "App: \(clean(screen.foregroundApp).ifBlank("ios"))",
      "Activity: \(clean(screen.activityName).ifBlank("-"))",
      "Page: \(title)",
      "Visible text count: \(screen.visibleTextCount)",
      "Clickable action count: \(screen.clickableNodeCount)",
      "Input field count: \(screen.inputFieldCount)"
    ]
    if !screen.selectedText.isEmpty {
      lines.append("Selected text: \(String(screen.selectedText.prefix(500)))")
    }
    if screen.clipboard.hasText {
      lines.append("Clipboard: \(screen.clipboard.textLength) chars / hash \(screen.clipboard.textHash)")
    }
    if !screen.notifications.items.isEmpty {
      lines.append("Notifications: \(screen.notifications.items.count)")
      lines += screen.notifications.items.prefix(6).map {
        "- \(clean($0.packageName).ifBlank("app")) / \(clean($0.title).ifBlank("-"))"
      }
    }
    if !screen.visibleTexts.isEmpty {
      lines.append("")
      lines.append("Visible text:")
      lines += screen.visibleTexts.prefix(40).map { "- \($0)" }
    }
    return lines.joined(separator: "\n")
  }

  private func readScreen(_ action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    switch clean(action.id).lowercased() {
    case "read-notifications":
      guard screen.notifications.hasAccess else {
        return AgentActionResult(
          actionId: action.id,
          success: false,
          message: "Notification access is not enabled."
        )
      }
      let packages = uniqueStrings(screen.notifications.items
        .map { clean($0.packageName) }
        .filter { !$0.isEmpty }
      )
        .prefix(4)
        .joined(separator: ", ")
        .ifBlank("none")
      let sensitiveCount = screen.notifications.items.filter { !$0.sensitiveFlags.isEmpty }.count
      let categories = Dictionary(
        grouping: screen.notifications.items.map { clean($0.category).ifBlank("app") },
        by: { $0 }
      )
      let categorySummary = categories
        .map { "\($0.key)=\($0.value.count)" }
        .sorted()
        .joined(separator: ", ")
        .ifBlank("none")
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Read \(screen.notifications.items.count) notifications from \(packages); categories=\(categorySummary); sensitive=\(sensitiveCount)"
      )

    case "read-device-status":
      let status = screen.deviceStatus
      let battery = status.batteryPercent >= 0 ? "\(status.batteryPercent)" : "unknown"
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Battery \(battery) / charging=\(status.charging) / powerSave=\(status.powerSaveMode) / network=\(status.network) / storage=\(status.freeStorageMb)MB free",
        metadata: [
          "battery_percent": String(status.batteryPercent),
          "charging": status.charging.description,
          "power_save_mode": status.powerSaveMode.description,
          "network": status.network,
          "free_storage_mb": String(status.freeStorageMb),
          "total_storage_mb": String(status.totalStorageMb),
          "thermal_state": status.thermalState,
          "completion_verified": "true"
        ]
      )

    case "read-clipboard":
      let clipboard = screen.clipboard
      let message: String
      if !clipboard.hasText {
        message = "Clipboard is empty"
      } else if !clipboard.sensitiveFlags.isEmpty {
        message = "Clipboard has \(clipboard.textLength) chars and sensitive flags=\(clipboard.sensitiveFlags.joined(separator: ","))"
      } else {
        message = "Clipboard has \(clipboard.textLength) chars: \(clipboard.preview.ifBlank(clipboard.textHash))"
      }
      return AgentActionResult(actionId: action.id, success: true, message: message)

    case "summarize-screen":
      let page = clean(screen.pageTitle).ifBlank(clean(screen.foregroundApp)).ifBlank("Current screen")
      if screen.sensitiveFlagCount > 0 || !screen.sensitiveFlags.isEmpty {
        return AgentActionResult(
          actionId: action.id,
          success: true,
          message: "Screen \(page) has \(screen.visibleTextCount) text items and sensitive flags=\(screen.sensitiveFlags.joined(separator: ","))"
        )
      }
      let visible = uniqueStrings(screen.visibleTexts
        .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      )
        .prefix(6)
        .map { String($0.prefix(80)) }
        .joined(separator: " | ")
      let focused = screen.selectedText.ifBlank("")
      let suffix = [visible.isEmpty ? "" : "visible=\(visible)", focused.isEmpty ? "" : "selected=\(String(focused.prefix(80)))"]
        .filter { !$0.isEmpty }
        .joined(separator: " / ")
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Screen: \(page) / app=\(clean(screen.foregroundApp).ifBlank("unknown")) / text=\(screen.visibleTextCount) / actions=\(screen.clickableNodeCount) / fields=\(screen.inputFieldCount)\(suffix.isEmpty ? "" : " / \(suffix)")"
      )

    default:
      return AgentActionResult(
        actionId: action.id,
        success: true,
        message: "Read \(screen.visibleTextCount) text items, \(screen.clickableNodeCount) actions, \(screen.inputFieldCount) fields, and \(screen.scrollableRegionCount) scroll regions"
      )
    }
  }

  private func copyScreenText(_ action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    guard screen.sensitiveFlagCount == 0, screen.sensitiveFlags.isEmpty else {
      return AgentActionResult(
        actionId: action.id,
        success: false,
        message: "Screen contains sensitive content; copying was blocked."
      )
    }
    let text = screen.selectedText.ifBlank(screen.visibleTexts.joined(separator: "\n"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return AgentActionResult(actionId: action.id, success: false, message: "No visible screen text is available to copy.")
    }
    UIPasteboard.general.string = String(text.prefix(12_000))
    return AgentActionResult(
      actionId: action.id,
      success: true,
      message: "Copied current screen text to the clipboard.",
      metadata: ["characters": String(min(text.count, 12_000)), "completion_verified": "true"]
    )
  }

  private func openURL(_ action: AgentAction) -> AgentActionResult {
    let raw = clean(action.parameters["url"] ?? action.target)
    guard let url = URL(string: raw),
          let scheme = url.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          url.host?.isEmpty == false else {
      return failure(action, "Only valid HTTP or HTTPS URLs can be opened on iOS.", code: "invalid_url")
    }
    guard handoffProvider.open(url) else {
      return failure(action, "iOS could not hand the URL to an available system handler.", code: "url_handoff_unavailable")
    }
    return success(
      action,
      message: "URL handoff started",
      metadata: [
        "handoff": "ios_url",
        "url_scheme": scheme,
        "completion_verified": "false"
      ]
    )
  }

  private func openApp(_ action: AgentAction) -> AgentActionResult {
    let package = clean(action.parameters["package"] ?? action.target).lowercased()
    guard let scheme = Self.appSchemes[package], let url = URL(string: scheme) else {
      return failure(
        action,
        "iOS does not allow normal apps to launch arbitrary bundle identifiers.",
        code: "arbitrary_app_launch_unavailable"
      )
    }
    guard handoffProvider.open(url) else {
      return failure(action, "The requested iOS app is not available for handoff.", code: "app_handoff_unavailable")
    }
    return success(
      action,
      message: "App handoff started",
      metadata: [
        "handoff": "ios_app",
        "package": package,
        "url_scheme": url.scheme ?? "",
        "completion_verified": "false"
      ]
    )
  }

  private func createNotification(_ action: AgentAction) -> AgentActionResult {
    let title = String(
      clean(action.parameters["title"] ?? "").ifBlank("GalaxySSI Agent").prefix(160)
    )
    let body = String(
      clean(action.parameters["text"] ?? "").ifBlank(action.description).prefix(1_000)
    )
    guard !body.isEmpty else {
      return failure(action, "Notification text is required.", code: "empty_notification_text")
    }

    let identifier = "galaxyssi.agent.notification.\(clean(action.id).ifBlank(UUID().uuidString))"
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.categoryIdentifier = "galaxyssi.agent.local"
    content.threadIdentifier = "galaxyssi.agent"
    content.userInfo = [
      "galaxyssi_action_id": action.id,
      "galaxyssi_destination": "main_app"
    ]

    AgentIOSOwnedNotificationStore.shared.record(
      identifier: identifier,
      title: title,
      body: body,
      category: "agent",
      postedAtMillis: max(0, nowMillis())
    )
    notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    notificationCenter.add(
      UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    )
    return success(
      action,
      message: "Created local notification",
      metadata: [
        "notification_id": identifier,
        "completion_verified": "false",
        "notification_permission_required": "true"
      ]
    )
  }

  private func scheduleAlarmOrTimer(_ action: AgentAction) -> AgentActionResult {
    if ["timer_seconds", "timer_operation", "operation_id"].contains(where: { action.parameters[$0] != nil }) {
      return executeTimer(action)
    }
    let identifier = "galaxyssi.schedule.\(clean(action.id).ifBlank(UUID().uuidString))"
    let content = UNMutableNotificationContent()
    content.title = "GalaxySSI"
    content.sound = .default

    let trigger: UNNotificationTrigger
    let category: String
    let body: String
    if let hour = Int(clean(action.parameters["hour"] ?? "")),
              let minute = Int(clean(action.parameters["minute"] ?? "")),
              (0...23).contains(hour),
              (0...59).contains(minute) {
      let timestamp = nowMillis()
      let now = timestamp > 0 ? Date(timeIntervalSince1970: Double(timestamp) / 1_000) : Date()
      let calendar = Calendar.autoupdatingCurrent
      var components = calendar.dateComponents([.year, .month, .day], from: now)
      components.hour = hour
      components.minute = minute
      components.second = 0
      guard var scheduled = calendar.date(from: components) else {
        return failure(action, "iOS could not construct the requested alarm time.", code: "invalid_alarm_time")
      }
      if scheduled <= now {
        scheduled = calendar.date(byAdding: .day, value: 1, to: scheduled) ?? scheduled
      }
      content.body = "Alarm \(String(format: "%02d:%02d", hour, minute))"
      body = content.body
      category = "alarm"
      let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduled)
      trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
    } else {
      return failure(action, "A valid timer duration or alarm hour and minute are required.", code: "invalid_alarm_request")
    }

    content.categoryIdentifier = "galaxyssi.schedule.\(category)"
    content.threadIdentifier = "galaxyssi.schedule"
    AgentIOSOwnedNotificationStore.shared.record(
      identifier: identifier,
      title: content.title,
      body: body,
      category: category,
      postedAtMillis: max(0, nowMillis())
    )
    notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    notificationCenter.add(
      UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    )
    return success(
      action,
      message: category == "timer" ? "Timer scheduled" : "Alarm scheduled",
      metadata: [
        "schedule": category,
        "notification_id": identifier,
        "completion_verified": "false",
        "notification_permission_required": "true"
      ]
    )
  }

  private func executeTimer(_ action: AgentAction) -> AgentActionResult {
    let conversation = clean(action.parameters["_galaxyssi_conversation_id"] ?? "")
    let turn = clean(action.parameters["_galaxyssi_turn_id"] ?? "")
    let operation = clean(action.parameters["timer_operation"] ?? "").ifBlank("start")
    let explicitId = clean(action.parameters["operation_id"] ?? "")
    guard !conversation.isBlank, !turn.isBlank, action.parameters["hour"] == nil, action.parameters["minute"] == nil else {
      return failure(action, "A phone timer needs a current conversation and turn, without alarm-time fields.",
                     code: "invalid_timer_scope")
    }
    let current = timerStore.current(conversationId: conversation)
    if !explicitId.isEmpty, current?.id.uuidString != explicitId {
      return timerRejection(action, current: current, code: "timer_operation_id_mismatch")
    }
    if operation == "inspect" || operation == "cancel" {
      guard action.parameters["timer_seconds"] == nil, let current,
            !explicitId.isEmpty || current.sourceTurnId == turn else {
        return timerRejection(action, current: current, code: "timer_operation_id_required")
      }
      if operation == "cancel" {
        if current.state == .scheduling {
          reconcilePendingTimer(current, conversation: conversation)
          guard let settled = timerStore.current(conversationId: conversation),
                settled.id == current.id, settled.state != .scheduling else {
            return timerRejection(action, current: current, code: "timer_scheduling_unsettled")
          }
        }
        guard timerStore.update(conversationId: conversation, id: current.id, to: .cancelled) else {
          return timerRejection(action, current: current, code: "timer_not_cancellable")
        }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [current.notificationId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [current.notificationId])
        AgentIOSOwnedNotificationStore.shared.remove(identifier: current.notificationId)
      } else if current.state == .scheduling {
        reconcilePendingTimer(current, conversation: conversation)
      }
      let latest = timerStore.current(conversationId: conversation)
      let observed = latest?.id == current.id ? latest ?? current : current
      if observed.state == .cancelled {
        return cancelledTimerResult(action, record: observed)
      }
      return success(action, message: operation == "cancel" ? "Phone timer cancelled" : "Phone timer state observed",
                     metadata: observed.evidence(now: nowMillis()))
    }
    guard operation == "start", let duration = Int(clean(action.parameters["timer_seconds"] ?? "")),
          (1...604_800).contains(duration) else {
      return failure(action, "Provide a timer duration from 1 to 604800 seconds, or inspect or cancel a known timer.",
                     code: "invalid_timer_request")
    }
    if let current, !explicitId.isEmpty {
      guard current.durationSeconds == duration else {
        return timerRejection(action, current: current, code: "timer_duration_mismatch")
      }
      return timerStartResult(action, record: current)
    }
    switch timerStore.reserve(conversationId: conversation, turnId: turn, duration: duration, now: nowMillis()) {
    case .existing(let record):
      guard record.sourceTurnId == turn, record.durationSeconds == duration else {
        return timerRejection(action, current: record, code: "timer_already_running")
      }
      if record.state == .scheduling { reconcilePendingTimer(record, conversation: conversation) }
      return timerStartResult(action, record: timerStore.current(conversationId: conversation) ?? record)
    case .unavailable:
      return failure(action, "The phone could not save a timer checkpoint.", code: "timer_checkpoint_unavailable")
    case .new(let record):
      return scheduleNewTimer(action, record: record, conversation: conversation)
    }
  }

  private func scheduleNewTimer(_ action: AgentAction, record: AgentIOSTimerCheckpoint, conversation: String) -> AgentActionResult {
    let gate = DispatchSemaphore(value: 0)
    let content = UNMutableNotificationContent()
    content.title = "GalaxySSI"
    content.body = String(clean(action.parameters["label"] ?? action.description).ifBlank("Timer").prefix(160))
    content.sound = .default
    content.categoryIdentifier = "galaxyssi.schedule.timer"
    content.threadIdentifier = "galaxyssi.schedule"
    notificationCenter.getNotificationSettings { settings in
      guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus),
            let current = self.timerStore.current(conversationId: conversation),
            current.id == record.id, current.state == .scheduling else {
        _ = self.timerStore.update(conversationId: conversation, id: record.id, to: .failed)
        gate.signal()
        return
      }
      let remaining = record.deadlineMillis - self.nowMillis()
      guard remaining > 0 else {
        _ = self.timerStore.update(conversationId: conversation, id: record.id, to: .failed)
        gate.signal()
        return
      }
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(remaining) / 1_000, repeats: false)
      self.notificationCenter.add(UNNotificationRequest(identifier: record.notificationId, content: content, trigger: trigger)) { error in
        let saved = self.timerStore.update(conversationId: conversation, id: record.id,
          to: error == nil ? .scheduled : .failed)
        if error == nil && !saved {
          self.notificationCenter.removePendingNotificationRequests(withIdentifiers: [record.notificationId])
        }
        gate.signal()
      }
    }
    _ = gate.wait(timeout: .now() + .milliseconds(750))
    return timerStartResult(action, record: timerStore.current(conversationId: conversation) ?? record)
  }

  private func reconcilePendingTimer(_ record: AgentIOSTimerCheckpoint, conversation: String) {
    let gate = DispatchSemaphore(value: 0)
    notificationCenter.getPendingNotificationRequests { requests in
      if requests.contains(where: { $0.identifier == record.notificationId }) {
        _ = self.timerStore.update(conversationId: conversation, id: record.id, to: .scheduled)
      }
      gate.signal()
    }
    _ = gate.wait(timeout: .now() + .milliseconds(500))
  }

  private func timerStartResult(_ action: AgentAction, record: AgentIOSTimerCheckpoint) -> AgentActionResult {
    let evidence = record.evidence(now: nowMillis())
    if record.state == .scheduled {
      return success(action, message: "Phone timer scheduled", metadata: evidence)
    }
    return AgentActionResult(actionId: action.id, success: false,
      message: "The phone has not verified an active timer. Inspect the existing operation; do not start it again.",
      metadata: evidence.merging(["error_code": "timer_not_verified",
        "dispatch_accepted": record.state == .scheduling ? "unknown" : "false"]) { _, new in new })
  }

  private func cancelledTimerResult(_ action: AgentAction, record: AgentIOSTimerCheckpoint) -> AgentActionResult {
    let gate = DispatchSemaphore(value: 0)
    notificationCenter.getPendingNotificationRequests { requests in
      if !requests.contains(where: { $0.identifier == record.notificationId }) { gate.signal() }
    }
    var evidence = record.evidence(now: nowMillis())
    guard gate.wait(timeout: .now() + .milliseconds(500)) == .success else {
      evidence["error_code"] = "timer_cancellation_unverified"
      return AgentActionResult(actionId: action.id, success: false, message: "Timer cancellation has not been verified.", metadata: evidence)
    }
    evidence["completion_verified"] = "true"
    return success(action, message: "Phone timer cancelled", metadata: evidence)
  }

  private func timerRejection(_ action: AgentAction, current: AgentIOSTimerCheckpoint?, code: String) -> AgentActionResult {
    let detail = current == nil
      ? "No timer exists in this conversation. For a new timer, omit operation_id; iOS generates it."
      : "Inspect the returned operation_id in this conversation. Do not retry a guessed or stale ID."
    let evidence = current?.evidence(now: nowMillis()) ?? [:]
    return AgentActionResult(actionId: action.id, success: false, message: detail,
      metadata: evidence.merging(["error_code": code, "dispatch_accepted": "false", "next_action": detail]) { _, new in new })
  }

  private func success(_ action: AgentAction, message: String, metadata: [String: String]) -> AgentActionResult {
    AgentActionResult(actionId: action.id, success: true, message: message, metadata: metadata)
  }

  private func failure(_ action: AgentAction, _ message: String, code: String) -> AgentActionResult {
    AgentActionResult(
      actionId: action.id,
      success: false,
      message: message,
      metadata: [
        "error_code": code,
        "platform": "ios",
        "completion_verified": "false"
      ]
    )
  }

  private func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func uniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { value in
      let key = value.lowercased()
      guard !seen.contains(key) else { return false }
      seen.insert(key)
      return true
    }
  }

  static func supportsAppHandoff(_ bundleId: String) -> Bool {
    appSchemes[bundleId.lowercased()] != nil
  }

  private static let appSchemes: [String: String] = [
    "com.apple.maps": "maps://",
    "com.apple.mobilecal": "calshow://",
    "com.apple.mobilemail": "message://",
    "com.apple.mobilesafari": "x-web-search://",
    "com.apple.mobileslideshow": "photos-redirect://"
  ]
}
