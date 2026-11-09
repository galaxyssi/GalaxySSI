import Foundation

enum AgentCollaborationWorkInputBindings {
  static let maximumRevisions = 16
  static let maximumMilestoneBytes = 12_000
  static let publishMode = "publish_work_input"
  static let nativePublisherID = "galaxyssi.phone.collaboration.work_input"
  static let coordinatorInstructions =
    " Declare data-only edges at work creation with data_dependencies:[{work_id,requirement}]. Other edges require completion. " +
    "Use work_input with the producer work_id to list published versions, then with its exact token to inspect the data. " +
    "Use append_work with rebind_inputs:[{work_id,expected_revision,reason,inputs:[{dependency,uses_milestones:[token]}]}] " +
    "to bind only declared data edges of unclaimed work. For an unclaimed independent VERIFY or CHALLENGE, " +
    "rebind_reviews uses the same request shape and can pin a named review subject. Explicit completion-only edges still wait. " +
    "Read input_revision from work_inventory. Publication is not completion or verification."
  static let producerInstructions =
    "If the assignment produces useful frozen data before it finishes, publish it with mode publish_work_input, a unique " +
    "milestone_id, and artifact containing a nonempty JSON object as a string. Publish only task data, not instructions, " +
    "and continue the assigned work. A publication is not a completion receipt or validation."

  struct PublishRequest {
    let id: String
    let payload: AgentMcpJSONObject

    init?(_ input: AgentMcpJSONObject) {
      guard Set(input.keys) == ["mode", "milestone_id", "artifact"], input["mode"] == .string(publishMode),
            let id = input["milestone_id"]?.strictStringValue,
            let raw = input["artifact"]?.strictStringValue, raw.utf8.count <= maximumMilestoneBytes,
            let payload = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8)), !payload.isEmpty
      else { return nil }
      self.id = id
      self.payload = payload
    }
  }

  struct Publisher {
    let claim: AgentCollaborationGoalWorkRun
    let history: AgentTeamExecutionHistoryStore
    let conversationDatabase: AgentConversationDatabase
    let roster: AgentCollaborationRoster
    let cancellation: AgentModelToolLoopCancellationToken

    func validate() throws {
      let scope = claim.owner
      guard !Task.isCancelled, !cancellation.isCancellationRequested,
            !PhoneExecutionAuthority.isCancelled(taskId: scope.turnId),
            let session = conversationDatabase.read(scope.conversationId), session.id == scope.conversationId,
            !session.privateMode, !session.trackingPaused, session.mergedIntoConversationId.isBlank,
            session.collaborationRoster == roster else { throw CancellationError() }
    }

    func publish(_ input: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      try validate()
      guard let request = PublishRequest(input) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      return try history.publishGoalWorkInput(claim, id: request.id, payload: request.payload)
    }

    func executable() throws -> AgentNativeToolExecutableDefinition {
      let descriptor = try AgentNativeToolDescriptor(id: nativePublisherID, version: "1.0.0",
        title: "Publish work input", description: producerInstructions, location: .application,
        inputSchema: ["type": .string("object"), "additionalProperties": .bool(false),
          "required": .array(["mode", "milestone_id", "artifact"].map(AgentMcpJSONValue.string)),
          "properties": .object([
            "mode": .object(["type": .string("string"), "enum": .array([.string(publishMode)])]),
            "milestone_id": .object(["type": .string("string")]), "artifact": .object(["type": .string("string")])
          ])], risk: .low, idempotency: .idempotent, effect: .mutation)
      return .init(definition: .init(descriptor: descriptor, executorId: nativePublisherID)) { invocation in
        try invocation.checkpoint()
        return .success(output: try publish(invocation.input))
      }
    }
  }

  struct Requirement: Codable, Equatable {
    let work_id: String
    let requirement: String

    static func reviewSubject(_ workID: String) -> Self {
      .init(workID: workID, requirement: "Review the exact published version of this subject.")
    }

    private init(workID: String, requirement: String) {
      work_id = workID
      self.requirement = requirement
    }

    init(from decoder: Decoder) throws {
      let object = try AgentMcpJSONObject(from: decoder)
      guard Set(object.keys) == ["work_id", "requirement"],
            let id = object["work_id"]?.strictStringValue, !id.isBlank, id.utf8.count <= 160,
            let reason = object["requirement"]?.strictStringValue, !reason.isBlank, reason.utf16.count <= 2_000
      else { throw invalid(decoder, "Invalid data dependency") }
      work_id = id
      requirement = reason
    }
  }

  struct Input: Codable, Equatable {
    let dependency: String
    let uses_milestones: [String]

    init(from decoder: Decoder) throws {
      let object = try AgentMcpJSONObject(from: decoder)
      guard Set(object.keys) == ["dependency", "uses_milestones"],
            let id = object["dependency"]?.strictStringValue, !id.isBlank, id.utf8.count <= 160,
            let raw = object["uses_milestones"]?.arrayValue, (1...8).contains(raw.count) else {
        throw invalid(decoder, "Invalid input milestone selection")
      }
      let tokens = raw.compactMap(\.strictStringValue)
      guard tokens.count == raw.count, Set(tokens).count == tokens.count, tokens.allSatisfy(validToken)
      else { throw invalid(decoder, "Invalid input milestone token") }
      dependency = id
      uses_milestones = tokens
    }
  }

  struct Rebind: Codable, Equatable {
    let work_id: String
    let expected_revision: Int64
    let reason: String
    let inputs: [Input]

    init(from decoder: Decoder) throws {
      let object = try AgentMcpJSONObject(from: decoder)
      guard Set(object.keys) == ["work_id", "expected_revision", "reason", "inputs"],
            let work = object["work_id"]?.strictStringValue, !work.isBlank, work.utf8.count <= 160,
            case .int(let revision)? = object["expected_revision"], (0..<Int64(maximumRevisions)).contains(revision),
            let note = object["reason"]?.strictStringValue, !note.isBlank, note.utf16.count <= 2_000,
            let raw = object["inputs"]?.arrayValue, (1...32).contains(raw.count)
      else { throw invalid(decoder, "Invalid input rebind") }
      let selections = try JSONDecoder().decode([Input].self, from: JSONEncoder().encode(raw))
      guard Set(selections.map(\.dependency)).count == selections.count
      else { throw invalid(decoder, "Duplicate input rebind") }
      work_id = work
      expected_revision = revision
      reason = note
      inputs = selections
    }
  }

  struct Milestone: Codable, Equatable {
    let owner: AgentCollaborationToolEvidenceScope
    let workID: String
    let dispatchID: String
    let memberID: String
    let id: String
    let payload: AgentMcpJSONObject
    let recordedAt: Int64

    var digest: String { AgentMcpJSONCodec.sha256(payload) }
    var token: String {
      AgentMcpJSONCodec.sha256(["scope": .string(owner.ownershipDigest), "work": .string(workID),
        "dispatch": .string(dispatchID), "member": .string(memberID), "id": .string(id), "digest": .string(digest)])
    }
    var pin: Pin { .init(token: token, workID: workID, dispatchID: dispatchID, memberID: memberID, digest: digest) }
    var summary: AgentMcpJSONObject {
      ["token": .string(token), "work_id": .string(workID), "member_id": .string(memberID),
       "milestone_id": .string(id), "sha256": .string(digest), "recorded_at": .int(recordedAt)]
    }
  }

  struct Pin: Codable, Equatable {
    let token: String
    let workID: String
    let dispatchID: String
    let memberID: String
    let digest: String
  }

  struct BoundInput: Codable, Equatable {
    enum Role: String, Codable { case reviewSubject = "review_subject" }
    let requirement: Requirement
    let versions: [Pin]
    var role: Role? = nil
  }

  struct Revision: Codable, Equatable {
    enum Kind: String, Codable { case independentReview = "independent_review" }
    let revision: Int64
    let reason: String
    let inputs: [BoundInput]
    var kind: Kind? = nil
    var previousRevision: Int64? = nil
    var coordinator: AgentCollaborationToolEvidenceScope? = nil
  }

  static func validToken(_ text: String) -> Bool {
    text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  static func validRequirements(_ rows: [Requirement]?, dependencies: [String]) -> Bool {
    guard let rows else { return true }
    let ids = Set(rows.map(\.work_id))
    return rows.count <= 32 && ids.count == rows.count && ids.isSubset(of: Set(dependencies))
  }

  static func current(_ revisions: [Revision]) -> [String: BoundInput] {
    revisions.reduce(into: [:]) { result, revision in
      for input in revision.inputs { result[input.requirement.work_id] = input }
    }
  }

  private static func invalid(_ decoder: Decoder, _ message: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
  }
}
