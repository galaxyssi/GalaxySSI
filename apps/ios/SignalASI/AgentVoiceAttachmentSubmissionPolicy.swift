import Foundation

enum AgentVoiceAttachmentSubmissionPolicy {
  static func select<T>(
    goalOverride: String?,
    composerAttachments: [T],
    attachmentSnapshot: [T]?
  ) -> [T] {
    attachmentSnapshot ?? (goalOverride == nil ? composerAttachments : [])
  }
}
