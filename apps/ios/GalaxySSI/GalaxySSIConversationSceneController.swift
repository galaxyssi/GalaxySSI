import UIKit

enum GalaxySSIConversationSceneController {
  static let activityType = "com.galaxyssi.chat.ios.conversation-window"
  private static let conversationIDKey = "conversation_id"

  @MainActor
  static var supportsIndependentWindows: Bool {
    UIApplication.shared.supportsMultipleScenes
  }

  @MainActor
  static func open(conversationID: String) {
    let clean = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard supportsIndependentWindows, !clean.isEmpty else { return }
    let activity = NSUserActivity(activityType: activityType)
    activity.title = "GalaxySSI"
    activity.targetContentIdentifier = clean
    activity.userInfo = [conversationIDKey: clean]
    activity.isEligibleForHandoff = false
    UIApplication.shared.requestSceneSessionActivation(
      nil,
      userActivity: activity,
      options: nil,
      errorHandler: nil
    )
  }

  static func conversationID(from activity: NSUserActivity) -> String {
    let stored = activity.userInfo?[conversationIDKey] as? String ?? ""
    let value = stored.ifBlank(activity.targetContentIdentifier ?? "")
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
