import Foundation

struct AgentDirectVisionInvocation: Equatable {
  var modelId: String
  var reasoningEffort: AgentModelReasoningEffort
}

enum AgentDirectVisionPolicy {
  static func instruction(_ attachments: [GalaxySSIDraftAttachment]) -> String {
    instructionForMimeTypes(attachments.map(\.mimeType))
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

  static func appendingCloudInstruction(to prompt: String, images: [CloudImagePayload]) -> String {
    let current = images.filter { $0.historicalSourceTurnId == nil }
    var result = appendingInstruction(to: prompt, mimeTypes: current.map(\.mimeType))
    if current.count != images.count {
      let history = "Historical images are earlier-turn references, not uploads in this request. " +
        "Use them only when relevant to the latest question. Do not restart the earlier task or repeat its answer format."
      if !result.contains(history) { result += (result.isEmpty ? "" : "\n\n") + history }
    }
    if !images.isEmpty {
      let answerStyle = "Check reading orientation internally. Mention orientation only if asked or if ambiguity affects the answer."
      if !result.contains(answerStyle) { result += (result.isEmpty ? "" : "\n\n") + answerStyle }
    }
    return result
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
