import Foundation

struct AgentModelPlanningPromptRequest: Codable, Equatable {
  var planRequest: AgentPlanRequest
  var parsingContext: AgentModelPlanParsingContext
  var conversationContext: AgentConversationContext
  var executionHistory: [AgentAction]
  var globalRealtimeContext: String
  var requirements: AgentTaskRequirements
  var hasAttachments: Bool
  var allowsPhoneRuntimeTools: Bool
  var allowsDirectResponse: Bool

  init(
    planRequest: AgentPlanRequest,
    parsingContext: AgentModelPlanParsingContext = .empty,
    conversationContext: AgentConversationContext = AgentConversationContext(
      conversationId: "",
      summary: "",
      turns: [],
      privateMode: false
    ),
    executionHistory: [AgentAction] = [],
    globalRealtimeContext: String = "",
    requirements: AgentTaskRequirements? = nil,
    hasAttachments: Bool? = nil,
    allowsPhoneRuntimeTools: Bool? = nil,
    allowsDirectResponse: Bool = false
  ) {
    let resolvedRequirements = requirements ?? AgentTaskRequirementAnalyzer.analyze(planRequest.goal)
    let resolvedHasAttachments = hasAttachments ?? conversationContext.hasAttachments
    self.planRequest = planRequest
    self.parsingContext = parsingContext
    self.conversationContext = conversationContext
    self.executionHistory = executionHistory
    self.globalRealtimeContext = String(globalRealtimeContext.prefix(8_000))
    self.requirements = resolvedRequirements
    self.hasAttachments = resolvedHasAttachments
    self.allowsPhoneRuntimeTools = (allowsPhoneRuntimeTools ?? true) &&
      AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: planRequest.goal)
    self.allowsDirectResponse = allowsDirectResponse
  }

  enum CodingKeys: String, CodingKey {
    case planRequest = "plan_request"
    case parsingContext = "parsing_context"
    case conversationContext = "conversation_context"
    case executionHistory = "execution_history"
    case globalRealtimeContext = "global_realtime_context"
    case requirements
    case hasAttachments = "has_attachments"
    case allowsPhoneRuntimeTools = "allows_phone_runtime_tools"
    case allowsDirectResponse = "allows_direct_response"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      planRequest: try container.decode(AgentPlanRequest.self, forKey: .planRequest),
      parsingContext: try container.decodeIfPresent(AgentModelPlanParsingContext.self, forKey: .parsingContext) ?? .empty,
      conversationContext: try container.decodeIfPresent(AgentConversationContext.self, forKey: .conversationContext) ??
        AgentConversationContext(conversationId: "", summary: "", turns: [], privateMode: false),
      executionHistory: try container.decodeIfPresent([AgentAction].self, forKey: .executionHistory) ?? [],
      globalRealtimeContext: try container.decodeIfPresent(String.self, forKey: .globalRealtimeContext) ?? "",
      requirements: try container.decodeIfPresent(AgentTaskRequirements.self, forKey: .requirements),
      hasAttachments: try container.decodeIfPresent(Bool.self, forKey: .hasAttachments),
      allowsPhoneRuntimeTools: try container.decodeIfPresent(Bool.self, forKey: .allowsPhoneRuntimeTools),
      allowsDirectResponse: try container.decodeIfPresent(Bool.self, forKey: .allowsDirectResponse) ?? false
    )
  }
}
