import Foundation

@MainActor
enum AgentConversationalTeamEngine {
  // Providers must cooperate with Task cancellation, including sibling failure and timeout.
  typealias Wire = @Sendable (String, String) async throws -> String
  typealias Contract = AgentConversationalTeamProtocol
  enum Event: Equatable {
    case planning, planAccepted(Int), roleStarted(Int, Int, Contract.Kind), roleCompleted(Int, Int, Contract.Kind)
    case synthesizing, completed, interrupted, stopped
    case auditing(Int, Int), rewriting, rechecking(Int, Int)
  }
  struct Outcome: Sendable {
    let answer: String
    let reports: [Contract.Report]
    let calls: Int
    let roleCount: Int
    let correction: String?
    func publicText(disagreementsTitle: String, correctionTitle: String = "Reviewer correction:") -> String {
      return answer + (correction.map { "\n\n" + correctionTitle + "\n" + $0 } ?? "") +
        Contract.renderObjections(reports.compactMap(\.objection), title: disagreementsTitle)
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
      let finalAuditRequired = AgentConversationalTeamCommand.requestsFinalAudit(objective)
      let planReply = try await call(finalAuditRequired ? Contract.finalReviewPlanner : Contract.planner,
        input: input("plan", objective: worksheet?.plannerObjective ?? objective,
          fields: finalAuditRequired ? ["final_review_required": true] : [:]), limit: 6_000, ask: ask)
      let canonical: String
      if finalAuditRequired { canonical = try AgentTeamPlanWire(constrained: false, finalReview: true).decode(planReply) }
      else { canonical = planReply }
      let plan = try Contract.plan(canonical)
      let editor = plan.finalEditor, contributors = plan.roles.filter { $0 != editor }
      if finalAuditRequired && editor == nil { throw Contract.Failure.finalAuditMissing }
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
      let objections = ordered.compactMap(\.objection)
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
        let additional = objections.filter { !editor.parents.contains($0.id) }
        if !additional.isEmpty { auditFields["additional_objections"] = additional.map(\.json) }
        if let worksheet { auditFields["verified_table"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(worksheet.evidence)) }
        let index = (plan.roles.firstIndex(of: editor) ?? 0) + 1
        onEvent(.auditing(index, plan.roles.count)); try reserveCall()
        let raw = try await call(worksheet == nil ? AgentTeamDraftAudit.system : AgentTeamDraftAudit.tableSystem,
          input: input("audit", objective: objective, fields: auditFields), limit: 17_300, ask: ask)
        let reviewed: AgentTeamDraftAudit.Result
        do { reviewed = try AgentTeamDraftAudit.parse(raw, draft: draft, sheet: worksheet, labels: labels) }
        catch let issue as AgentTeamDraftAudit.Failure {
          switch issue {
          case .withheld, .tableMismatch: throw AgentTeamDraftAudit.Rejected(issue: issue, objections: objections)
          case .invalid: throw issue
          }
        }
        answer = reviewed.answer; correction = reviewed.correction
        if reviewed.requiresHandback {
          guard let objection = reviewed.correction else { throw AgentTeamDraftAudit.Failure.invalid }
          func withhold(_ reason: String) -> AgentTeamDraftAudit.Rejected {
            AgentTeamDraftAudit.Rejected(issue: .withheld(reason), objections: objections)
          }
          // Fund the complete pair before asking the writer; never start an unauditable rewrite.
          guard calls + 2 <= Contract.maximumCalls else { throw withhold(objection) }
          do {
            onEvent(.rewriting); try reserveCall()
            let rewriteFields: [String: Any] = ["brief": plan.synthesis, "reports": ordered.map(\.json),
              "draft": draft, "objection": objection]
            let rawRewrite = try await call(AgentTeamDraftAudit.rewriteSystem,
              input: input("rewrite", objective: objective, fields: rewriteFields), limit: 16_064, ask: ask)
            let candidate = try AgentTeamDraftAudit.replacement(rawRewrite, rejected: draft)
            onEvent(.rechecking(index, plan.roles.count)); try reserveCall()
            auditFields["draft"] = candidate; auditFields["rejected_draft"] = draft; auditFields["objection"] = objection
            let rawRecheck = try await call(AgentTeamDraftAudit.recheckSystem,
              input: input("recheck", objective: objective, fields: auditFields), limit: 1_300, ask: ask)
            try AgentTeamDraftAudit.recheck(rawRecheck)
            answer = candidate
          } catch is CancellationError { throw CancellationError() }
            catch AgentTeamDraftAudit.Failure.withheld(let reason) { throw withhold(reason) }
            catch { throw withhold(objection) }
        }
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
