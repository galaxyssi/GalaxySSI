import Foundation

@MainActor
enum AgentConversationalTeamEngine {
  // Providers must cooperate with Task cancellation, including sibling failure and timeout.
  typealias Wire = @Sendable (String, String) async throws -> String
  typealias Contract = AgentConversationalTeamProtocol
  enum Event: Equatable {
    case planning, planAccepted(Int), roleStarted(Int, Int, Contract.Kind), roleCompleted(Int, Int, Contract.Kind)
    case synthesizing, completed, interrupted, stopped
    case auditing(Int, Int)
  }
  struct Outcome: Sendable {
    let answer: String
    let reports: [Contract.Report]
    let calls: Int
    let roleCount: Int
    let correction: String?
    func publicText(disagreementsTitle: String, correctionTitle: String = "Reviewer correction:") -> String {
      let dissent = reports.compactMap { report in report.dissent.map { "- [\(report.role.id)] \($0)" } }
      return answer + (correction.map { "\n\n" + correctionTitle + "\n" + $0 } ?? "") +
        (dissent.isEmpty ? "" : "\n\n" + disagreementsTitle + "\n" + dissent.joined(separator: "\n"))
    }
  }
  nonisolated private static func input(_ stage: String, objective: String, fields: [String: Any] = [:]) throws -> String {
    var payload = fields; payload["stage"] = stage; payload["objective"] = objective
    return String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self)
  }
  nonisolated private static func call(_ system: String, input: String, limit: Int, ask: @escaping Wire) async throws -> String {
    try Task.checkCancellation()
    let reply: String
    do {
      reply = try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask { try await ask(system, input) }
        group.addTask {
          try await Task.sleep(nanoseconds: 120_000_000_000)
          throw Contract.Failure.timeout
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw Contract.Failure.transport }
        return first
      }
    } catch is CancellationError { throw CancellationError() }
      catch let error as Contract.Failure { throw error }
      catch { throw Contract.Failure.transport }
    try Task.checkCancellation()
    guard !reply.isBlank, reply.utf16.count <= limit else { throw Contract.Failure.transport }
    return Contract.trimLineEndings(reply)
  }
  static func run(objective: String, labels: AgentTeamDraftAudit.Labels = .english,
    ask: @escaping Wire, onEvent: (Event) -> Void = { _ in }) async throws -> Outcome {
    guard !objective.isBlank, objective.utf16.count <= 8_000 else { throw Contract.Failure.objective }
    var calls = 0
    func reserveCall() throws {
      guard calls < Contract.maximumCalls else { throw Contract.Failure.budget }
      calls += 1
    }
    do {
      onEvent(.planning)
      try reserveCall()
      let worksheet = AgentTeamComparisonSheet.evaluate(objective)
      let plan = try Contract.plan(await call(Contract.planner, input: input("plan", objective: worksheet?.plannerObjective ?? objective), limit: 6_000, ask: ask))
      let editor = plan.finalEditor, contributors = plan.roles.filter { $0 != editor }
      onEvent(.planAccepted(plan.roles.count))
      let reports = try await withThrowingTaskGroup(of: Contract.Report.self) { group -> [String: Contract.Report] in
        var reports: [String: Contract.Report] = [:], running = Set<String>()
        defer { group.cancelAll() }
        while reports.count < contributors.count {
          try Task.checkCancellation()
          for (index, role) in plan.roles.enumerated() {
            try Task.checkCancellation()
            if running.count == Contract.maximumParallel { break }
            guard role != editor, reports[role.id] == nil, !running.contains(role.id), role.parents.allSatisfy({ reports[$0] != nil }) else { continue }
            let parents = try role.parents.map { parent -> [String: Any] in
              guard let report = reports[parent] else { throw Contract.Failure.stalled }
              return report.json
            }
            let payload = try input("role", objective: objective, fields: ["id": role.id, "kind": role.kind.rawValue,
              "assignment": role.assignment, "reports": parents])
            try reserveCall(); running.insert(role.id)
            onEvent(.roleStarted(index + 1, plan.roles.count, role.kind))
            group.addTask {
              try Contract.report(await call(Contract.worker, input: payload, limit: 5_264, ask: ask), role: role)
            }
          }
          guard !running.isEmpty, let report = try await group.next(), running.remove(report.role.id) != nil else { throw Contract.Failure.stalled }
          reports[report.role.id] = report
          guard let index = plan.roles.firstIndex(of: report.role) else { throw Contract.Failure.stalled }
          onEvent(.roleCompleted(index + 1, plan.roles.count, report.role.kind))
        }
        return reports
      }
      let ordered = try contributors.map { role -> Contract.Report in
        guard let report = reports[role.id] else { throw Contract.Failure.stalled }
        return report
      }
      try Task.checkCancellation()
      onEvent(.synthesizing); try reserveCall()
      var fields: [String: Any] = ["brief": plan.synthesis, "reports": ordered.map(\.json)]
      if let worksheet { fields["verified_table"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(worksheet.evidence)) }
      let payload = try input("synthesis", objective: objective, fields: fields)
      let draft = try Contract.synthesis(await call(Contract.synthesizer, input: payload, limit: 16_064, ask: ask))
      var answer = draft, correction: String?
      if let editor {
        let parents = try editor.parents.map { id -> [String: Any] in
          guard let report = reports[id] else { throw Contract.Failure.stalled }
          return report.json
        }
        var auditFields: [String: Any] = ["id": editor.id, "kind": editor.kind.rawValue, "assignment": editor.assignment,
          "reports": parents, "draft": draft]
        if let worksheet { auditFields["verified_table"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(worksheet.evidence)) }
        let index = (plan.roles.firstIndex(of: editor) ?? 0) + 1
        onEvent(.auditing(index, plan.roles.count)); try reserveCall()
        let raw = try await call(worksheet == nil ? AgentTeamDraftAudit.system : AgentTeamDraftAudit.tableSystem,
          input: input("audit", objective: objective, fields: auditFields), limit: 17_300, ask: ask)
        let reviewed = try AgentTeamDraftAudit.parse(raw, draft: draft, sheet: worksheet, labels: labels)
        answer = reviewed.answer; correction = reviewed.correction
        onEvent(.roleCompleted(index, plan.roles.count, editor.kind))
      }
      try Task.checkCancellation()
      onEvent(.completed)
      return Outcome(answer: answer, reports: ordered, calls: calls, roleCount: plan.roles.count, correction: correction)
    } catch is CancellationError {
      onEvent(.interrupted); throw CancellationError()
    } catch {
      onEvent(.stopped); throw error
    }
  }
}
