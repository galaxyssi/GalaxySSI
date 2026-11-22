import Foundation

struct AgentDirectVisionInvocation: Equatable {
  var modelId: String
  var reasoningEffort: AgentModelReasoningEffort
}

enum AgentDirectVisionPolicy {
  static let attachedInputHeader = "Attached input:"
  static let historicalInputHeader = "Historical visual context (no new attachment in this turn):"
  static let historicalContext = "Historical images are references from earlier turns, not new attachments. Follow the user's current request; do not restart the earlier image task."
  static let checkHistoricalPixels = "If a question requires the original image, inspect its native pixels rather than trusting an earlier assistant guess."
  static let answerStyle = "Check image orientation internally when needed. Do not prefix replies with image orientation, rotation, or verification commentary unless the user asks for it."

  static func instruction(_ attachments: [GalaxySSIDraftAttachment]) -> String {
    let current = attachments.filter { $0.historicalSourceTurnId == nil }
    var parts = [instructionForMimeTypes(current.map(\.mimeType))]
    if attachments.contains(where: { $0.isImage && $0.historicalSourceTurnId != nil }) {
      parts.append(historicalContext)
      parts.append(checkHistoricalPixels)
      if !current.contains(where: \.isImage) { parts.append(answerStyle) }
    }
    return parts.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  static func goalWithAttachmentEvidence(
    userGoal: String, attachments: [GalaxySSIDraftAttachment], evidence: String, hasUserGoal: Bool
  ) -> String {
    guard !attachments.isEmpty else { return userGoal }
    let historicalOnly = attachments.allSatisfy { $0.historicalSourceTurnId != nil }
    let header = historicalOnly ? historicalInputHeader : attachedInputHeader
    var parts = [userGoal, header + "\n" + evidence, instruction(attachments)]
    if !historicalOnly {
      parts.append(hasUserGoal ? "Use the attached content when completing the request." :
        "Inspect the newly attached content, infer the user's most likely intent from the content and conversation, and complete the most helpful relevant action.")
    }
    return parts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n\n")
  }

  // Older checkpoints put host vision guidance before the evidence marker.
  // Remove exact generated suffixes only, never matching words inside the user's request.
  static func userGoalBeforeAttachmentEvidence(_ prefix: String) -> String {
    guard let header = [attachedInputHeader, historicalInputHeader].first(where: { prefix.hasSuffix($0) }) else {
      return prefix
    }
    var goal = String(prefix.dropLast(header.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    let current = instructionForMimeTypes(["image/jpeg"])
    let historical = historicalContext + "\n" + checkHistoricalPixels
    let suffixes = [current + "\n" + historical, historical + "\n" + answerStyle, current]
    for suffix in suffixes where goal.hasSuffix("\n\n" + suffix) {
      goal.removeLast(("\n\n" + suffix).count)
      break
    }
    return goal.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func instructionForMimeTypes(_ mimeTypes: [String]) -> String {
    guard containsImage(mimeTypes) else { return "" }
    return """
    Use each attached image as native visual model input. Do not replace it with locally extracted text.
    Before answering, inspect the image twice. First identify the relevant content and its reading orientation. If the image is sideways or upside down, consider which orientation makes the visible marks, labels, and layout coherent before interpreting them.
    Then verify the answer against connected handwriting, equations, table rows and columns, diagram relationships, or the visible shape, logos, and readable text, as appropriate. Preserve the order and relationships of marks; do not invent characters, operators, or missing entries. Do not infer a product from packaging color or isolated words.
    Treat unrelated prior images and memories as non-evidence. If multiple interpretations remain plausible, state the uncertainty rather than asserting an unsupported result.
    """
  }

  static func appendingInstruction(to prompt: String, mimeTypes: [String]) -> String {
    let guidance = instructionForMimeTypes(mimeTypes)
    guard !guidance.isEmpty, !prompt.contains(guidance) else { return prompt }
    return prompt.isEmpty ? guidance : prompt + "\n\n" + guidance
  }

  static func invocation(
    modelId: String,
    reasoningEffort: AgentModelReasoningEffort,
    mimeTypes: [String]
  ) -> AgentDirectVisionInvocation {
    AgentDirectVisionInvocation(
      modelId: RetiredAgentModelPolicy.availableOrDefault(modelId),
      reasoningEffort: reasoningEffort
    )
  }

  static func containsImage(_ mimeTypes: [String]) -> Bool {
    mimeTypes.contains {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .hasPrefix("image/")
    }
  }
}
