import CoreFoundation
import Foundation

struct AgentSupervisedAnswerPreview: Equatable, Identifiable {
  static let format = "supervised_answer_preview_v1"
  struct Scope: Equatable {
    let token: UUID
    let profile: String
    let owner: String
    let source: Int64
    let route: AgentPairedPhonePlannerRoute
    let identity: AgentTaskIdentity
    let generation: Int64
  }
  let scope: Scope
  let sequence: Int64
  let text: String
  var id: String { scope.owner }

  static func claims(_ payload: [String: Any]) -> Bool {
    payload.string("type") == "agent_task_event" && payload.dictionary("partial_result")?.string("format") == format
  }

  init?(payload: [String: Any], scope: Scope) {
    guard Self.claims(payload), !scope.profile.isBlank, scope.owner.hasPrefix(AgentPairedPhonePlannerRoute.ownerPrefix),
          scope.identity.isComplete, scope.source > 0, scope.source <= 9_007_199_254_740_991,
          scope.route.clientRouteId == scope.identity.clientRouteId,
          AgentRemoteOutcomePolicy.validGeneration(scope.generation),
          payload.string("agent_id") == "codex", payload.string("contact_id") == scope.route.contactId,
          payload.string("desktop_id") == scope.route.desktopId,
          payload.string("client_route_id") == scope.identity.clientRouteId,
          payload.string("conversation_id") == scope.identity.conversationId,
          payload.string("turn_id") == scope.identity.turnId, payload.string("task_id") == scope.identity.taskId,
          Self.source(payload) == scope.source,
          AgentRemoteTaskStatusPolicy.normalize(payload.string("task_status").ifBlank(payload.string("status"))) == "running",
          AgentDesktopReplyRecovery.integer(payload["execution_generation"], minimum: 1) == scope.generation,
          let partial = payload.dictionary("partial_result"), let visible = partial["user_visible"] as? NSNumber,
          CFGetTypeID(visible) == CFBooleanGetTypeID(), visible.boolValue,
          let sequence = AgentDesktopReplyRecovery.integer(partial["sequence"], minimum: 0) else { return nil }
    let text = partial.string("text").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !Self.isControlFragment(text) else { return nil }
    self.scope = scope
    self.sequence = sequence
    self.text = String(text.prefix(64_000))
  }

  static func source(_ payload: [String: Any]) -> Int64? {
    if let text = payload["source_message_id"] as? String {
      guard let source = Int64(text), String(source) == text, source > 0, source <= 9_007_199_254_740_991 else { return nil }
      return source
    }
    return AgentDesktopReplyRecovery.integer(payload["source_message_id"], minimum: 1)
      .flatMap { $0 <= 9_007_199_254_740_991 ? $0 : nil }
  }

  func advances(_ prior: Self?) -> Bool {
    guard let prior else { return true }
    return scope == prior.scope && sequence > prior.sequence
  }

  static func isControlFragment(_ text: String) -> Bool {
    if AgentPublicProgressPolicy.isInternal(text) || CloudSupervisedResearch.hasUnexecutedMarkup(text) ||
      CloudSupervisedResearch.isControlPayload(text) || text.contains("execution_location") { return true }
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("```json") { value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) }
    return value.range(of: #"^\{\s*\"(?:disposition|actions?|completion_requirements|tool_calls|function_call)\"\s*:"#,
      options: .regularExpression) != nil
  }
}
