import Foundation

struct AgentCollaborationProcedure: Codable, Equatable {
  struct Input: Codable, Equatable {
    let name: String
    let required: Bool
  }

  struct Use: Codable, Equatable {
    let procedure: AgentCollaborationResearchReference
    let inputs: AgentMcpJSONObject
    let applicability: AgentMcpJSONObject
    let failures: [AgentCollaborationResearchReference]
  }

  let lesson: AgentCollaborationResearchReference
  let innovation: AgentCollaborationResearchReference
  let plan: AgentCollaborationResearchReference
  let result: AgentCollaborationResearchReference
  let rollback: AgentCollaborationResearchReference
  let domain: String
  let inputs: [Input]
  let method: String
  let appliesWhen: String
  let avoidWhen: String
  let transferTest: String
  let limitations: String

  private static func text(_ value: AgentMcpJSONValue?, limit: Int = 8_192) -> String? {
    guard let value = value?.strictStringValue, !value.isBlank, value.utf8.count <= limit else { return nil }
    return value
  }

  static func freeze(
    _ draft: AgentCollaborationResearchDraft,
    current: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?
  ) rethrows -> Self? {
    let reference = AgentCollaborationExperimentPlanIntake.reference
    guard draft.kind == .procedureSkill, draft.objectId?.isBlank != false, draft.baseRevision == 0,
          draft.observations?.isEmpty != false, let spec = draft.body["procedure_skill"]?.objectValue,
          Set(spec.keys) == ["name", "keywords", "limitations", "inputs", "lesson"],
          text(spec["name"], limit: 320) != nil, let limitations = text(spec["limitations"]),
          let keywords = spec["keywords"]?.arrayValue, (1...32).contains(keywords.count),
          keywords.allSatisfy({ text($0, limit: 160) != nil }),
          let rawInputs = spec["inputs"]?.arrayValue, rawInputs.count <= 32,
          let lessonRef = reference(spec["lesson"]), draft.parents.contains(lessonRef),
          let lesson = try current(lessonRef), lesson.draft.kind == .capabilityLesson,
          let retained = lesson.draft.body["capability_lesson"]?.objectValue,
          retained["decision"] == .string("retain"), lesson.frozenCloudReads?.isEmpty == false,
          let resultRef = reference(retained["result"]), let result = try current(resultRef),
          result.draft.kind == .experimentResult, result.frozenCloudReads?.isEmpty == false,
          result.measuredCases.map(AgentCollaborationMeasuredCase.supportsRetention) == true,
          let planRef = reference(result.draft.body["experiment_result"]?.objectValue?["plan"]),
          let plan = try current(planRef), plan.draft.kind == .experimentPlan,
          let experiment = plan.draft.body["experiment_plan"]?.objectValue,
          let innovationRef = reference(experiment["innovation"]), let idea = try current(innovationRef),
          idea.draft.kind == .innovation,
          let domain = text(idea.draft.body["innovation"]?.objectValue?["domain"]),
          let rollbackRef = reference(retained["rollback"]), rollbackRef == reference(experiment["baseline"]),
          let rollback = try current(rollbackRef), [.artifact, .innovation, .proposal].contains(rollback.draft.kind),
          let method = text(retained["procedure"]), let applies = text(retained["applies_when"]),
          let avoid = text(retained["avoid_when"]), let transfer = text(retained["transfer_test"])
    else { return nil }
    var names = Set<String>()
    var inputs: [Input] = []
    for entry in rawInputs {
      guard let item = entry.objectValue, Set(item.keys) == ["name", "description", "required"],
            let name = text(item["name"], limit: 80),
            name.range(of: #"\A[A-Za-z][A-Za-z0-9_]*\z"#, options: .regularExpression) != nil,
            names.insert(name).inserted, text(item["description"]) != nil,
            case .bool(let required)? = item["required"] else { return nil }
      inputs.append(.init(name: name, required: required))
    }
    return Self(lesson: lessonRef, innovation: innovationRef, plan: planRef, result: resultRef, rollback: rollbackRef,
      domain: domain, inputs: inputs, method: method, appliesWhen: applies, avoidWhen: avoid,
      transferTest: transfer, limitations: limitations)
  }

  func binding(_ use: Use,
               current: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?,
               visible: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?) rethrows -> AgentMcpJSONObject? {
    guard Set(use.inputs.keys).isSubset(of: Set(inputs.map(\.name))),
          inputs.allSatisfy({ !$0.required || (use.inputs[$0.name] != nil && use.inputs[$0.name] != .null) }),
          AgentMcpJSONCodec.stringify(use.inputs).utf8.count <= 16 * 1_024,
          Set(use.applicability.keys) == ["why", "conditions_checked", "remaining_uncertainty"],
          Self.text(use.applicability["why"]) != nil, Self.text(use.applicability["remaining_uncertainty"]) != nil,
          let checked = use.applicability["conditions_checked"]?.arrayValue, (1...32).contains(checked.count),
          checked.allSatisfy({ Self.text($0, limit: 1_024) != nil }),
          use.failures.count <= 8, Set(use.failures.map(\.objectId)).count == use.failures.count else { return nil }
    for ref in [lesson, innovation, plan, result, rollback] {
      guard try current(ref)?.reference == ref else { return nil }
    }
    var failures: [AgentMcpJSONValue] = []
    for ref in use.failures {
      guard let record = try visible(ref), record.draft.kind == .failureExperience,
            record.frozenCloudReads?.isEmpty == false,
            let experience = record.draft.body["failure_experience"]?.objectValue else { return nil }
      failures.append(.object(["reference": .object(Self.fields(ref)), "experience": .object(experience)]))
    }
    let value: AgentMcpJSONObject = [
      "procedure": .object(Self.fields(use.procedure)), "lesson": .object(Self.fields(lesson)),
      "rollback": .object(Self.fields(rollback)), "inputs": .object(use.inputs), "domain": .string(domain),
      "method": .string(method), "applies_when": .string(appliesWhen), "avoid_when": .string(avoidWhen),
      "transfer_test": .string(transferTest), "limitations": .string(limitations),
      "applicability": .object(use.applicability), "failure_experiences": .array(failures),
      "grants_permissions": .bool(false)
    ]
    return AgentMcpJSONCodec.stringify(value).utf8.count <= 48 * 1_024 ? value : nil
  }

  static func fields(_ ref: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    ["object_id": .string(ref.objectId), "revision": .int(ref.revision), "sha256": .string(ref.sha256)]
  }
}
