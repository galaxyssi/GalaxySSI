import Foundation

struct PreparedCloudModelConversationContext: Equatable {
  var systemPrompt: String
  var turns: [ChatMessage]
  var contextWindowTokens: Int
  var originalEstimatedTokens: Int
  var compactedEstimatedTokens: Int
  var compacted: Bool
}

enum CloudModelConversationContext {
  static func prepare(
    model: CloudModelConfig,
    apiKey: String?,
    turns: [ChatMessage],
    systemPrompt: String,
    contextWindowTokens overrideContextWindowTokens: Int? = nil
  ) -> PreparedCloudModelConversationContext {
    let profile = profile(model: model, apiKey: apiKey)
    let contextWindow = max(4_096, overrideContextWindowTokens ?? profile.contextWindowTokens)
    let outputReserve = min(
      max(512, profile.maxOutputTokens),
      max(512, contextWindow / 2)
    )
    let budget = ConversationContextBudget(
      contextWindowTokens: contextWindow,
      reservedOutputTokens: min(outputReserve, contextWindow - 512),
      minimumRecentGroups: 4,
      maximumSummaryTokens: max(256, min(8_000, contextWindow / 8)),
      maximumMessageCharacters: 16_000
    )
    let compacted = AgentModelContextCompactor.compact(
      agentMessages(turns: turns, systemPrompt: systemPrompt),
      budget: budget
    )
    let systemMessages = compacted.messages
      .filter { $0.role == .system }
      .map(\.text)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return PreparedCloudModelConversationContext(
      systemPrompt: systemMessages.joined(separator: "\n\n").ifBlank(systemPrompt),
      turns: chatMessages(from: compacted.messages, sourceTurns: turns),
      contextWindowTokens: contextWindow,
      originalEstimatedTokens: compacted.originalEstimatedTokens,
      compactedEstimatedTokens: compacted.compactedEstimatedTokens,
      compacted: compacted.compacted
    )
  }

  static func contextWindowTokens(model: CloudModelConfig, apiKey: String?) -> Int {
    max(4_096, profile(model: model, apiKey: apiKey).contextWindowTokens)
  }

  private static func profile(model: CloudModelConfig, apiKey: String?) -> ProviderProfile {
    ProviderProfileCatalog.fromCloudModel(
      resourceId: "",
      provider: model.provider,
      displayName: model.displayName,
      model: model,
      apiKey: apiKey
    )
  }

  private static func agentMessages(turns: [ChatMessage], systemPrompt: String) -> [AgentModelMessage] {
    var messages = [AgentModelMessage.system(systemPrompt)]
    messages.append(contentsOf: turns.filter { !$0.isSystem }.map { turn in
      AgentModelMessage(
        id: turn.id.uuidString,
        role: turn.isMine ? .user : .assistant,
        text: turn.content
      )
    })
    return messages
  }

  private static func chatMessages(
    from messages: [AgentModelMessage],
    sourceTurns: [ChatMessage]
  ) -> [ChatMessage] {
    let contactId = sourceTurns.last?.contactId ?? ""
    let conversationId = sourceTurns.last?.conversationId ?? ""
    return messages.compactMap { message in
      switch message.role {
      case .system, .tool:
        return nil
      case .user, .assistant:
        return ChatMessage(
          contactId: contactId,
          content: message.text,
          isMine: message.role == .user,
          conversationId: conversationId
        )
      }
    }
  }
}
