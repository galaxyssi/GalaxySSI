import Foundation

struct AgentConversationalTeamJob: Codable, Equatable, Identifiable {
  enum State: String, Codable { case queued, running, finished, stopped }
  enum Failure: Error { case invalid, stale, budget, unavailable }
  let id: UUID
  let conversation: String
  let objective: String
  let route: AgentConversationGoal.Route
  var source: AgentLocalTeamReviewSource? = nil
  private(set) var state: State = .queued
  private(set) var calls = 0
  private(set) var revision = 0
  private(set) var answer = ""
  init(id: UUID = UUID(), conversation: String, objective: String, route: AgentConversationGoal.Route) {
    self.id = id; self.conversation = conversation; self.objective = objective; self.route = route
  }
  var active: Bool { state == .queued || state == .running }
  var valid: Bool {
    !conversation.isBlank && conversation.utf8.count <= 512 && !objective.isBlank && objective.utf16.count <= 4_000 &&
      route.valid && (source == nil || source?.valid == true) &&
      (0...AgentConversationalTeamProtocol.maximumCalls).contains(calls) && revision >= 0 && revision < Int.max &&
      (state != .queued || (calls == 0 && revision == 0)) &&
      (state == .finished ? (!answer.isBlank && answer.utf16.count <= 64_000 && !answer.contains("```galaxyssi-rich")) : answer.isEmpty)
  }
  func begin() throws -> Self {
    guard valid, state == .queued else { throw Failure.stale }
    var value = self; value.state = .running; value.revision += 1
    guard value.valid else { throw Failure.invalid }
    return value
  }
  func reserveCall() throws -> Self {
    guard valid, state == .running else { throw Failure.stale }
    guard calls < AgentConversationalTeamProtocol.maximumCalls else { throw Failure.budget }
    var value = self; value.calls += 1; value.revision += 1
    guard value.valid else { throw Failure.invalid }
    return value
  }
  func finish(_ answer: String) throws -> Self {
    guard valid, state == .running else { throw Failure.stale }
    var value = self; value.state = .finished; value.answer = answer; value.revision += 1
    guard value.valid else { throw Failure.invalid }
    return value
  }
  func stop() throws -> Self {
    guard valid, active else { throw Failure.stale }
    var value = self; value.state = .stopped; value.revision += 1
    guard value.valid else { throw Failure.invalid }
    return value
  }
}
