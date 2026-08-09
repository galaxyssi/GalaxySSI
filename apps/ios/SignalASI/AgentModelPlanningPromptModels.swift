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
    allowsPhoneRuntimeTools: Bool? = nil
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
    self.allowsPhoneRuntimeTools = allowsPhoneRuntimeTools ??
      Self.infersPhoneRuntimeTools(goal: planRequest.goal, requirements: resolvedRequirements)
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
      allowsPhoneRuntimeTools: try container.decodeIfPresent(Bool.self, forKey: .allowsPhoneRuntimeTools)
    )
  }

  private static func infersPhoneRuntimeTools(
    goal: String,
    requirements: AgentTaskRequirements
  ) -> Bool {
    if !requirements.capabilities.isDisjoint(with: [.code, .taskExecution]) {
      return true
    }
    let normalized = goal.lowercased()
    return phoneRuntimeTerms.contains { normalized.contains($0) }
  }

  private static let phoneRuntimeTerms = [
    "build", "compile", "run tests", "create app", "create file", "zip project", "workspace",
    "python", "javascript", "swift", "ffmpeg",
    "\u{7f16}\u{8bd1}", "\u{5f00}\u{53d1}", "\u{8fd0}\u{884c}\u{6d4b}\u{8bd5}",
    "\u{9879}\u{76ee}", "\u{4ee3}\u{7801}"
  ]
}
