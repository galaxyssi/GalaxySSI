import Foundation

struct AgentAttachmentContinuityReuse {
  var attachments: [GalaxySSIDraftAttachment]
  var stagedAttachments: [AgentStagedAttachment]
}

struct AgentConversationVisualReference: Equatable {
  var turnId: String
  var blocks: [AgentRichBlock]
}

enum AgentConversationAttachmentContinuity {
  private struct PriorTurn {
    var turnId: String
    var blocks: [AgentRichBlock]
  }

  static func resolve(
    conversationId: String,
    currentTurnId: String,
    request: String,
    messages: [ChatMessage]
  ) -> AgentAttachmentContinuityReuse {
    guard let prior = select(messages: messages, currentTurnId: currentTurnId, request: request) else {
      return AgentAttachmentContinuityReuse(attachments: [], stagedAttachments: [])
    }
    let restored = AgentAttachmentWorkspaceStager.restore(
      conversationId: conversationId,
      turnId: prior.turnId,
      blocks: prior.blocks
    )
    return AgentAttachmentContinuityReuse(
      attachments: restored.map(\.attachment),
      stagedAttachments: restored.map(\.staged)
    )
  }

  static func latestVisualReference(
    messages: [ChatMessage],
    currentTurnId: String
  ) -> AgentConversationVisualReference? {
    messages.reversed().compactMap { message -> AgentConversationVisualReference? in
      guard message.isMine,
            !message.isSystem,
            !message.turnId.isEmpty,
            message.turnId != currentTurnId else { return nil }
      let images = AgentRichContentCodec.decode(message.richOutputJson).filter {
        $0.type == .image && $0.metadata["source"] == "user_attachment"
      }
      return images.isEmpty ? nil : AgentConversationVisualReference(turnId: message.turnId, blocks: images)
    }.first
  }

  private static func select(
    messages: [ChatMessage],
    currentTurnId: String,
    request: String
  ) -> PriorTurn? {
    let candidates = messages.reversed().compactMap { message -> PriorTurn? in
      guard message.isMine,
            !message.isSystem,
            !message.turnId.isEmpty,
            message.turnId != currentTurnId else {
        return nil
      }
      let blocks = AgentRichContentCodec.decode(message.richOutputJson).filter {
        attachmentTypes.contains($0.type) && $0.metadata["source"] == "user_attachment"
      }
      return blocks.isEmpty ? nil : PriorTurn(turnId: message.turnId, blocks: blocks)
    }
    guard !candidates.isEmpty else { return nil }
    let currentRequest = currentRequest(request)
    if let named = candidates.first(where: { candidate in
      candidate.blocks.contains { block in
        let name = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && currentRequest.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
    }) {
      return named
    }
    if referencesPriorArtifact(currentRequest) {
      return candidates.first
    }
    if let visual = latestVisualReference(messages: messages, currentTurnId: currentTurnId) {
      return PriorTurn(turnId: visual.turnId, blocks: visual.blocks)
    }
    return nil
  }

  private static func currentRequest(_ value: String) -> String {
    guard let marker = value.range(of: "Current user request:", options: [.caseInsensitive, .backwards]) else {
      return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return String(value[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func referencesPriorArtifact(_ request: String) -> Bool {
    let normalized = request
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !normalized.isEmpty else { return false }
    return continuationTerms.contains { term in
      term.allSatisfy({ $0.isASCII && $0.isLetter })
        ? normalized.range(of: "(?<![a-z0-9])\(NSRegularExpression.escapedPattern(for: term))(?![a-z0-9])", options: .regularExpression) != nil
        : normalized.contains(term)
    }
  }

  private static let attachmentTypes: Set<AgentRichBlockType> = [.image, .file, .video, .audio]
  private static let continuationTerms = [
    "continue", "again", "same", "previous", "above", "this", "that", "it",
    "modify", "edit", "revise", "change", "correct", "fix", "improve",
    "annotate", "mark", "redo", "regenerate", "return", "send", "save",
    "download", "export", "open", "inspect", "analyze", "summarize",
    "translate", "crop", "rotate", "resize", "compress", "image", "photo",
    "file", "document", "attachment", "\u{7ee7}\u{7eed}", "\u{518d}",
    "\u{540c}\u{4e00}", "\u{4e0a}\u{4e00}", "\u{4e4b}\u{524d}",
    "\u{4fee}\u{6539}", "\u{6807}\u{6ce8}", "\u{91cd}\u{505a}",
    "\u{4f18}\u{5316}", "\u{56fe}\u{7247}", "\u{7167}\u{7247}",
    "\u{6587}\u{4ef6}", "\u{6587}\u{6863}", "\u{9644}\u{4ef6}",
    "\u{5206}\u{6790}", "\u{603b}\u{7ed3}", "\u{7ffb}\u{8bd1}",
    "\u{88c1}\u{526a}", "\u{65cb}\u{8f6c}", "\u{538b}\u{7f29}"
  ]
}
