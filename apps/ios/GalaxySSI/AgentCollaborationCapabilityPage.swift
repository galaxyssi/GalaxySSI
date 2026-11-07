import Foundation

struct AgentCollaborationCapabilityPage {
  private static let directoryKinds: Set<String> = [
    "workflow_method", "executable_tool", "tool_test_plan", "tool_release", "failure_experience", "capability_lesson",
    "capability_suite", "capability_channel", "procedure_skill"
  ]
  struct Row: Hashable {
    let objectID: String
    let revision: Int64
  }

  private let scope: AgentCollaborationToolEvidenceScope
  private let load: (Row) throws -> AgentCollaborationResearchRevision?
  private var verified: [AgentCollaborationResearchReference: AgentCollaborationResearchRevision] = [:]
  private var references: [Row: AgentCollaborationResearchReference] = [:]
  private var unavailable = Set<Row>()

  init(scope: AgentCollaborationToolEvidenceScope, load: @escaping (Row) throws -> AgentCollaborationResearchRevision?) {
    self.scope = scope
    self.load = load
  }

  mutating func read(_ row: Row, matching expected: AgentCollaborationResearchReference? = nil)
    throws -> AgentCollaborationResearchRevision? {
    if let reference = references[row] {
      return expected == nil || expected == reference ? verified[reference] : nil
    }
    if unavailable.contains(row) { return nil }
    guard let original = try load(row) else {
      unavailable.insert(row)
      return nil
    }
    let reference = original.reference
    guard reference.objectId == row.objectID, reference.revision == row.revision,
          reference.sha256.utf8.count == 64,
          reference.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    guard original.turnId != scope.turnId || (original.runId == scope.runId && original.authorId == scope.memberId) else {
      unavailable.insert(row)
      return nil
    }
    guard Self.directoryKinds.contains(original.draft.kind.rawValue) else {
      unavailable.insert(row)
      return nil
    }
    references[row] = reference
    verified[reference] = original
    return expected == nil || expected == reference ? original : nil
  }

  static func reference(_ value: AgentMcpJSONObject) -> AgentCollaborationResearchReference? {
    let objectID = value.string("object_id")
    let digest = value.string("sha256")
    guard case .int(let revision)? = value["revision"], revision > 0,
          [objectID, digest].allSatisfy({ text in
            text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
          }) else { return nil }
    return .init(objectId: objectID, revision: revision, sha256: digest)
  }

  static func searchableMetadata(_ body: AgentMcpJSONObject, fields: [String]) -> [String] {
    fields.compactMap { name in
      guard let field = body[name] else { return nil }
      return field.strictStringValue ?? field.arrayValue?.compactMap(\.strictStringValue).joined(separator: " ")
    }
  }
}
