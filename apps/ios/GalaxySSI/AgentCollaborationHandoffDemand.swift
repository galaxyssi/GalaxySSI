import CryptoKit
import Foundation

enum AgentCollaborationHandoffDemand {
  enum Owner: Equatable { case ready, running }
  static let format = "galaxyssi.work-handoff.v1"
  static let instructions = "For a routine handoff whose summary is sufficient for the declared downstream assignment, " +
    "return JSON with format galaxyssi.work-handoff.v1, summary, and input_tokens containing exact versions you published " +
    "with publish_work_input in this assignment. A token is a receipt, not permission for another assignment to read it. " +
    "If a decision, repair or independent assessment is needed, say so instead of using this routine handoff format."

  static func tokens(_ run: AgentCollaborationGoalWorkRun) -> [String]? {
    guard run.state == .succeeded, run.truncated != true, let output = run.output,
          SHA256.hash(data: Data(output.utf8)).map({ String(format: "%02x", $0) }).joined() == run.outputHash,
          let body = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(output.utf8)),
          Set(body.keys) == ["format", "summary", "input_tokens"], body.string("format") == format,
          let summary = body["summary"]?.strictStringValue, !summary.isBlank,
          let values = body["input_tokens"]?.arrayValue, (1...8).contains(values.count) else { return nil }
    let tokens = values.compactMap(\.strictStringValue)
    guard tokens.count == values.count, Set(tokens).count == tokens.count,
          tokens.allSatisfy(AgentCollaborationWorkInputBindings.validToken) else { return nil }
    return tokens
  }

  static func owner(graph: AgentCollaborationLiveGraph, runs: [String: AgentCollaborationGoalWorkRun],
      specialists: Set<String>, now: Int64, recorded: (AgentCollaborationLiveGraph.Work, [String]) throws -> Bool) rethrows -> Owner? {
    let byID = Dictionary(graph.work.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let states = runs.mapValues { $0.visibleState(now: now) }
    let completionEdges = graph.work.reduce(into: [String: [String]]()) { result, item in
      let pinned = graph.boundInputs(for: item.id)
      result[item.id] = item.depends_on.filter { pinned[$0] == nil }
    }
    func succeeded(_ id: String) -> Bool { states[id] == .succeeded && runs[id]?.truncated != true }
    var ready: [String] = [], active: [String] = []
    for item in graph.work where specialists.contains(item.member) {
      let edges = completionEdges[item.id] ?? []
      guard !edges.isEmpty else { continue }
      if states[item.id] == .running, edges.allSatisfy(succeeded) {
        active.append(contentsOf: edges)
      } else if runs[item.id] == nil, edges.allSatisfy(succeeded) {
        ready.append(contentsOf: edges)
      }
    }
    func ancestors(_ roots: [String]) -> Set<String> {
      var queue = roots, seen = Set<String>(), cursor = 0
      while cursor < queue.count {
        let id = queue[cursor]
        cursor += 1
        guard seen.insert(id).inserted, succeeded(id) else { continue }
        queue.append(contentsOf: (completionEdges[id] ?? []).filter(succeeded))
      }
      return seen
    }
    let running = ancestors(active)
    let owned = running.union(ancestors(ready))
    var required = Set<String>()
    for (id, run) in runs where states[id] != .running {
      guard owned.contains(id), let item = byID[id], item.learning == nil, item.blockerResolution == nil,
            item.probeBinding == nil, item.repair == nil, let tokens = tokens(run),
            try recorded(item, tokens) else { return nil }
      required.insert(id)
    }
    guard !required.isEmpty else { return nil }
    return required.isSubset(of: running) ? .running : .ready
  }
}
