import Foundation

enum AgentCollaborationGoalCoverage {
  static let mappingKey = "semantic_goal_mapping"
  static let reviewKey = "semantic_coverage_review"
  static let manifestKey = "semantic_goal_manifest"
  private static let header: Set<String> = ["format", "goal_sha256", "criteria_sha256"]

  private struct Segment: Equatable {
    let kind: String
    let criteria: Set<String>
  }

  private struct Review {
    let target: AgentCollaborationResearchReference
    let segments: [String: Segment]
    let supported: Bool
  }

  private static func reference(_ value: AgentMcpJSONValue?) -> AgentCollaborationResearchReference? {
    guard let row = value?.objectValue, Set(row.keys) == ["object_id", "revision", "sha256"],
          case .int(let revision)? = row["revision"], revision > 0 else { return nil }
    let id = row.string("object_id"), digest = row.string("sha256")
    guard [id, digest].allSatisfy({ $0.utf8.count == 64 &&
      $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }) else { return nil }
    return .init(objectId: id, revision: revision, sha256: digest)
  }

  private static func verdict(_ row: AgentMcpJSONObject) -> Bool? {
    let status = row.string("verdict")
    guard ["supported", "refuted", "not_tested"].contains(status), !row.string("rationale").isBlank,
          let unresolved = row["unresolved"]?.arrayValue,
          unresolved.allSatisfy({ $0.strictStringValue?.isBlank == false }),
          status != "supported" || unresolved.isEmpty else { return nil }
    return status == "supported"
  }

  private static func segments(_ value: AgentMcpJSONValue?, reviewing: Bool,
                               requiresSupport: Bool = false) -> [String: Segment]? {
    guard let entries = value?.arrayValue, !entries.isEmpty else { return nil }
    let keys: Set<String> = reviewing
      ? ["id", "criterion_ids", "rationale", "verdict", "unresolved"] : ["id", "criterion_ids", "rationale"]
    var result: [String: Segment] = [:]
    for item in entries {
      guard let row = item.objectValue, Set(row.keys).subtracting(["coverage_kind"]) == keys,
            let id = row["id"]?.strictStringValue, !id.isBlank, result[id] == nil,
            row["rationale"]?.strictStringValue?.isBlank == false,
            let values = row["criterion_ids"]?.arrayValue else { return nil }
      let kind = (row["coverage_kind"] ?? .string("outcome")).strictStringValue
      guard let kind, ["outcome", "constraint", "context"].contains(kind) else { return nil }
      let criteria = Set(values.compactMap(\.strictStringValue))
      guard criteria.count == values.count, criteria.allSatisfy({ !$0.isBlank }),
            kind != "outcome" || !criteria.isEmpty else { return nil }
      if reviewing {
        guard let supported = verdict(row), !requiresSupport || supported else { return nil }
      }
      result[id] = .init(kind: kind, criteria: criteria)
    }
    return result
  }

  private static func review(_ body: AgentMcpJSONObject) -> Review? {
    guard let row = body[reviewKey]?.objectValue,
          Set(row.keys) == ["target", "segments", "verdict", "rationale", "unresolved"],
          let target = reference(row["target"]), let supported = verdict(row),
          let segments = segments(row["segments"], reviewing: true, requiresSupport: supported) else { return nil }
    return .init(target: target, segments: segments, supported: supported)
  }

  static func reviewTarget(_ body: AgentMcpJSONObject, parents: [AgentCollaborationResearchReference])
    -> AgentCollaborationResearchReference? {
    guard body["acceptance_review"] == nil, let review = review(body), parents == [review.target] else { return nil }
    return review.target
  }

  static func supports(_ body: AgentMcpJSONObject) -> Bool { review(body)?.supported == true }

  static func manifestLinks(_ body: AgentMcpJSONObject, reference target: AgentCollaborationResearchReference) -> Bool {
    guard let manifest = body[manifestKey]?.objectValue,
          manifest["format"] == .string("galaxyssi.semantic-goal-manifest.v1") else { return false }
    if Set(manifest.keys) == header.union(["manifests"]) {
      return manifest["manifests"]?.arrayValue?.contains { reference($0) == target } == true
    }
    guard Set(manifest.keys) == header.union(["parts"]) else { return false }
    return manifest["parts"]?.arrayValue?.contains {
      reference($0.objectValue?["mapping"]) == target || reference($0.objectValue?["review"]) == target
    } == true
  }

  static func reviewIndexPrefix(_ target: AgentCollaborationResearchReference) -> String {
    "semantic-coverage-review:" + AgentMcpJSONCodec.sha256(["id": .string(target.objectId),
      "revision": .int(target.revision), "sha256": .string(target.sha256)]) + ":"
  }

  static func verifies(_ coverage: AgentMcpJSONObject, source: AgentMcpJSONObject, criteria: Set<String>,
                       coordinator: String, current: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?,
                       previousAuthor: (String, Int64) throws -> String?,
                       hasDissent: (AgentCollaborationResearchReference) throws -> Bool) throws -> Bool {
    let goalHash = source.string("goal_sha256"), criteriaHash = source.string("criteria_sha256")
    let sourceIDs = Set((source["segments"]?.arrayValue ?? []).compactMap { $0.objectValue?["id"]?.strictStringValue })
    guard !sourceIDs.isEmpty, !criteria.isEmpty else { return false }
    func matchesHeader(_ row: AgentMcpJSONObject, format: String) -> Bool {
      row["format"] == .string(format) && row["goal_sha256"] == .string(goalHash) && row["criteria_sha256"] == .string(criteriaHash)
    }
    var parts: [AgentMcpJSONValue] = []
    if Set(coverage.keys) == ["manifest"] {
      guard let root = reference(coverage["manifest"]) else { return false }
      var pending = [root]
      var visited = Set<String>()
      while let next = pending.popLast() {
        guard visited.count < 512, visited.insert(next.objectId).inserted,
              let record = try current(next), record.draft.kind == .artifact,
              let manifest = record.draft.body[manifestKey]?.objectValue,
              matchesHeader(manifest, format: "galaxyssi.semantic-goal-manifest.v1") else { return false }
        if Set(manifest.keys) == header.union(["parts"]), let leaves = manifest["parts"]?.arrayValue, !leaves.isEmpty {
          for leaf in leaves {
            guard let row = leaf.objectValue, let mapping = reference(row["mapping"]), let review = reference(row["review"]),
                  record.draft.parents.contains(mapping), record.draft.parents.contains(review) else { return false }
          }
          parts += leaves
        } else if Set(manifest.keys) == header.union(["manifests"]),
                  let children = manifest["manifests"]?.arrayValue, !children.isEmpty {
          for child in children {
            guard let ref = reference(child), record.draft.parents.contains(ref) else { return false }
            pending.append(ref)
          }
        } else { return false }
      }
    } else if Set(coverage.keys) == ["parts"], let listed = coverage["parts"]?.arrayValue {
      parts = listed
    } else { parts = [.object(coverage)] }
    guard !parts.isEmpty, parts.count <= sourceIDs.count else { return false }
    var seen = Set<String>(), mapped = Set<String>(), maps = Set<String>(), authors = Set<String>(), reviewers = Set<String>()
    let stable = AgentTeamProgressPolicy.stableCollaborationMemberId
    for value in parts {
      guard let row = value.objectValue, Set(row.keys) == ["mapping", "review"],
            let mappingRef = reference(row["mapping"]), let reviewRef = reference(row["review"]),
            maps.insert(mappingRef.objectId).inserted,
            let mapping = try current(mappingRef), mapping.draft.kind == .artifact,
            let body = mapping.draft.body[mappingKey]?.objectValue,
            Set(body.keys) == header.union(["segments"]), matchesHeader(body, format: "galaxyssi.semantic-goal-mapping.v1"),
            let assigned = segments(body["segments"], reviewing: false),
            let reviewed = try current(reviewRef), reviewed.draft.kind == .acceptanceReview,
            let check = review(reviewed.draft.body), check.supported, check.target == mappingRef,
            reviewed.draft.parents == [mappingRef], check.segments == assigned,
            !stable(reviewed.authorId).isBlank, stable(reviewed.authorId) != stable(coordinator),
            try !hasDissent(mappingRef) else { return false }
      reviewers.insert(stable(reviewed.authorId))
      authors.insert(stable(mapping.authorId))
      for revision in 1..<mappingRef.revision {
        guard let author = try previousAuthor(mappingRef.objectId, revision), !author.isBlank else { return false }
        authors.insert(stable(author))
      }
      for (id, segment) in assigned {
        guard sourceIDs.contains(id), seen.insert(id).inserted, segment.criteria.isSubset(of: criteria) else { return false }
        if segment.kind == "outcome" { mapped.formUnion(segment.criteria) }
      }
    }
    return seen == sourceIDs && mapped == criteria && reviewers.isDisjoint(with: authors)
  }
}
