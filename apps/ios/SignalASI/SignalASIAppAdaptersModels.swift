import Foundation
import UIKit

enum SignalASIAppAdapterId: String, CaseIterable, Identifiable {
  case wechat
  case sms
  case phone
  case browser
  case files

  var id: String { rawValue }
}

enum SignalASIAppAdapterAvailability: String {
  case ready
  case limited
  case needsSetup
  case unavailable
}

enum SignalASIAppAdapterTone {
  case accent
  case blue
  case teal
  case orange
  case purple
  case gray
}

struct SignalASIAppAdapterDefinition: Identifiable, Equatable {
  var id: SignalASIAppAdapterId
  var titleKey: String
  var titleFallback: String
  var subtitleKey: String
  var subtitleFallback: String
  var detailKey: String
  var detailFallback: String
  var systemImage: String
  var tone: SignalASIAppAdapterTone
  var launchURLString: String?
  var routeFallback: String
  var capabilityIds: [AgentPhoneCapabilityId]
}

struct SignalASIAppAdapterReadinessCheck: Identifiable, Equatable {
  var id: String
  var titleKey: String
  var titleFallback: String
  var detailKey: String
  var detailFallback: String
  var availability: SignalASIAppAdapterAvailability
}

struct SignalASIAppAdapterStatus: Identifiable, Equatable {
  var id: SignalASIAppAdapterId { definition.id }
  var definition: SignalASIAppAdapterDefinition
  var availability: SignalASIAppAdapterAvailability
  var evidenceKey: String
  var evidenceFallback: String
  var checks: [SignalASIAppAdapterReadinessCheck]

  var isOperational: Bool {
    availability == .ready || availability == .limited
  }

  var launchURL: URL? {
    guard let launchURLString = definition.launchURLString else { return nil }
    return URL(string: launchURLString)
  }
}

struct SignalASIAppAdapterSnapshot: Equatable {
  var statuses: [SignalASIAppAdapterStatus]

  static let empty = SignalASIAppAdapterSnapshot(statuses: [])

  var operationalCount: Int {
    statuses.filter(\.isOperational).count
  }

  var limitedCount: Int {
    statuses.filter { $0.availability == .limited }.count
  }

  var needsSetupCount: Int {
    statuses.filter { $0.availability == .needsSetup }.count
  }
}

enum SignalASIAppAdapterCatalog {
  static var adapterCount: Int { definitions.count }

  static func snapshot(
    screenObservationAllowed: Bool,
    notificationsAuthorized: Bool
  ) -> SignalASIAppAdapterSnapshot {
    SignalASIAppAdapterSnapshot(
      statuses: definitions.map {
        status(
          for: $0,
          screenObservationAllowed: screenObservationAllowed,
          notificationsAuthorized: notificationsAuthorized
        )
      }
    )
  }

  private static let definitions: [SignalASIAppAdapterDefinition] = [
    SignalASIAppAdapterDefinition(
      id: .wechat,
      titleKey: "agent_adapter_wechat",
      titleFallback: "WeChat",
      subtitleKey: "agent_adapter_wechat_subtitle",
      subtitleFallback: "Grounded contact search and draft flow; screen access %@ / notification reply %@",
      detailKey: "signalasi.app_adapters.wechat_detail",
      detailFallback: "The iOS adapter mirrors Android's WeChat flow through URL handoff, clipboard-assisted drafting, screen observation, and explicit user confirmation. iOS cannot silently read or reply through another app.",
      systemImage: "bubble.left.and.bubble.right",
      tone: .accent,
      launchURLString: "weixin://",
      routeFallback: "weixin:// URL handoff",
      capabilityIds: [.installedApps, .intentLaunch, .clipboard, .mediaProjectionOCR, .notificationRead, .notificationReply]
    ),
    SignalASIAppAdapterDefinition(
      id: .sms,
      titleKey: "agent_adapter_sms",
      titleFallback: "SMS",
      subtitleKey: "agent_adapter_sms_subtitle",
      subtitleFallback: "Open the system composer with recipient and message draft; sending remains owner controlled",
      detailKey: "signalasi.app_adapters.sms_detail",
      detailFallback: "SMS execution opens the iOS Messages composer or sms: handoff. SignalASI may prepare recipient and draft context, but the owner completes sending in the system UI.",
      systemImage: "message",
      tone: .blue,
      launchURLString: "sms:",
      routeFallback: "sms: system composer handoff",
      capabilityIds: [.intentLaunch, .installedApps, .notificationReply]
    ),
    SignalASIAppAdapterDefinition(
      id: .phone,
      titleKey: "agent_adapter_phone",
      titleFallback: "Phone",
      subtitleKey: "agent_adapter_phone_subtitle",
      subtitleFallback: "Open the system dialer with a verified number; calls are not placed silently",
      detailKey: "signalasi.app_adapters.phone_detail",
      detailFallback: "Phone execution is limited to a visible tel: dialer handoff. The app validates the target and never places a call without the user completing the system prompt.",
      systemImage: "phone",
      tone: .teal,
      launchURLString: "tel:",
      routeFallback: "tel: system dialer handoff",
      capabilityIds: [.intentLaunch, .installedApps]
    ),
    SignalASIAppAdapterDefinition(
      id: .browser,
      titleKey: "agent_adapter_browser",
      titleFallback: "Browser",
      subtitleKey: "agent_adapter_browser_subtitle",
      subtitleFallback: "Validated HTTP/HTTPS navigation, search, screen understanding, and grounded page actions",
      detailKey: "signalasi.app_adapters.browser_detail",
      detailFallback: "Browser execution validates HTTP and HTTPS URLs before opening Safari or the default browser. Further page understanding stays bounded by explicit screen capture and web content policies.",
      systemImage: "safari",
      tone: .purple,
      launchURLString: "https://signalasi.org",
      routeFallback: "https:// browser handoff",
      capabilityIds: [.network, .intentLaunch, .mediaProjectionOCR]
    ),
    SignalASIAppAdapterDefinition(
      id: .files,
      titleKey: "agent_adapter_files",
      titleFallback: "Files",
      subtitleKey: "agent_adapter_files_subtitle",
      subtitleFallback: "User-selected document access for files, PDFs, and images without broad storage permission",
      detailKey: "signalasi.app_adapters.files_detail",
      detailFallback: "Files execution uses the iOS document picker and security-scoped user selection. SignalASI can process selected files without broad storage enumeration.",
      systemImage: "folder",
      tone: .orange,
      launchURLString: nil,
      routeFallback: "UIDocumentPicker user-selected handoff",
      capabilityIds: [.installedApps, .intentLaunch]
    )
  ]

  private static func status(
    for definition: SignalASIAppAdapterDefinition,
    screenObservationAllowed: Bool,
    notificationsAuthorized: Bool
  ) -> SignalASIAppAdapterStatus {
    switch definition.id {
    case .wechat:
      let schemeVisible = canOpen("weixin://") || canOpen("wechat://")
      let availability: SignalASIAppAdapterAvailability
      let evidenceKey: String
      let evidenceFallback: String
      if schemeVisible && screenObservationAllowed && notificationsAuthorized {
        availability = .limited
        evidenceKey = "signalasi.app_adapters.wechat_limited"
        evidenceFallback = "WeChat handoff is visible; iOS still keeps third-party app control user-visible and bounded."
      } else {
        availability = .needsSetup
        evidenceKey = "signalasi.app_adapters.wechat_needs_setup"
        evidenceFallback = "Install WeChat and enable screen understanding plus notifications before using this adapter."
      }
      return SignalASIAppAdapterStatus(
        definition: definition,
        availability: availability,
        evidenceKey: evidenceKey,
        evidenceFallback: evidenceFallback,
        checks: [
          check(
            id: "wechat.scheme",
            titleKey: "signalasi.app_adapters.check_wechat_installed",
            titleFallback: "WeChat URL handoff",
            detailKey: "signalasi.app_adapters.check_wechat_installed_detail",
            detailFallback: "iOS exposes only declared URL schemes, not a full installed-app list.",
            passed: schemeVisible
          ),
          check(
            id: "wechat.screen",
            titleKey: "signalasi.app_adapters.check_screen_access",
            titleFallback: "Screen understanding",
            detailKey: "signalasi.app_adapters.check_screen_access_detail",
            detailFallback: "Required for grounded contact search and UI verification.",
            passed: screenObservationAllowed
          ),
          check(
            id: "wechat.notifications",
            titleKey: "signalasi.app_adapters.check_notifications",
            titleFallback: "Notification prompts",
            detailKey: "signalasi.app_adapters.check_notifications_detail",
            detailFallback: "Used for SignalASI-owned confirmations and visible reply prompts.",
            passed: notificationsAuthorized
          ),
          limitedCheck(
            id: "wechat.third_party_boundary",
            titleKey: "signalasi.app_adapters.check_third_party_boundary",
            titleFallback: "Third-party app boundary",
            detailKey: "signalasi.app_adapters.check_third_party_boundary_detail",
            detailFallback: "iOS does not allow silent cross-app reading, typing, or notification reply injection."
          )
        ]
      )
    case .sms:
      let canLaunch = canOpen("sms:")
      return simpleStatus(
        definition,
        ready: canLaunch,
        readyKey: "signalasi.app_adapters.sms_ready",
        readyFallback: "The iOS SMS composer route is available.",
        unavailableKey: "signalasi.app_adapters.sms_unavailable",
        unavailableFallback: "This device cannot open the SMS composer route.",
        checks: [
          check(
            id: "sms.route",
            titleKey: "signalasi.app_adapters.check_sms_route",
            titleFallback: "SMS composer",
            detailKey: "signalasi.app_adapters.check_sms_route_detail",
            detailFallback: "The task can be handed to Messages, while final sending remains user-controlled.",
            passed: canLaunch
          ),
          limitedCheck(
            id: "sms.confirmation",
            titleKey: "signalasi.app_adapters.check_owner_send",
            titleFallback: "Owner-controlled send",
            detailKey: "signalasi.app_adapters.check_owner_send_detail",
            detailFallback: "The adapter prepares a draft and never sends silently."
          )
        ]
      )
    case .phone:
      let canLaunch = canOpen("tel:")
      return simpleStatus(
        definition,
        ready: canLaunch,
        readyKey: "signalasi.app_adapters.phone_ready",
        readyFallback: "The iOS dialer route is available.",
        unavailableKey: "signalasi.app_adapters.phone_unavailable",
        unavailableFallback: "This device cannot open the phone dialer route.",
        checks: [
          check(
            id: "phone.route",
            titleKey: "signalasi.app_adapters.check_phone_route",
            titleFallback: "Dialer route",
            detailKey: "signalasi.app_adapters.check_phone_route_detail",
            detailFallback: "The task can prefill a number, but the call must be placed by the user.",
            passed: canLaunch
          ),
          limitedCheck(
            id: "phone.confirmation",
            titleKey: "signalasi.app_adapters.check_owner_call",
            titleFallback: "Owner-controlled call",
            detailKey: "signalasi.app_adapters.check_owner_call_detail",
            detailFallback: "The adapter never starts a call silently."
          )
        ]
      )
    case .browser:
      let canLaunch = canOpen("https://signalasi.org")
      let availability: SignalASIAppAdapterAvailability = canLaunch
        ? (screenObservationAllowed ? .ready : .limited)
        : .unavailable
      return SignalASIAppAdapterStatus(
        definition: definition,
        availability: availability,
        evidenceKey: canLaunch
          ? "signalasi.app_adapters.browser_ready"
          : "signalasi.app_adapters.browser_unavailable",
        evidenceFallback: canLaunch
          ? "HTTP/HTTPS browser handoff is available."
          : "This device cannot open HTTP/HTTPS URLs.",
        checks: [
          check(
            id: "browser.route",
            titleKey: "signalasi.app_adapters.check_browser_route",
            titleFallback: "HTTP/HTTPS route",
            detailKey: "signalasi.app_adapters.check_browser_route_detail",
            detailFallback: "The adapter validates and opens safe web URLs.",
            passed: canLaunch
          ),
          check(
            id: "browser.screen",
            titleKey: "signalasi.app_adapters.check_screen_access",
            titleFallback: "Screen understanding",
            detailKey: "signalasi.app_adapters.check_browser_screen_detail",
            detailFallback: "Needed for grounded page actions after the browser opens.",
            passed: screenObservationAllowed
          )
        ]
      )
    case .files:
      return SignalASIAppAdapterStatus(
        definition: definition,
        availability: .ready,
        evidenceKey: "signalasi.app_adapters.files_ready",
        evidenceFallback: "The iOS document picker is available for user-selected files.",
        checks: [
          check(
            id: "files.picker",
            titleKey: "signalasi.app_adapters.check_file_picker",
            titleFallback: "Document picker",
            detailKey: "signalasi.app_adapters.check_file_picker_detail",
            detailFallback: "Files, PDFs, and images are selected explicitly through system UI.",
            passed: true
          ),
          limitedCheck(
            id: "files.storage_boundary",
            titleKey: "signalasi.app_adapters.check_storage_boundary",
            titleFallback: "Storage boundary",
            detailKey: "signalasi.app_adapters.check_storage_boundary_detail",
            detailFallback: "iOS does not expose broad shared storage enumeration."
          )
        ]
      )
    }
  }

  private static func simpleStatus(
    _ definition: SignalASIAppAdapterDefinition,
    ready: Bool,
    readyKey: String,
    readyFallback: String,
    unavailableKey: String,
    unavailableFallback: String,
    checks: [SignalASIAppAdapterReadinessCheck]
  ) -> SignalASIAppAdapterStatus {
    SignalASIAppAdapterStatus(
      definition: definition,
      availability: ready ? .ready : .unavailable,
      evidenceKey: ready ? readyKey : unavailableKey,
      evidenceFallback: ready ? readyFallback : unavailableFallback,
      checks: checks
    )
  }

  private static func check(
    id: String,
    titleKey: String,
    titleFallback: String,
    detailKey: String,
    detailFallback: String,
    passed: Bool
  ) -> SignalASIAppAdapterReadinessCheck {
    SignalASIAppAdapterReadinessCheck(
      id: id,
      titleKey: titleKey,
      titleFallback: titleFallback,
      detailKey: detailKey,
      detailFallback: detailFallback,
      availability: passed ? .ready : .needsSetup
    )
  }

  private static func limitedCheck(
    id: String,
    titleKey: String,
    titleFallback: String,
    detailKey: String,
    detailFallback: String
  ) -> SignalASIAppAdapterReadinessCheck {
    SignalASIAppAdapterReadinessCheck(
      id: id,
      titleKey: titleKey,
      titleFallback: titleFallback,
      detailKey: detailKey,
      detailFallback: detailFallback,
      availability: .limited
    )
  }

  private static func canOpen(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    return UIApplication.shared.canOpenURL(url)
  }
}
