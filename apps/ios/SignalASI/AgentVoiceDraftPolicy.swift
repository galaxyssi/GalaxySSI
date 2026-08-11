import Foundation

struct AgentVoiceDraftSnapshot: Equatable {
  let conversationID: String
  let text: String
}

extension AgentVoiceTranscriptPolicy {
  static func draftSnapshot(conversationID: String, text: String) -> AgentVoiceDraftSnapshot? {
    let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !draft.isEmpty else { return nil }
    return AgentVoiceDraftSnapshot(
      conversationID: conversationID.trimmingCharacters(in: .whitespacesAndNewlines),
      text: draft
    )
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
