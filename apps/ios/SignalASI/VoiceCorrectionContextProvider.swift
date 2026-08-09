import Foundation

struct VoiceCorrectionContextMerge: Equatable {
  var context: AgentConversationContext
  var correctionContext: String
  var injected: Bool
}

struct VoiceCorrectionPlanningContextMerge: Equatable {
  var request: AgentModelPlanningPromptRequest
  var contextMerge: VoiceCorrectionContextMerge
}

enum VoiceCorrectionContextProvider {
  static func merge(
    request: AgentModelPlanningPromptRequest,
    correctionJournal: VoiceCorrectionJournal
  ) -> VoiceCorrectionPlanningContextMerge {
    let contextMerge = merge(
      baseContext: request.conversationContext,
      correctionJournal: correctionJournal
    )
    return VoiceCorrectionPlanningContextMerge(
      request: request.withVoiceCorrectionConversationContext(contextMerge.context),
      contextMerge: contextMerge
    )
  }

  static func merge(
    baseContext: AgentConversationContext,
    correctionJournal: VoiceCorrectionJournal
  ) -> VoiceCorrectionContextMerge {
    merge(
      baseContext: baseContext,
      correctionContext: correctionJournal.contextBlock(conversationId: baseContext.conversationId)
    )
  }

  static func merge(
    baseContext: AgentConversationContext,
    correctionContext: String
  ) -> VoiceCorrectionContextMerge {
    let cleanCorrection = correctionContext.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanCorrection.isEmpty else {
      return VoiceCorrectionContextMerge(
        context: baseContext,
        correctionContext: "",
        injected: false
      )
    }

    var context = baseContext
    context.summary = [context.summary, cleanCorrection]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
    return VoiceCorrectionContextMerge(
      context: context,
      correctionContext: cleanCorrection,
      injected: true
    )
  }
}

private extension AgentModelPlanningPromptRequest {
  func withVoiceCorrectionConversationContext(
    _ conversationContext: AgentConversationContext
  ) -> AgentModelPlanningPromptRequest {
    AgentModelPlanningPromptRequest(
      planRequest: planRequest,
      parsingContext: parsingContext,
      conversationContext: conversationContext,
      executionHistory: executionHistory,
      globalRealtimeContext: globalRealtimeContext,
      requirements: requirements,
      hasAttachments: hasAttachments || conversationContext.hasAttachments,
      allowsPhoneRuntimeTools: allowsPhoneRuntimeTools
    )
  }
}
