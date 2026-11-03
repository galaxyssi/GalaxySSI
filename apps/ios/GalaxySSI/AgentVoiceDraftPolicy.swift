import Foundation

struct AgentVoiceDraftSnapshot: Equatable {
  let conversationID: String
  let text: String
  var dictationOnly = false
  var ownerID: UUID? = nil
}

extension AgentVoiceTranscriptPolicy {
  static func draftSnapshot(conversationID: String, text: String, dictationOnly: Bool = false,
                            ownerID: UUID? = nil) -> AgentVoiceDraftSnapshot? {
    let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard dictationOnly || !draft.isEmpty else { return nil }
    return AgentVoiceDraftSnapshot(
      conversationID: conversationID.trimmingCharacters(in: .whitespacesAndNewlines),
      text: draft,
      dictationOnly: dictationOnly,
      ownerID: ownerID
    )
  }

  static func canApplyDraft(_ snapshot: AgentVoiceDraftSnapshot, conversationID: String, ownerID: UUID?) -> Bool {
    snapshot.conversationID == conversationID && (!snapshot.dictationOnly || snapshot.ownerID == ownerID)
  }

  static func mergeDraftWithTranscript(draft: String, transcript: String) -> String {
    let left = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let right = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !left.isEmpty else { return right }
    guard !right.isEmpty else { return left }
    if left.hasSuffix(",") || left.hasSuffix("\u{FF0C}") {
      return "\(left) \(right)"
    }
    let usesCJKPunctuation = (left + right).unicodeScalars.contains { scalar in
      (0x3400...0x9FFF).contains(scalar.value)
    }
    return usesCJKPunctuation ? "\(left)\u{FF0C}\(right)" : "\(left), \(right)"
  }
}
