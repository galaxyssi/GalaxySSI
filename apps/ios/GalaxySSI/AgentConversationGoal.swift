import Foundation

enum AgentConversationGoalCommand: Equatable {
  case start(String), resume(String), status, pause, stop, help

  static func parse(_ raw: String) -> Self? {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.prefix(5).lowercased() == "/goal" else { return nil }
    let suffix = clean.dropFirst(5)
    guard suffix.isEmpty || suffix.first?.isWhitespace == true else { return nil }
    let text = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.utf16.count <= 4_000 else { return .help }
    let action = String(text.prefix { !$0.isWhitespace }).lowercased()
    let rest = text.dropFirst(action.count).trimmingCharacters(in: .whitespacesAndNewlines)
    func command(_ key: String) -> Bool {
      let alias = GalaxySSILocalization.string("galaxyssi.conversation_goal.command_" + key,
        fallback: key, language: LanguagePolicySettings.zhCN)
      return action == key || action == alias
    }
    if action.isEmpty || command("status") { return rest.isEmpty ? .status : .help }
    if command("help") { return .help }
    if command("pause") { return rest.isEmpty ? .pause : .help }
    if command("stop") { return rest.isEmpty ? .stop : .help }
    if command("resume") { return .resume(rest) }
    return .start(text)
  }
}

struct AgentConversationGoal: Codable, Equatable, Identifiable {
  static let roundBudget = 6
  enum Phase: String, Codable { case running, paused, blocked, done, stopped }
  enum Issue: String, Codable { case interrupted, repeatedProgress, invalidResponse, providerFailure, conversationUnavailable, routeChanged }
  enum Failure: Error { case invalid, stale, unavailable, interrupted, exhausted }
  struct Route: Codable, Equatable {
    enum Kind: String, Codable { case local, cloud }
    let kind: Kind
    let target: String
    let model: String
    let endpointSHA: String
    let host: String
    var valid: Bool {
      !target.isBlank && target.utf8.count <= 512 && !model.isBlank && model.utf8.count <= 512 &&
        (kind == .local ? (target == "local-llm" && endpointSHA.isEmpty && host.isEmpty) :
          (target != "local-llm" && MqttRouteProtocol.hex(endpointSHA, count: 64) && !host.isBlank && host.utf8.count <= 253))
    }
  }
  let id: UUID
  let conversation: String
  let objective: String
  let route: Route
  private(set) var generation = 1
  private(set) var phase: Phase = .running
  private(set) var rounds = 0
  private(set) var allowance = roundBudget
  private(set) var inFlight = false
  private(set) var checkpoints: [String] = []
  private(set) var next = ""
  private(set) var clarification = ""
  private(set) var revision = 0
  private(set) var review = false
  private(set) var issue: Issue?

  init(id: UUID = UUID(), conversation: String, objective: String, route: Route) {
    self.id = id; self.conversation = conversation; self.objective = objective; self.route = route
  }
  var terminal: Bool { phase == .done || phase == .stopped }
  var valid: Bool {
    !conversation.isBlank && conversation.utf8.count <= 512 && !objective.isBlank && objective.utf16.count <= 4_000 &&
      route.valid && generation > 0 && generation < Int.max && revision >= 0 && revision < Int.max &&
      rounds >= 0 && rounds <= allowance && allowance >= Self.roundBudget && allowance <= Int.max - Self.roundBudget &&
      allowance - rounds <= Self.roundBudget && checkpoints.count <= 16 &&
      checkpoints.allSatisfy { !$0.isBlank && $0.utf16.count <= 12_000 } && next.utf16.count <= 1_000 &&
      clarification.utf16.count <= 4_000 && (!inFlight || phase == .running) &&
      (!review || !checkpoints.isEmpty) && (phase != .done || (!review && !checkpoints.isEmpty))
  }
  func claim() throws -> Self {
    guard valid, phase == .running else { throw Failure.stale }
    guard !inFlight else { throw Failure.interrupted }
    guard rounds < allowance else { throw Failure.exhausted }
    var value = self; value.rounds += 1; value.inFlight = true; value.revision += 1
    guard value.valid else { throw Failure.invalid }
    return value
  }
  func halt(_ issue: Issue) throws -> Self {
    guard valid, !terminal else { throw Failure.stale }
    var value = self; value.phase = .blocked; value.inFlight = false; value.issue = issue; value.revision += 1
    guard value.valid else { throw Failure.invalid }
    return value
  }
  func pause() throws -> Self {
    guard valid, phase == .running else { throw Failure.stale }
    var value = self; value.phase = .paused; value.generation += 1; value.inFlight = false; value.revision += 1
    guard value.valid else { throw Failure.invalid }
    return value
  }
  func stop() throws -> Self {
    guard valid, !terminal else { throw Failure.stale }
    var value = self; value.phase = .stopped; value.generation += 1; value.inFlight = false; value.revision += 1
    guard value.valid else { throw Failure.invalid }
    return value
  }
  func resume(clarification: String) throws -> Self {
    guard valid, [.paused, .blocked].contains(phase), clarification.utf16.count <= 4_000,
      rounds <= Int.max - 2 * Self.roundBudget else { throw Failure.stale }
    var value = self; value.phase = .running; value.generation += 1; value.allowance = rounds + Self.roundBudget
    value.inFlight = false; value.issue = nil; value.revision += 1
    if !clarification.isBlank { value.clarification = clarification }
    guard value.valid else { throw Failure.invalid }
    return value
  }
  func accept(_ raw: String) throws -> Self {
    guard valid, phase == .running, inFlight, raw.utf8.count <= 131_072 else { throw Failure.invalid }
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```"), text.hasSuffix("```"), let newline = text.firstIndex(of: "\n"),
      ["```", "```json"].contains(String(text[..<newline]).lowercased()) {
      text = String(text[text.index(after: newline)...].dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(text.utf8)),
      Set(object.keys) == ["state", "result", "next"], let state = object["state"]?.strictStringValue,
      let rawWork = object["result"]?.strictStringValue, let rawPending = object["next"]?.strictStringValue else { throw Failure.invalid }
    let work = rawWork.trimmingCharacters(in: .whitespacesAndNewlines)
    let pending = rawPending.trimmingCharacters(in: .whitespacesAndNewlines)
    var value = self
    if state == "verified" {
      guard review, !checkpoints.isEmpty, work.isEmpty, pending.isEmpty else { throw Failure.invalid }
      value.phase = .done; value.inFlight = false; value.review = false; value.next = ""; value.issue = nil; value.revision += 1
      guard value.valid else { throw Failure.invalid }
      return value
    }
    guard ["continue", "done", "blocked"].contains(state), !(review && state == "done"),
      work.utf16.count <= 12_000, pending.utf16.count <= 1_000,
      (state == "blocked" || !work.isEmpty), (state == "done" || !pending.isEmpty),
      !work.contains("```galaxyssi-rich"), !pending.contains("```galaxyssi-rich") else { throw Failure.invalid }
    if !work.isEmpty && checkpoints.contains(work) { return try halt(.repeatedProgress) }
    if !work.isEmpty { value.checkpoints.append(work) }
    if value.checkpoints.count > 16 { value.checkpoints = [value.checkpoints[0]] + Array(value.checkpoints.suffix(15)) }
    value.inFlight = false; value.next = pending; value.issue = nil; value.review = state == "done"; value.revision += 1
    if state == "blocked" { value.phase = .blocked }
    else if rounds >= allowance { value.phase = .paused }
    guard value.valid else { throw Failure.invalid }
    return value
  }
}
