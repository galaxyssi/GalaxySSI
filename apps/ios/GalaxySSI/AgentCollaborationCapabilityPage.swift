import CryptoKit
import Foundation

struct AgentCollaborationCapabilityPage {
  private static let directoryKinds: Set<String> = [
    "workflow_method", "executable_tool", "tool_test_plan", "failure_experience", "capability_lesson",
    "capability_suite", "capability_channel", "procedure_skill", "tool_release", "tool_test_comparison"
  ]
  struct Row: Hashable {
    let objectID: String
    let revision: Int64
  }

  struct DirectoryRecord: Decodable {
    let revision: AgentCollaborationResearchRevision?
    private struct DraftHeader: Decodable { let kind: String }
    private enum Key: String, CodingKey { case draft }

    init(from decoder: Decoder) throws {
      let fields = try decoder.container(keyedBy: Key.self)
      let header = try fields.decode(DraftHeader.self, forKey: .draft)
      if header.kind == "tool_release" {
        // Some original release-history receipts have a header but no searchable body.
        revision = try? AgentCollaborationResearchRevision(from: decoder)
      } else {
        revision = try AgentCollaborationResearchRevision(from: decoder)
      }
    }
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
    if original.draft.kind == .toolRelease,
       Self.releaseBinding(original) == nil || (original.turnId == scope.turnId && original.sourceId != scope.sourceId) {
      unavailable.insert(row)
      return nil
    }
    if original.draft.kind == .toolTestComparison,
       original.toolTestComparison == nil || (original.turnId == scope.turnId && original.sourceId != scope.sourceId) {
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

  struct ProcedureMetadata {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    let fields: [(name: String, text: String)]
    var linkedSource: AgentMcpJSONObject?

    func matches(_ term: String) -> Bool {
      fields.contains { $0.text.range(of: term, options: Self.options) != nil }
    }

    func excerpts(terms: [String]) -> AgentMcpJSONObject {
      let candidates = fields.map { field in
        (field, terms.compactMap { field.text.range(of: $0, options: Self.options) }.first)
      }
      let selected = candidates.filter { $0.1 != nil } + candidates.filter { $0.1 == nil }
      return Dictionary(uniqueKeysWithValues: selected.prefix(5).map { field, match in
        let start = match.map {
          field.text.index($0.lowerBound, offsetBy: -48, limitedBy: field.text.startIndex) ?? field.text.startIndex
        } ?? field.text.startIndex
        return (field.name, .string(String(field.text[start...].prefix(180))))
      })
    }
  }

  mutating func procedureMetadata(_ skill: AgentCollaborationResearchRevision) throws -> ProcedureMetadata? {
    guard skill.draft.kind == .procedureSkill, let procedure = skill.retainedProcedure,
          let spec = skill.draft.body["procedure_skill"]?.objectValue else { return nil }
    let inputDescriptions = (spec["inputs"]?.arrayValue ?? []).compactMap { input -> String? in
      guard let item = input.objectValue, let name = item["name"]?.strictStringValue,
            let description = item["description"]?.strictStringValue else { return nil }
      return name + " " + description
    }.joined(separator: "\n")
    var fields = [("title", skill.draft.title), ("name", spec.string("name")), ("domain", procedure.domain),
      ("keywords", Self.searchableMetadata(spec, fields: ["keywords"]).first ?? ""),
      ("limitations", procedure.limitations), ("inputs", inputDescriptions)].filter { !$0.1.isBlank }
    let ref = procedure.lesson
    guard skill.draft.parents.contains(ref),
          spec["lesson"]?.objectValue.flatMap(Self.reference) == ref,
          let lesson = try read(.init(objectID: ref.objectId, revision: ref.revision), matching: ref),
          lesson.turnId != scope.turnId || lesson.sourceId == scope.sourceId,
          lesson.draft.kind == .capabilityLesson, lesson.frozenCloudReads?.isEmpty == false,
          let body = lesson.draft.body["capability_lesson"]?.objectValue, body["decision"] == .string("retain")
    else { return .init(fields: fields) }
    let linked = [("procedure", procedure.method), ("applies_when", procedure.appliesWhen),
      ("avoid_when", procedure.avoidWhen), ("transfer_test", procedure.transferTest)]
    guard linked.allSatisfy({ body[$0.0]?.strictStringValue == $0.1 }) else { return .init(fields: fields) }
    fields += linked
    return .init(fields: fields, linkedSource: [
      "source": .object(AgentCollaborationProcedure.fields(ref)),
      "fields": .array(linked.map { .string($0.0) }), "complete_read": .bool(false)
    ])
  }

  static let releaseState = "eligible_for_scoped_tool_execution"
  private static let toolFields = ["name", "purpose", "environment", "dependencies", "applies_when", "avoid_when", "side_effects"]
  private static let reviewFields = ["review", "applies_when", "avoid_when", "limitations", "authorization_boundary"]

  private static func releaseBinding(_ release: AgentCollaborationResearchRevision)
      -> (source: AgentCollaborationResearchReference, digest: String)? {
    guard release.draft.kind == .toolRelease, let host = release.testedToolRelease,
          host["state"] == .string(releaseState), host["grants_permissions"] != .bool(true),
          let source = AgentCollaborationSavedToolTest.reference(host["executable_tool"]),
          let digest = host["source_sha256"]?.strictStringValue, AgentCollaborationCandidateRecall.validDigest(digest)
    else { return nil }
    return (source, digest)
  }

  struct ReleaseMetadata {
    var fields: [String: String]
    var linked: AgentMcpJSONObject?

    var excerpts: AgentMcpJSONObject {
      fields.mapValues { .string(String($0.prefix(240))) }
    }
  }

  mutating func releaseMetadata(_ release: AgentCollaborationResearchRevision) throws -> ReleaseMetadata? {
    guard let binding = Self.releaseBinding(release),
          let review = release.draft.body["tool_release"]?.objectValue else { return nil }
    var metadata = ReleaseMetadata(fields: Self.fields(review, keys: Self.reviewFields))
    let reference = binding.source
    guard let source = try read(.init(objectID: reference.objectId, revision: reference.revision), matching: reference),
          source.draft.kind == .executableTool,
          source.turnId != scope.turnId || source.sourceId == scope.sourceId,
          let tool = source.draft.body["executable_tool"]?.objectValue,
          let code = tool["source"]?.strictStringValue,
          SHA256.hash(data: Data(code.utf8)).map({ String(format: "%02x", $0) }).joined() == binding.digest
    else { return metadata }
    let fields = Self.fields(tool, keys: Self.toolFields)
    for (key, value) in fields { metadata.fields["tool_" + key] = value }
    if !fields.isEmpty {
      metadata.linked = [
        "source": .object(AgentCollaborationCandidateRecall.reference(reference)), "field_prefix": .string("tool_"),
        "fields": .array(Self.toolFields.filter { fields[$0] != nil }.map(AgentMcpJSONValue.string)),
        "complete_read": .bool(false)
      ]
    }
    return metadata
  }

  private static func fields(_ body: AgentMcpJSONObject, keys: [String]) -> [String: String] {
    keys.reduce(into: [:]) { result, key in
      guard let text = searchableMetadata(body, fields: [key]).first, !text.isBlank else { return }
      result[key] = text
    }
  }
}
