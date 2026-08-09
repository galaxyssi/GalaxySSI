import Foundation
import UIKit
import UserNotifications

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

struct AgentIOSNativeActionExecutor: AgentActionExecutor {
  var handoffProvider: AgentIOSNativeActionHandoffProviding
  var notificationCenter: UNUserNotificationCenter
  var nowMillis: () -> Int64

  init(
    handoffProvider: AgentIOSNativeActionHandoffProviding = AgentIOSDefaultNativeActionHandoffProvider(),
    notificationCenter: UNUserNotificationCenter = .current(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.handoffProvider = handoffProvider
    self.notificationCenter = notificationCenter
    self.nowMillis = nowMillis
  }

  func execute(action: AgentAction, screen: AgentScreenContext) -> AgentActionResult {
    switch action.kind {
    case .openURL:
      return openURL(action)
    case .openApp:
      return openApp(action)
    case .setAlarm:
      return scheduleAlarmOrTimer(action)
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

  private func scheduleAlarmOrTimer(_ action: AgentAction) -> AgentActionResult {
    let identifier = "signalasi.schedule.\(clean(action.id).ifBlank(UUID().uuidString))"
    let content = UNMutableNotificationContent()
    content.title = "SignalASI"
    content.sound = .default

    let trigger: UNNotificationTrigger
    let category: String
    let body: String
    if let seconds = Int(clean(action.parameters["timer_seconds"] ?? "")), (1...604_800).contains(seconds) {
      body = clean(action.parameters["label"] ?? action.description).ifBlank("Timer")
      category = "timer"
      content.body = body
      trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
    } else if let hour = Int(clean(action.parameters["hour"] ?? "")),
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

    content.categoryIdentifier = "signalasi.schedule.\(category)"
    content.threadIdentifier = "signalasi.schedule"
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

  private static let appSchemes: [String: String] = [
    "com.apple.maps": "maps://",
    "com.apple.mobilecal": "calshow://",
    "com.apple.mobilemail": "message://",
    "com.apple.mobilesafari": "x-web-search://",
    "com.apple.mobileslideshow": "photos-redirect://"
  ]
}
