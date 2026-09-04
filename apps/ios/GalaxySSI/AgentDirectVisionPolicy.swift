import Foundation

struct AgentDirectVisionInvocation: Equatable {
  var modelId: String
  var reasoningEffort: AgentModelReasoningEffort
}

enum AgentDirectVisionPolicy {
  static let textOnlyCodexModelId = "gpt-5.3-codex-spark"
  static let visionFallbackModelId = "gpt-5.6-luna"

  static func instruction(_ attachments: [GalaxySSIDraftAttachment]) -> String {
    instructionForMimeTypes(attachments.map(\.mimeType))
  }

  static func instructionForMimeTypes(_ mimeTypes: [String]) -> String {
    guard containsImage(mimeTypes) else { return "" }
    return """
    Use each attached image as native visual model input. Do not replace it with locally extracted text or use a text-extraction pipeline to identify the object. Before answering, inspect the image twice: first determine the overall object and scene; then verify every category, brand, model, or product claim against the visible shape, logos, and readable text. Do not infer a product from packaging color or isolated words. Treat unrelated prior images and memories as non-evidence. If visible evidence conflicts or is insufficient, give only the supported broader identification and clearly state the uncertainty.
    """
  }

  static func invocation(
    modelId: String,
    reasoningEffort: AgentModelReasoningEffort,
    mimeTypes: [String]
  ) -> AgentDirectVisionInvocation {
    let cleanModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard containsImage(mimeTypes),
          cleanModelId.caseInsensitiveCompare(textOnlyCodexModelId) == .orderedSame else {
      return AgentDirectVisionInvocation(modelId: cleanModelId, reasoningEffort: reasoningEffort)
    }
    return AgentDirectVisionInvocation(modelId: visionFallbackModelId, reasoningEffort: .high)
  }

  static func containsImage(_ mimeTypes: [String]) -> Bool {
    mimeTypes.contains {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .hasPrefix("image/")
    }
  }
}
