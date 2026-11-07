import Foundation

struct AgentCollaborationCapabilityBank: Codable, Equatable {
  struct Anchor: Codable, Equatable {
    let id: String
    let metric: String
    let direction: String
    let dataset: AgentCollaborationResearchReference
    let repetitions: Int64
    let tolerance: Double
    let value: Double
    let threshold: Double?
    let result: AgentCollaborationResearchReference

    func admits(_ item: AgentMcpJSONObject) -> Bool {
      guard item["purpose"] == .string("regression"),
            item["metric"] == .string(metric), item["direction"] == .string(direction),
            AgentCollaborationExperimentPlanIntake.reference(item["dataset"]) == dataset,
            case .int(let count)? = item["repetitions"], count >= repetitions,
            let allowed = AgentCollaborationExperimentPlanIntake.number(item["tolerance"]),
            allowed >= 0, allowed <= tolerance else { return false }
      return true
    }

    func passes(_ candidate: Double, case item: AgentMcpJSONObject) -> Bool {
      guard candidate.isFinite, admits(item),
            let allowed = AgentCollaborationExperimentPlanIntake.number(item["tolerance"]) else { return false }
      let maximize = direction == "maximize"
      let delta = maximize ? candidate - value : value - candidate
      guard delta.isFinite, delta >= -allowed else { return false }
      return threshold.map { maximize ? candidate >= $0 : candidate <= $0 } ?? true
    }
  }

  let lesson: AgentCollaborationResearchReference
  let previous: AgentCollaborationResearchReference?
  let domain: String
  let environment: String
  let budgetUnit: String
  let anchors: [Anchor]

  func admits(_ spec: AgentMcpJSONObject, domain: String) -> Bool {
    guard self.domain == domain, spec["environment"] == .string(environment),
          spec["budget_unit"] == .string(budgetUnit), !anchors.isEmpty,
          let cases = spec["cases"]?.arrayValue, AgentCollaborationExperimentPlanIntake.validatesCases(cases) else { return false }
    let byID = Dictionary(uniqueKeysWithValues: cases.compactMap(\.objectValue).map { ($0.string("id"), $0) })
    return anchors.allSatisfy { anchor in byID[anchor.id].map(anchor.admits) ?? false }
  }

  static func freeze(
    draft: AgentCollaborationResearchDraft,
    exact: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?
  ) rethrows -> Self? {
    let reference = AgentCollaborationExperimentPlanIntake.reference
    let number = AgentCollaborationExperimentPlanIntake.number
    guard draft.kind == .capabilitySuite, draft.objectId?.isBlank != false, draft.baseRevision == 0,
          draft.observations?.isEmpty != false, let body = draft.body["capability_suite"]?.objectValue,
          Set(body.keys).isSubset(of: ["scope", "limitations", "lesson", "previous_suite"]),
          ["scope", "limitations"].allSatisfy({ body[$0]?.strictStringValue?.isBlank == false }),
          let lessonRef = reference(body["lesson"]), draft.parents.contains(lessonRef),
          let lesson = try exact(lessonRef), lesson.draft.kind == .capabilityLesson,
          let lessonBody = lesson.draft.body["capability_lesson"]?.objectValue,
          lessonBody["decision"] == .string("retain"), lesson.frozenCloudReads?.isEmpty == false,
          let resultRef = reference(lessonBody["result"]), let result = try exact(resultRef),
          result.draft.kind == .experimentResult, let measured = result.measuredCases,
          AgentCollaborationMeasuredCase.supportsRetention(measured), result.frozenCloudReads?.isEmpty == false,
          let planRef = reference(result.draft.body["experiment_result"]?.objectValue?["plan"]),
          let plan = try exact(planRef), plan.draft.kind == .experimentPlan,
          let spec = plan.draft.body["experiment_plan"]?.objectValue,
          let ideaRef = reference(spec["innovation"]), let idea = try exact(ideaRef), idea.draft.kind == .innovation,
          let domain = idea.draft.body["innovation"]?.objectValue?["domain"]?.strictStringValue, !domain.isBlank,
          let environment = spec["environment"]?.strictStringValue, !environment.isBlank,
          let budgetUnit = spec["budget_unit"]?.strictStringValue, !budgetUnit.isBlank,
          let cases = spec["cases"]?.arrayValue, AgentCollaborationExperimentPlanIntake.validatesCases(cases)
    else { return nil }
    let previous: AgentCollaborationResearchReference?
    let inherited: Self?
    if let value = body["previous_suite"] {
      guard let ref = reference(value), draft.parents.contains(ref), reference(spec["retention_suite"]) == ref,
            let record = try exact(ref), record.draft.kind == .capabilitySuite,
            let bank = record.retentionBank, plan.retentionBank == bank, bank.admits(spec, domain: domain)
      else { return nil }
      previous = ref
      inherited = bank
    } else {
      guard spec["retention_suite"] == nil, plan.retentionBank == nil else { return nil }
      previous = nil
      inherited = nil
    }
    let old = inherited?.anchors ?? []
    guard Set(old.map(\.id)).count == old.count, Set(measured.map(\.id)).count == measured.count,
          measured.count == cases.count else { return nil }
    let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
    let measuredByID = Dictionary(uniqueKeysWithValues: measured.map { ($0.id, $0) })
    var anchors: [Anchor] = []
    for raw in cases {
      guard let item = raw.objectValue, let row = measuredByID[item.string("id")],
            row.purpose == item.string("purpose"), let value = row.candidate, value.isFinite,
            let dataset = reference(item["dataset"]), try exact(dataset)?.draft.kind == .artifact,
            case .int(let repetitions)? = item["repetitions"], let tolerance = number(item["tolerance"])
      else { return nil }
      if let existing = oldByID[row.id] {
        guard existing.passes(value, case: item) else { return nil }
        anchors.append(existing)
      } else {
        anchors.append(Anchor(id: row.id, metric: item.string("metric"), direction: item.string("direction"),
          dataset: dataset, repetitions: repetitions, tolerance: tolerance, value: value,
          threshold: row.purpose == "feasibility" ? number(item["threshold"]) : nil, result: resultRef))
      }
    }
    return Self(lesson: lessonRef, previous: previous, domain: domain, environment: environment,
      budgetUnit: budgetUnit, anchors: anchors.sorted { $0.id < $1.id })
  }
}

struct AgentCollaborationCapabilitySelection: Codable, Equatable {
  let implementation: AgentCollaborationResearchReference
  let implementationKind: String
  let lesson: AgentCollaborationResearchReference
  let innovation: AgentCollaborationResearchReference
  let suite: AgentCollaborationResearchReference
  let testedSuite: AgentCollaborationResearchReference
  let domain: String
  let restoredFrom: AgentCollaborationResearchReference?

  var requiresRevalidation: Bool { testedSuite != suite }

  static func resolve(
    _ channel: AgentCollaborationResearchReference,
    implementationKind: String = "tool_release",
    current: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?
  ) rethrows -> Self? {
    guard let record = try current(channel), record.reference == channel,
          record.draft.kind == .capabilityChannel, let selected = record.capabilitySelection,
          selected.implementationKind == implementationKind,
          let implementation = try current(selected.implementation), implementation.draft.kind.rawValue == implementationKind,
          let active = try current(selected.suite)?.retentionBank, active.domain == selected.domain,
          let tested = try current(selected.testedSuite)?.retentionBank, tested.domain == selected.domain,
          tested.lesson == selected.lesson else { return nil }
    var pending = [selected.implementation, selected.lesson, selected.innovation, selected.suite, selected.testedSuite]
    var checked = Set<String>()
    while let ref = pending.popLast() {
      guard let value = try current(ref), value.reference == ref else { return nil }
      guard checked.insert(ref.objectId).inserted else { continue }
      guard checked.count <= 128, pending.count + value.draft.parents.count <= 512 else { return nil }
      pending.append(contentsOf: value.draft.parents)
    }
    return selected
  }

  static func validate(
    draft: AgentCollaborationResearchDraft, objectID: String, head: AgentCollaborationResearchRevision?,
    exact: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?,
    historical: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?,
    implementationKind: (AgentCollaborationResearchReference) throws -> String?
  ) rethrows -> Self? {
    let ref = AgentCollaborationExperimentPlanIntake.reference
    guard draft.kind == .capabilityChannel, draft.observations?.isEmpty != false,
          let body = draft.body["capability_channel"]?.objectValue,
          let reason = body["reason"]?.strictStringValue, !reason.isBlank, reason.utf8.count <= 8_192,
          let operation = body["operation"]?.strictStringValue,
          (head == nil) == (operation == "initialize"),
          head == nil || head?.capabilitySelection != nil else { return nil }
    if operation == "rollback" {
      guard Set(body.keys) == ["operation", "reason", "target_revision"],
            let head, let active = head.capabilitySelection,
            let targetRef = ref(body["target_revision"]), targetRef.objectId == objectID,
            targetRef.revision < head.reference.revision, draft.parents.contains(targetRef),
            let target = try historical(targetRef), target.draft.kind == .capabilityChannel,
            let restored = target.capabilitySelection, restored.domain == active.domain,
            restored.implementationKind == active.implementationKind,
            try implementationKind(restored.implementation) == restored.implementationKind,
            try exact(restored.lesson)?.frozenCloudReads?.isEmpty == false,
            try exact(restored.innovation)?.draft.kind == .innovation,
            try exact(restored.testedSuite)?.retentionBank != nil,
            try exact(active.suite)?.retentionBank != nil else { return nil }
      return Self(implementation: restored.implementation, implementationKind: restored.implementationKind,
        lesson: restored.lesson, innovation: restored.innovation, suite: active.suite,
        testedSuite: restored.testedSuite, domain: active.domain, restoredFrom: targetRef)
    }
    guard ["initialize", "promote"].contains(operation),
          Set(body.keys) == ["operation", "reason", "implementation", "lesson", "suite"],
          let implementation = ref(body["implementation"]), draft.parents.contains(implementation),
          let kind = try implementationKind(implementation),
          let lessonRef = ref(body["lesson"]), draft.parents.contains(lessonRef),
          let lesson = try exact(lessonRef), lesson.draft.kind == .capabilityLesson,
          let lessonBody = lesson.draft.body["capability_lesson"]?.objectValue,
          lessonBody["decision"] == .string("retain"), lesson.frozenCloudReads?.isEmpty == false,
          let resultRef = ref(lessonBody["result"]), let result = try exact(resultRef),
          result.draft.kind == .experimentResult, result.measuredCases.map(AgentCollaborationMeasuredCase.supportsRetention) == true,
          let planRef = ref(result.draft.body["experiment_result"]?.objectValue?["plan"]),
          let plan = try exact(planRef), plan.draft.kind == .experimentPlan,
          let planBody = plan.draft.body["experiment_plan"]?.objectValue,
          let ideaRef = ref(planBody["innovation"]), let idea = try exact(ideaRef), idea.draft.kind == .innovation,
          let ideaBody = idea.draft.body["innovation"]?.objectValue, ref(ideaBody[kind]) == implementation,
          idea.draft.parents.contains(implementation),
          let suiteRef = ref(body["suite"]), draft.parents.contains(suiteRef),
          let suite = try exact(suiteRef), suite.draft.kind == .capabilitySuite,
          let bank = suite.retentionBank, bank.lesson == lessonRef, ideaBody["domain"] == .string(bank.domain)
    else { return nil }
    if kind == "workflow_method" {
      guard let comparison = plan.workflowComparison, comparison.candidate == implementation,
            comparison.baseline != implementation else { return nil }
    }
    if let active = head?.capabilitySelection {
      guard active.implementationKind == kind, active.domain == bank.domain,
            ref(planBody["baseline"]) == active.innovation, ref(planBody["retention_suite"]) == active.suite,
            bank.previous == active.suite, let previous = try exact(active.suite)?.retentionBank,
            bank.anchors.count > previous.anchors.count,
            previous.anchors.allSatisfy({ bank.anchors.contains($0) }) else { return nil }
    }
    return Self(implementation: implementation, implementationKind: kind, lesson: lessonRef,
      innovation: ideaRef, suite: suiteRef, testedSuite: suiteRef, domain: bank.domain, restoredFrom: nil)
  }
}
