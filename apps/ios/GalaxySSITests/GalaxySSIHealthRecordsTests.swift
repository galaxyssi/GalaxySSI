import CoreGraphics
import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import GalaxySSI

final class GalaxySSIHealthRecordsTests: XCTestCase {
  @MainActor
  func testReviewedTargetIsSeparateAndInvalidatesOldReminderAnchors() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "target-fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-300), value: 110,
      unitOverride: "mg/dL", referenceInterval: "70 - 99"))
    try records.setPrivacy(.localCare, enabled: true)
    try records.setHealthOnlinePermission(true)
    try records.reconcileLocalCare(now: now)
    func current() throws -> GalaxySSIHealthCare.Concern {
      try XCTUnwrap(records.load().localCare?.current["glucose"])
    }
    let concernID = try current().id
    _ = try records.openLocalCareDiscussion(id: concernID, metric: .glucose)
    let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
      endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: now)
    let quote = "This fictional source exists only to verify exact test provenance and is not clinical guidance."
    let body = Data("<article><h1>Fixture</h1><p>\(quote) No real health data is present in this test.</p></article>".utf8)
    let review: AgentMcpJSONObject = [
      "mode": .string("INDIVIDUALIZED"), "checks": .array([.object(["field": .string("unit"),
        "operator": .string("EQUALS"), "expected": .string("mg/dL"), "source_index": .int(0)])]),
      "missing_information": .array([]), "conflicts": .array([])
    ]
    let action: AgentMcpJSONObject = ["kind": .string("RECHECK"), "description": .string("Fixture step"),
      "rationale": .string("Synthetic review"), "source_index": .int(0), "due_from": .string(""),
      "due_until": .string(""), "applicability": .object(review)]
    let target: AgentMcpJSONObject = ["field": .string("value"), "low": .string("110"), "high": .string("120"),
      "low_inclusive": .bool(false), "high_inclusive": .bool(true), "unit": .string("mg/dL"),
      "rationale": .string("Synthetic boundary fixture"), "source_index": .int(0), "applicability": .object(review)]
    var badBound = target
    badBound["low"] = .string("1.1e2")
    XCTAssertThrowsError(try GalaxySSIHealthCareTarget.parse(badBound, sourceCount: 1))
    badBound = target
    badBound["high"] = .string("110")
    XCTAssertThrowsError(try GalaxySSIHealthCareTarget.parse(badBound, sourceCount: 1))
    func saveDraft(_ proposed: AgentMcpJSONObject?, actionIncluded: Bool) throws -> GalaxySSIHealthCarePlan.Proposal {
      var approval = try records.prepareLocalCareDiscussion(id: concernID, metric: .glucose, question: "Test draft",
        destinationID: "provider", model: model, credential: "fixture-api-key", proposesPlan: true, now: now)
      let source = GalaxySSIHealthCareEvidence.PublicSource.labResults
      let evidence = try GalaxySSIHealthCareEvidence.fromNativeBody(body, source: source, binding: .init(approval),
        retrievedAt: now, observedAt: now)
      approval.evidence = [evidence]
      let reference: AgentMcpJSONObject = ["title": .string("Fixture"), "url": .string(source.url.absoluteString),
        "version": .string("2026"), "applicability": .string("Fixture only"), "evidence_id": .string(evidence.id.uuidString),
        "quote": .string(quote)]
      var arguments: AgentMcpJSONObject = ["uncertainty": .string("Synthetic"), "sources": .array([.object(reference)]),
        "actions": .array(actionIncluded ? [.object(action)] : [])]
      if let proposed { arguments["target"] = .object(proposed) }
      try records.beginLocalCareDiscussionTurn(approval, now: now)
      try records.saveLocalCarePlan(approval, arguments: arguments, now: now)
      return try XCTUnwrap(records.load().localCarePlans?[approval.id.uuidString])
    }
    let oldPlan = try saveDraft(nil, actionIncluded: true)
    try records.resolveLocalCarePlan(oldPlan, selected: [0], now: now)
    let oldAction = try XCTUnwrap(current().adoptedActions?.first)
    XCTAssertNil(oldAction.targetRevision)
    try records.setReviewRemindersEnabled(true)
    try records.setReviewNotificationPreferences(.init(enabled: true, quietStart: 0, quietEnd: 0))
    func schedule(_ action: GalaxySSIHealthCarePlan.AdoptedAction) throws {
      try records.scheduleLocalCareFollowUp(concernID: concernID, metric: .glucose, actionID: action.id,
        replacing: nil, at: now.addingTimeInterval(3_600), now: now)
    }
    try schedule(oldAction)
    let first = try saveDraft(target, actionIncluded: false)
    XCTAssertNil(try current().target)
    XCTAssertThrowsError(try records.resolveLocalCarePlan(first, selected: [], now: now))
    try records.resolveLocalCarePlan(first, selected: [], acceptTarget: true, now: now)
    let confirmed = try current()
    XCTAssertEqual(confirmed.targetRevision, 1)
    XCTAssertEqual(confirmed.adoptedActions, [oldAction])
    XCTAssertEqual(confirmed.stage, .waitingResults)
    XCTAssertEqual(records.localCareTargetComparison(confirmed, now: now), .below)
    XCTAssertNil(try records.load().localCareFollowUps?[oldAction.id])
    XCTAssertThrowsError(try schedule(oldAction))

    var inclusive = target
    inclusive["low_inclusive"] = .bool(true)
    let replacement = try saveDraft(inclusive, actionIncluded: true)
    try records.resolveLocalCarePlan(replacement, selected: [0], acceptTarget: true, now: now)
    let replaced = try current()
    let newAction = try XCTUnwrap(replaced.adoptedActions?.last)
    XCTAssertEqual(newAction.targetRevision, 2)
    XCTAssertEqual(records.localCareTargetComparison(replaced, now: now), .within)
    XCTAssertEqual(replaced.stage, .waitingResults)
    try schedule(newAction)
    try records.revokeLocalCareTarget(replaced, now: now)
    XCTAssertNil(try current().target)
    XCTAssertEqual(try current().targetRevision, 3)
    XCTAssertNil(try records.load().localCareFollowUps?[newAction.id])
    XCTAssertThrowsError(try schedule(newAction))
    XCTAssertTrue(try records.localCareHistory(concernID).contains { $0.target?.numeric != nil })

    let fresh = try saveDraft(inclusive, actionIncluded: false)
    try records.resolveLocalCarePlan(fresh, selected: [], acceptTarget: true, now: now)
    try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-30), value: 112,
      unitOverride: "mg/dL", referenceInterval: "70 - 99"))
    try records.reconcileLocalCare(now: now)
    XCTAssertEqual(records.localCareTargetComparison(try current(), now: now), .reviewRequired)
    XCTAssertEqual(try current().stage, .reassess)
  }

  func testRecordedBloodPressureWarningUsesEitherComponentWithoutConversionRounding() throws {
    let policy = GalaxySSIHealthCarePriority.self
    func reading(_ top: String, _ bottom: String, unit: String = "mmHg") throws -> GalaxySSIHealthReading {
      .init(metric: .bloodPressure, value: try XCTUnwrap(Decimal(string: top)),
        diastolic: try XCTUnwrap(Decimal(string: bottom)), unitOverride: unit)
    }
    XCTAssertNil(policy.evaluate(try reading("180", "120")))
    XCTAssertNotNil(policy.evaluate(try reading("181", "90")))
    XCTAssertNotNil(policy.evaluate(try reading("170", "121")))
    XCTAssertNil(policy.evaluate(try reading("23.998032", "15.998688", unit: "kPa")))
    XCTAssertNotNil(policy.evaluate(try reading("23.998033", "15", unit: "kPa")))
    XCTAssertNotNil(policy.evaluate(try reading("20", "15.998689", unit: "kPa")))
    XCTAssertNil(policy.evaluate(try reading("20", "16", unit: "unknown")))
  }

  @MainActor
  func testBloodPressureWarningAcknowledgmentIsVersionBoundAndLeavesOtherConcernsUnchanged() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "priority-fixture", secrets: secrets, isolatedFile: file)
    let now = Date()
    try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-100), value: 110,
      unitOverride: "mg/dL", referenceInterval: "70 - 99"))
    let bp = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now.addingTimeInterval(-86_400),
      value: 170, diastolic: 121)
    try records.write(bp)
    XCTAssertThrowsError(try records.reconcileLocalCare(now: now))
    try records.setPrivacy(.localCare, enabled: true)
    try records.reconcileLocalCare(now: now)
    let archive = try records.load()
    let ledger = try XCTUnwrap(archive.localCare)
    let ordinary = try XCTUnwrap(ledger.current["glucose"])
    let (_, warning) = try XCTUnwrap(GalaxySSIHealthRecords.currentCareBloodPressureWarning(archive, now: now))
    XCTAssertEqual(warning.record.id, bp.id)
    XCTAssertEqual(warning.handoff.currentSymptoms, "unknown")
    XCTAssertFalse(warning.handoff.currentEmergencyEstablished)
    let first = GalaxySSIHealthCarePriority.page(Array(ledger.current.values), acknowledged: nil, limit: 1)
    XCTAssertEqual(first.rows.first?.metric, .bloodPressure)
    let cursor = try XCTUnwrap(first.next)
    let rest = GalaxySSIHealthCarePriority.page(Array(ledger.current.values), acknowledged: nil, after: cursor)
    XCTAssertEqual(rest.rows.map(\.id), [ordinary.id])
    try records.acknowledgeLocalCareBloodPressure(warning, now: now)
    let reopened = GalaxySSIHealthRecords(owner: "priority-fixture", secrets: secrets, isolatedFile: file)
    XCTAssertEqual(try reopened.load().localCare?.acknowledgedBloodPressure, warning.record)

    var correction = try XCTUnwrap(reopened.load().current.first(where: { $0.id == bp.id }))
    correction.value = 171
    try reopened.write(correction)
    XCTAssertNil(try GalaxySSIHealthRecords.currentCareBloodPressureWarning(reopened.load(), now: now))
    XCTAssertThrowsError(try reopened.acknowledgeLocalCareBloodPressure(warning, now: now))
    try reopened.reconcileLocalCare(now: now)
    let updated = try reopened.load()
    let (_, replacement) = try XCTUnwrap(GalaxySSIHealthRecords.currentCareBloodPressureWarning(updated, now: now))
    XCTAssertEqual(replacement.record.id, warning.record.id)
    XCTAssertNotEqual(replacement.record.revision, warning.record.revision)
    XCTAssertNotEqual(updated.localCare?.acknowledgedBloodPressure, replacement.record)
    XCTAssertEqual(updated.localCare?.current["glucose"], ordinary)

    try reopened.write(.init(metric: .bloodPressure, measuredAt: now.addingTimeInterval(-50), value: 130, diastolic: 80))
    try reopened.reconcileLocalCare(now: now)
    XCTAssertNil(try GalaxySSIHealthRecords.currentCareBloodPressureWarning(reopened.load(), now: now))
    XCTAssertEqual(try reopened.load().localCare?.current["glucose"], ordinary)
  }

  @MainActor
  func testLocalCareComparisonFencesCorrectionsBackfillAndPrivateSourceIdentity() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "comparison-fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let origin = "private-sensor-fixture"
    let first = GalaxySSIHealthReading(metric: .glucose, measuredAt: now.addingTimeInterval(-3 * 86_400),
      value: 110, conditions: "private condition fixture", unitOverride: "mg/dL", referenceInterval: "70 - 99",
      healthKitSource: .init(key: "private-source-1", origin: origin, name: nil))
    try records.write(first)
    try records.setPrivacy(.localCare, enabled: true)
    try records.setHealthOnlinePermission(true)
    try records.reconcileLocalCare(now: now)
    let initial = try XCTUnwrap(records.load().localCare?.current["glucose"])
    try records.setLocalCareContext(initial, applicability: .applicable, now: now)
    _ = try records.openLocalCareDiscussion(id: initial.id, metric: .glucose)
    let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
      endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: now)
    func approval() throws -> GalaxySSIHealthCareDiscussion.Approval {
      try records.prepareLocalCareDiscussion(id: initial.id, metric: .glucose, question: "Compare the available readings",
        destinationID: "provider", model: model, credential: "fixture-api-key", now: now)
    }
    let previous = try approval()
    try records.beginLocalCareDiscussionTurn(previous, now: now)
    try records.finishLocalCareDiscussionTurn(previous, answer: "Private old response marker", now: now)
    let stale = try approval()
    let second = GalaxySSIHealthReading(metric: .glucose, measuredAt: now.addingTimeInterval(-300), value: 100,
      conditions: "different condition fixture", unitOverride: "mg/dL", referenceInterval: "70 - 99",
      healthKitSource: .init(key: "private-source-2", origin: origin, name: nil))
    try records.write(second)
    XCTAssertThrowsError(try records.beginLocalCareDiscussionTurn(stale, now: now))
    try records.reconcileLocalCare(now: now)
    let advanced = try XCTUnwrap(records.load().localCare?.current["glucose"])
    let pair = try XCTUnwrap(advanced.comparison)
    XCTAssertEqual(pair.kind, .newResult)
    XCTAssertEqual(pair.before.record.id, first.id)
    XCTAssertEqual(pair.after.record.id, second.id)
    XCTAssertEqual(pair.previousContext?.applicability, .applicable)
    XCTAssertNil(advanced.context)
    XCTAssertEqual(pair.changes.map(\.delta), ["-10"])
    XCTAssertTrue(pair.gaps(currentContext: nil).contains(.conditionsDiffer))
    XCTAssertTrue(pair.gaps(currentContext: nil).contains(.contextUnconfirmed))
    try records.reconcileLocalCare(now: now)
    XCTAssertEqual(try records.load().localCare?.current["glucose"], advanced)
    let handoff = try approval().payload
    XCTAssertTrue(handoff.contains("arithmeticOnly"))
    for privateValue in [origin, "private condition fixture", first.id.uuidString, second.id.uuidString, "Private old response marker"] {
      XCTAssertFalse(handoff.contains(privateValue))
    }
    try records.setLocalCareContext(advanced, applicability: .excluded, now: now)
    let context = try XCTUnwrap(records.load().localCare?.current["glucose"]?.context)
    XCTAssertTrue(pair.gaps(currentContext: context).contains(.contextDiffers))

    var correction = try XCTUnwrap(records.load().current.first(where: { $0.id == second.id }))
    correction.value = 105
    try records.write(correction)
    try records.reconcileLocalCare(now: now)
    let corrected = try XCTUnwrap(records.load().localCare?.current["glucose"]?.comparison)
    XCTAssertEqual(corrected.kind, .recordCorrection)
    XCTAssertEqual(corrected.before.result, "100")
    XCTAssertTrue(corrected.changes.isEmpty)
    let correctionPayload = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(try approval().payload.utf8))
    XCTAssertNil(correctionPayload["concern"]?.objectValue?["comparison"]?.objectValue?["before"])

    let backfill = GalaxySSIHealthReading(metric: .glucose, measuredAt: now.addingTimeInterval(-86_400),
      value: 6, unitOverride: "mmol/L", referenceInterval: "4 - 5.5")
    try records.write(backfill)
    try records.reconcileLocalCare(now: now)
    let revisedHistory = try XCTUnwrap(records.load().localCare?.current["glucose"]?.comparison)
    XCTAssertEqual(revisedHistory.kind, .historyChanged)
    XCTAssertEqual(revisedHistory.before.record.id, backfill.id)
    XCTAssertTrue(revisedHistory.changes.isEmpty)
    XCTAssertTrue(revisedHistory.gaps(currentContext: nil).contains(.unitsDiffer))
    for id in [first.id, backfill.id] {
      var deleting = try XCTUnwrap(records.load().current.first(where: { $0.id == id }))
      deleting.deleted = true
      try records.write(deleting)
    }
    XCTAssertThrowsError(try approval())
    try records.reconcileLocalCare(now: now)
    XCTAssertNil(try records.load().localCare?.current["glucose"]?.comparison)
  }

  @MainActor
  func testLocalCarePlanAdoptsOnlySelectedStepsAndRejectsReplay() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let now = Date()
    try records.write(.init(metric: .glucose, measuredAt: now.addingTimeInterval(-300), value: 110,
      unitOverride: "mg/dL", referenceInterval: "70 - 99"))
    try records.setPrivacy(.localCare, enabled: true)
    try records.setHealthOnlinePermission(true)
    try records.reconcileLocalCare(now: now)
    let concern = try XCTUnwrap(records.load().localCare?.current["glucose"])
    _ = try records.openLocalCareDiscussion(id: concern.id, metric: .glucose)
    let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
      endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: now)
    let pending = try records.prepareLocalCareDiscussion(id: concern.id, metric: .glucose, question: "Draft options",
      destinationID: "provider", model: model, credential: "fixture-api-key", proposesPlan: true, now: now)
    let source = GalaxySSIHealthCareEvidence.PublicSource.labResults
    let quote = "This fictional laboratory paragraph is a fixture for testing the extraction and exact passage matching."
    let alternative = "The remainder supplies more article content."
    let hidden = "This exact passage is outside the approved model excerpt."
    let wideText = String(repeating: "\u{4E2D}", count: 4_000)
    let body = Data("<html><body><article><h1>Fixture</h1><p>\(quote) \(alternative) \(wideText) \(hidden)</p></article></body></html>".utf8)
    func addEvidence(_ pending: GalaxySSIHealthCareDiscussion.Approval) throws -> GalaxySSIHealthCareDiscussion.Approval {
      var approval = pending
      approval.evidence = [try GalaxySSIHealthCareEvidence.fromNativeBody(body, source: source,
        binding: .init(approval), retrievedAt: now, observedAt: now)]
      return approval
    }
    XCTAssertThrowsError(try records.beginLocalCareDiscussionTurn(pending, now: now))
    let approval = try addEvidence(pending)
    let request = try GalaxySSIHealthCareDiscussion.request(approval, key: "fixture-api-key")
    XCTAssertTrue(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains(GalaxySSIHealthCarePlan.tool))
    XCTAssertTrue(try approval.providerPayload().contains(quote))
    let receipt = try XCTUnwrap(approval.evidence.first)
    XCTAssertEqual(receipt.modelValue["evidence_id"], .string(receipt.id.uuidString))
    XCTAssertEqual(receipt.modelValue["excerpt_truncated"], .bool(true))
    XCTAssertLessThanOrEqual(receipt.modelExcerpt.utf8.count, GalaxySSIHealthCareEvidence.maximumModelExcerptBytes)
    XCTAssertFalse(try approval.providerPayload().contains(hidden))
    XCTAssertNotNil(receipt.match(url: source.url, quote: hidden))
    XCTAssertNil(receipt.match(url: source.url, quote: hidden, fromModelExcerpt: true))
    try records.beginLocalCareDiscussionTurn(approval, now: now)
    let raw = """
      {"uncertainty":"Context unconfirmed","sources":[{"title":"Fixture source","url":"\(source.url.absoluteString)",
      "version":"2026","applicability":"Applicability needs review","evidence_id":"\(approval.evidence[0].id.uuidString)",
      "quote":"\(quote)"}],"actions":[
      {"kind":"CONTEXT","description":"Clarify context","rationale":"Missing context","source_index":0,"due_from":"","due_until":"",
      "applicability":{"mode":"DISCUSSION_ONLY","checks":[],"missing_information":[],"conflicts":[]}},
      {"kind":"RECHECK","description":"Discuss a recheck","rationale":"Timing needs professional review","source_index":0,
      "due_from":"","due_until":"","applicability":{"mode":"INDIVIDUALIZED","checks":[
      {"field":"unit","operator":"EQUALS","expected":"mg/dL","source_index":0}],"missing_information":[],"conflicts":[]}},
      {"kind":"LIFESTYLE","description":"Review an option","rationale":"Adult applicability only","source_index":0,
      "due_from":"","due_until":"","applicability":{"mode":"INDIVIDUALIZED","checks":[
      {"field":"adult","operator":"EQUALS","expected":"YES","source_index":0}],"missing_information":[],"conflicts":[]}}]}
      """
    let arguments = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8))
    let call: AgentMcpJSONObject = ["type": .string("function"), "function": .object([
      "name": .string(GalaxySSIHealthCarePlan.tool), "arguments": .string(raw)
    ])]
    func envelope(_ calls: [AgentMcpJSONValue]) -> Data {
      Data(AgentMcpJSONCodec.stringify(["choices": .array([.object(["finish_reason": .string("tool_calls"),
        "message": .object(["tool_calls": .array(calls)])])])]).utf8)
    }
    XCTAssertEqual(try GalaxySSIHealthCarePlan.arguments(envelope([.object(call)]), style: .openAICompatible), arguments)
    XCTAssertThrowsError(try GalaxySSIHealthCarePlan.arguments(envelope([.object(call), .object(call)]), style: .openAICompatible))
    let invalidWindow = raw.replacingOccurrences(of: "\"due_from\":\"\"", with: "\"due_from\":\"2000-01-01T00:00:00Z\"")
    XCTAssertThrowsError(try GalaxySSIHealthCarePlan.parse(
      JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(invalidWindow.utf8)), evidence: approval.evidence, now: now))
    let badQuote = raw.replacingOccurrences(of: quote, with: "This passage was not in the original.")
    XCTAssertThrowsError(try GalaxySSIHealthCarePlan.parse(
      JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(badQuote.utf8)), evidence: approval.evidence, now: now))
    XCTAssertThrowsError(try GalaxySSIHealthCarePlan.parse(arguments, evidence: [], now: now))
    let originalSource = try XCTUnwrap(arguments["sources"]?.arrayValue?.first?.objectValue)
    var alternateSource = originalSource
    alternateSource["quote"] = .string(alternative)
    var duplicateSource = originalSource
    duplicateSource["quote"] = .string("  " + quote.replacingOccurrences(of: " ", with: "  ") + " ")
    var distinctPassages = arguments
    var actions = try XCTUnwrap(arguments["actions"]?.arrayValue?.compactMap(\.objectValue))
    actions[1]["source_index"] = .int(1)
    distinctPassages["actions"] = .array(actions.map(AgentMcpJSONValue.object))
    distinctPassages["sources"] = .array([.object(originalSource), .object(alternateSource)])
    let twoPassages = try GalaxySSIHealthCarePlan.parse(distinctPassages, evidence: approval.evidence, now: now)
    XCTAssertEqual(twoPassages.sources.map { $0.provenance?.quote }, [quote, alternative])
    XCTAssertEqual(twoPassages.sources[twoPassages.actions[1].sourceIndex].provenance?.quote, alternative)
    let policy = GalaxySSIHealthCareApplicability.self
    XCTAssertEqual(policy.status(twoPassages.actions[2].applicability, concern: concern), .needsContext)
    XCTAssertTrue(policy.canAdopt(twoPassages.actions[0], concern: concern))
    XCTAssertFalse(policy.canAdopt(twoPassages.actions[2], concern: concern))
    var confirmed = concern
    let activeRecord = try XCTUnwrap(confirmed.assessment.record)
    confirmed.context = .init(record: activeRecord, applicability: .unknown, facts: .init(adult: .no))
    XCTAssertEqual(policy.status(twoPassages.actions[2].applicability, concern: confirmed), .mismatch)
    confirmed.context = .init(record: activeRecord, applicability: .unknown, facts: .init(adult: .yes))
    XCTAssertTrue(policy.canAdopt(twoPassages.actions[2], concern: confirmed))
    confirmed.context = .init(record: .init(.init(metric: .glucose)), applicability: .unknown, facts: .init(adult: .yes))
    XCTAssertEqual(policy.status(twoPassages.actions[2].applicability, concern: confirmed), .needsContext)
    let unit = try XCTUnwrap(twoPassages.actions[1].applicability?.checks.first)
    let differentUnit = policy.result(.init(field: unit.field, comparison: unit.comparison, expected: "mmol/L",
      sourceIndex: unit.sourceIndex), concern: concern)
    XCTAssertEqual(differentUnit, .mismatch)
    var conflictArgs = distinctPassages
    var conflicted = actions
    var review = try XCTUnwrap(conflicted[1]["applicability"]?.objectValue)
    review["conflicts"] = .array([.object(["source_indices": .array([.int(0), .int(1)]),
      "detail": .string("Populations differ"), "next_step": .string("Clarify with clinician")])])
    conflicted[1]["applicability"] = .object(review)
    conflictArgs["actions"] = .array(conflicted.map(AgentMcpJSONValue.object))
    let conflict = try GalaxySSIHealthCarePlan.parse(conflictArgs, evidence: approval.evidence, now: now)
    XCTAssertEqual(policy.status(conflict.actions[1].applicability, concern: concern), .conflict)
    XCTAssertFalse(policy.canAdopt(conflict.actions[1], concern: concern))
    let acceptedArguments = distinctPassages
    distinctPassages["sources"] = .array([.object(originalSource), .object(duplicateSource)])
    XCTAssertThrowsError(try GalaxySSIHealthCarePlan.parse(distinctPassages, evidence: approval.evidence, now: now))
    try records.saveLocalCarePlan(approval, arguments: acceptedArguments, now: now)
    try records.saveLocalCarePlan(approval, arguments: acceptedArguments, now: now)
    var changed = acceptedArguments
    changed["uncertainty"] = .string("Changed after persistence")
    XCTAssertThrowsError(try records.saveLocalCarePlan(approval, arguments: changed, now: now))
    XCTAssertNil(try records.load().localCare?.current["glucose"]?.adoptedActions)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let draft = try XCTUnwrap(reopened.load().localCarePlans?[approval.id.uuidString])
    XCTAssertEqual(try reopened.load().localCareEvidence?[approval.id.uuidString], approval.evidence)
    XCTAssertEqual(draft.draft.sources.first?.provenance?.quote, quote)
    XCTAssertTrue(draft.selected.isEmpty)
    XCTAssertThrowsError(try reopened.resolveLocalCarePlan(draft, selected: [], now: now))
    XCTAssertThrowsError(try reopened.resolveLocalCarePlan(draft, selected: [1, 2], now: now))
    XCTAssertNil(try reopened.load().localCare?.current["glucose"]?.adoptedActions)
    try reopened.resolveLocalCarePlan(draft, selected: [1], now: now)
    let updated = try XCTUnwrap(reopened.load().localCare?.current["glucose"])
    XCTAssertEqual(updated.stage, .waitingResults)
    XCTAssertEqual(updated.adoptedActions?.map(\.action.kind), [.recheck])
    XCTAssertEqual(updated.adoptedActions?.first?.source.provenance?.quote, alternative)
    XCTAssertThrowsError(try reopened.resolveLocalCarePlan(draft, selected: [0], now: now))
    XCTAssertNil(try reopened.load().reviewReminderState)
    let action = try XCTUnwrap(updated.adoptedActions?.first)
    let firstTime = now.addingTimeInterval(3_600)
    XCTAssertThrowsError(try reopened.scheduleLocalCareFollowUp(concernID: concern.id, metric: .glucose,
      actionID: action.id, replacing: nil, at: firstTime, now: now))
    try reopened.setReviewRemindersEnabled(true)
    try reopened.setReviewNotificationPreferences(.init(enabled: true, quietStart: 0, quietEnd: 0))
    XCTAssertThrowsError(try reopened.scheduleLocalCareFollowUp(concernID: concern.id, metric: .glucose,
      actionID: action.id, replacing: nil, at: now, now: now))
    try reopened.scheduleLocalCareFollowUp(concernID: concern.id, metric: .glucose, actionID: action.id,
      replacing: nil, at: firstTime, now: now)
    let firstReminder = try XCTUnwrap(reopened.load().localCareFollowUps?[action.id])
    let secondTime = firstTime.addingTimeInterval(3_600)
    try reopened.scheduleLocalCareFollowUp(concernID: concern.id, metric: .glucose, actionID: action.id,
      replacing: firstReminder.id, at: secondTime, now: now)
    XCTAssertThrowsError(try reopened.cancelLocalCareFollowUp(firstReminder))
    let secondReminder = try XCTUnwrap(reopened.load().localCareFollowUps?[action.id])
    let delivery = try XCTUnwrap(reopened.localCareFollowUpDelivery(pending: [:], delivered: [],
      permitted: true, calendar: .current, now: now).pending.first)
    XCTAssertEqual(delivery.reminder, secondReminder)
    XCTAssertEqual(delivery.due, secondTime)
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: secondTime)
    let quiet = GalaxySSIHealthReviewDelivery.Preferences(enabled: true, quietStart: hour, quietEnd: (hour + 1) % 24)
    let deferred = GalaxySSIHealthCareFollowUp.deliveryPlan(reminders: [secondReminder], preferences: quiet,
      permitted: true, pending: [:], delivered: [], calendar: calendar, now: now)
    XCTAssertGreaterThan(try XCTUnwrap(deferred.pending.first?.due), secondTime)
    XCTAssertTrue(GalaxySSIHealthCareFollowUp.deliveryPlan(reminders: [secondReminder], preferences: quiet,
      permitted: false, pending: [:], delivered: [], calendar: calendar, now: now).pending.isEmpty)
    try reopened.markLocalCareFollowUpSubmitted(delivery, calendar: .current, now: now)
    XCTAssertNil(try reopened.localCareFollowUpTarget(token: firstReminder.id, now: secondTime))
    XCTAssertEqual(try reopened.localCareFollowUpTarget(token: secondReminder.id, now: secondTime)?.id, secondReminder.id)
    let otherPending = try reopened.prepareLocalCareDiscussion(id: concern.id, metric: .glucose, question: "A separate step",
      destinationID: "provider", model: model, credential: "fixture-api-key", proposesPlan: true, now: now)
    var crossTurn = otherPending
    crossTurn.evidence = approval.evidence
    XCTAssertThrowsError(try reopened.beginLocalCareDiscussionTurn(crossTurn, now: now))
    let otherApproval = try addEvidence(otherPending)
    try reopened.beginLocalCareDiscussionTurn(otherApproval, now: now)
    XCTAssertThrowsError(try reopened.saveLocalCarePlan(otherApproval, arguments: arguments, now: now))
    let pendingEvidenceID = approval.evidence[0].id.uuidString
    func argumentsFor(_ approval: GalaxySSIHealthCareDiscussion.Approval) throws -> AgentMcpJSONObject {
      let scoped = raw.replacingOccurrences(of: pendingEvidenceID, with: approval.evidence[0].id.uuidString)
      return try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(scoped.utf8))
    }
    try reopened.saveLocalCarePlan(otherApproval, arguments: argumentsFor(otherApproval), now: now)
    let otherPlan = try XCTUnwrap(reopened.load().localCarePlans?[otherApproval.id.uuidString])
    try reopened.resolveLocalCarePlan(otherPlan, selected: [0], now: now)
    let otherAction = try XCTUnwrap(reopened.load().localCare?.current["glucose"]?.adoptedActions?.last)
    try reopened.scheduleLocalCareFollowUp(concernID: concern.id, metric: .glucose, actionID: otherAction.id,
      replacing: nil, at: firstTime, now: now)
    XCTAssertThrowsError(try reopened.recordLocalCareOutcome(concernID: concern.id, metric: .glucose,
      action: action, note: " ", now: now))
    try reopened.recordLocalCareOutcome(concernID: concern.id, metric: .glucose, action: action,
      note: "Discussed at appointment", now: now)
    let recorded = try XCTUnwrap(reopened.load().localCare?.current["glucose"])
    XCTAssertEqual(recorded.stage, .reassess)
    XCTAssertEqual(recorded.assessment, updated.assessment)
    XCTAssertEqual(recorded.adoptedActions?.first?.outcome?.note, "Discussed at appointment")
    XCTAssertNil(try reopened.load().localCareFollowUps?[action.id])
    XCTAssertNotNil(try reopened.load().localCareFollowUps?[otherAction.id])
    XCTAssertNil(try reopened.localCareFollowUpTarget(token: secondReminder.id, now: secondTime))
    let second = try addEvidence(reopened.prepareLocalCareDiscussion(id: concern.id, metric: .glucose, question: "Another draft",
      destinationID: "provider", model: model, credential: "fixture-api-key", proposesPlan: true, now: now))
    try reopened.beginLocalCareDiscussionTurn(second, now: now)
    try reopened.saveLocalCarePlan(second, arguments: argumentsFor(second), now: now)
    let revoked = try XCTUnwrap(reopened.load().localCarePlans?[second.id.uuidString])
    try reopened.setHealthOnlinePermission(false)
    XCTAssertNil(try reopened.load().localCareFollowUps?[otherAction.id])
    XCTAssertThrowsError(try reopened.resolveLocalCarePlan(revoked, selected: [0], now: now))
    try reopened.resolveLocalCarePlan(revoked, selected: nil, now: now)
    XCTAssertEqual(try reopened.load().localCarePlans?[second.id.uuidString]?.state, .dismissed)
    XCTAssertEqual(try reopened.load().localCare?.current["glucose"]?.adoptedActions?.count, 2)
  }

  @MainActor
  func testOptInHealthCareNativeEvidenceProviderProbe() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["GALAXYSSI_IOS_HEALTH_LIVE_PROBE"] == "1",
          let endpoint = env["GALAXYSSI_IOS_HEALTH_LIVE_ENDPOINT"],
          let modelID = env["GALAXYSSI_IOS_HEALTH_LIVE_MODEL"],
          let key = env["GALAXYSSI_IOS_HEALTH_LIVE_KEY"], CloudModelCredentialPolicy.isStoredCredential(key)
    else { throw XCTSkip("Requires explicit test-provider opt-in and credentials") }
    let model = CloudModelConfig(id: "live-fixture", displayName: "Live fixture", provider: "Custom",
      modelId: modelID, endpoint: endpoint, apiStyle: .openAICompatible, keychainAccount: "", updatedAt: Date())
    guard GalaxySSIHealthCareDiscussion.endpoint(for: model) != nil else { throw GalaxySSIHealthRecords.Failure.invalid }

    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "synthetic-health-probe", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.write(.init(metric: .glucose, measuredAt: Date().addingTimeInterval(-300), value: 110,
      conditions: "Synthetic fixture; fasting status unknown", unitOverride: "mg/dL", referenceInterval: "70 - 99"))
    try records.setPrivacy(.localCare, enabled: true)
    try records.setHealthOnlinePermission(true)
    try records.reconcileLocalCare()
    let concern = try XCTUnwrap(records.load().localCare?.current["glucose"])
    _ = try records.openLocalCareDiscussion(id: concern.id, metric: .glucose)
    var approval = try records.prepareLocalCareDiscussion(id: concern.id, metric: .glucose,
      question: "Synthetic test. Draft one context-clarification step from the supplied native source and quote it exactly.",
      destinationID: "test-provider", model: model, credential: key, proposesPlan: true)
    approval.evidence = [try await GalaxySSIHealthCareEvidence.fetch(.labResults, binding: .init(approval))]
    try records.beginLocalCareDiscussionTurn(approval)
    let planRequest = try GalaxySSIHealthCareDiscussion.request(approval, key: key)
    let planData = try await GalaxySSIHealthSummaryTransport.responseBytes(planRequest, limit: 65_536)
    let arguments = try GalaxySSIHealthCarePlan.arguments(planData, style: .openAICompatible)
    try records.saveLocalCarePlan(approval, arguments: arguments)
    let draft = try XCTUnwrap(records.load().localCarePlans?[approval.id.uuidString])
    XCTAssertEqual(draft.state, .pending)
    XCTAssertTrue(draft.draft.sources.allSatisfy { $0.provenance?.receiptID == approval.evidence.first?.id })

    let followUp = try records.prepareLocalCareDiscussion(id: concern.id, metric: .glucose,
      question: "\u{8BF7}\u{7528}\u{7B80}\u{4F53}\u{4E2D}\u{6587}\u{56DE}\u{7B54}\u{FF1A}What context is still unknown for this synthetic reading?",
      destinationID: "test-provider", model: model, credential: key)
    try records.beginLocalCareDiscussionTurn(followUp)
    let followUpRequest = try GalaxySSIHealthCareDiscussion.request(followUp, key: key)
    let followUpData = try await GalaxySSIHealthSummaryTransport.responseBytes(followUpRequest, limit: 65_536)
    let answer = try GalaxySSIHealthFollowUpTransport.output(followUpData, style: .openAICompatible)
    XCTAssertTrue(answer.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) })
    try records.finishLocalCareDiscussionTurn(followUp, answer: answer)
    let archive = try records.load()
    XCTAssertEqual(archive.localCare?.current["glucose"], concern)
    XCTAssertTrue(archive.localCareFollowUps?.isEmpty ?? true)
  }

  @MainActor
  func testLocalCareDiscussionBindsConsentToConcernTurnAndProvider() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let now = Date()
    let reading = GalaxySSIHealthReading(metric: .glucose, measuredAt: now.addingTimeInterval(-300),
      value: 110, notes: "Private note excluded", unitOverride: "mg/dL", referenceInterval: "70 - 99")
    try records.write(reading)
    try records.setPrivacy(.localCare, enabled: true)
    try records.reconcileLocalCare(now: now)
    let concern = try XCTUnwrap(records.load().localCare?.current["glucose"])
    let thread = try records.openLocalCareDiscussion(id: concern.id, metric: .glucose)
    XCTAssertTrue(thread.turns.isEmpty)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertEqual(try reopened.openLocalCareDiscussion(id: concern.id, metric: .glucose).id, thread.id)
    let model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
      endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: now)
    func review(_ provider: String = "provider-a") throws -> GalaxySSIHealthCareDiscussion.Approval {
      try records.prepareLocalCareDiscussion(id: concern.id, metric: .glucose, question: "Explain this reading",
        destinationID: provider, model: model, credential: "fixture-api-key", now: now)
    }
    XCTAssertThrowsError(try review())
    try records.setHealthOnlinePermission(true)
    let approved = try review()
    XCTAssertFalse(approved.payload.contains(reading.notes))
    XCTAssertFalse(approved.payload.contains(reading.id.uuidString))
    let request = try GalaxySSIHealthCareDiscussion.request(approved, key: "fixture-api-key")
    XCTAssertEqual(request.url, approved.endpoint)
    XCTAssertThrowsError(try GalaxySSIHealthCareDiscussion.request(approved, key: "different-api-key"))
    XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains("\"tools\""))
    var otherModel = model
    otherModel.apiStyle = .gemini
    otherModel.endpoint = "https://example.test/v1beta/models/other:generateContent"
    XCTAssertNil(GalaxySSIHealthCareDiscussion.endpoint(for: otherModel))
    XCTAssertThrowsError(try records.beginLocalCareDiscussionTurn(approved, now: now.addingTimeInterval(601)))
    try records.beginLocalCareDiscussionTurn(approved, now: now)
    XCTAssertThrowsError(try reopened.beginLocalCareDiscussionTurn(approved, now: now))
    try records.finishLocalCareDiscussionTurn(approved, answer: "Fixture scoped response", now: now)
    XCTAssertTrue(try review().payload.contains("Fixture scoped response"))
    XCTAssertFalse(try review("provider-b").payload.contains("Fixture scoped response"))
    let stale = try review()
    try records.setHealthOnlinePermission(false)
    try records.setHealthOnlinePermission(true)
    XCTAssertThrowsError(try records.beginLocalCareDiscussionTurn(stale, now: now))
    let updatedApproval = try review()
    try records.setLocalCareContext(concern, applicability: .excluded, now: now)
    XCTAssertThrowsError(try records.beginLocalCareDiscussionTurn(updatedApproval, now: now))
    let updated = try XCTUnwrap(records.load().localCare?.current["glucose"])
    try records.deleteLocalCare(updated)
    XCTAssertThrowsError(try records.openLocalCareDiscussion(id: concern.id, metric: .glucose))
    XCTAssertEqual(try reopened.load().localCareDiscussions?[concern.id.uuidString]?.id, thread.id)
  }

  @MainActor
  func testLocalCareRequiresPermissionAndPreservesExactRevisionHistory() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let high = GalaxySSIHealthReading(metric: .glucose, measuredAt: now.addingTimeInterval(-1_000),
      value: 110, conditions: "lab", unitOverride: "mg/dL", referenceInterval: "70 - 99")
    try records.write(high)
    XCTAssertThrowsError(try records.reconcileLocalCare(now: now))
    try records.setPrivacy(.localCare, enabled: true)
    try records.reconcileLocalCare(now: now)
    let first = try XCTUnwrap(records.load().localCare?.current["glucose"])
    XCTAssertEqual(first.assessment.signals, [.reportHigh, .glucoseContext])
    XCTAssertNil(first.target)
    XCTAssertNil(first.assessment.guidelineVersion)
    try records.reconcileLocalCare(now: now)
    XCTAssertEqual(try records.load().localCare?.current["glucose"], first)
    try records.setLocalCareContext(first, applicability: .applicable, now: now)
    let verified = try XCTUnwrap(records.load().localCare?.current["glucose"])
    XCTAssertEqual(verified.assessment.guidelineVersion, "ADA 2026")
    XCTAssertThrowsError(try records.reviewLocalCare(first, stage: .closed, reason: "Stale revision", now: now))
    let inRange = GalaxySSIHealthReading(metric: .glucose, measuredAt: now.addingTimeInterval(-100),
      value: 90, conditions: "lab", unitOverride: "mg/dL", referenceInterval: "70 - 99")
    try records.write(inRange)
    try records.reconcileLocalCare(now: now)
    let updated = try XCTUnwrap(records.load().localCare?.current["glucose"])
    XCTAssertEqual(updated.id, first.id)
    XCTAssertEqual(updated.stage, .reassess)
    XCTAssertNil(updated.context)
    XCTAssertEqual(try records.localCareHistory(updated.id).map(\.revision), [2, 1])
    var later = high
    later.id = UUID()
    later.measuredAt = now.addingTimeInterval(-10)
    later.value = 113
    try records.write(later)
    XCTAssertThrowsError(try records.reviewLocalCare(updated, stage: .closed, reason: "Source changed", now: now))
    XCTAssertThrowsError(try records.deleteLocalCare(updated, now: now))
    XCTAssertEqual(try records.load().localCare?.current["glucose"], updated)
    try records.reconcileLocalCare(now: now)
    let refreshed = try XCTUnwrap(records.load().localCare?.current["glucose"])
    XCTAssertEqual(refreshed.assessment.record?.id, later.id)
    try records.deleteLocalCare(refreshed, now: now)
    try records.reconcileLocalCare(now: now)
    XCTAssertNil(try records.load().localCare?.current["glucose"])
    later.id = UUID()
    later.measuredAt = now
    try records.write(later)
    try records.reconcileLocalCare(now: now)
    XCTAssertEqual(try records.load().localCare?.current["glucose"]?.assessment.record?.id, later.id)
    try records.setPrivacy(.localCare, enabled: false)
    XCTAssertThrowsError(try records.localCareHistory(updated.id))
    XCTAssertNil(try Data(contentsOf: file).range(of: Data("glucoseContext".utf8)))
  }

  @MainActor
  func testDataFilesOrdersAndPagesMetadataWithoutReadingPayloads() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = Date(timeIntervalSince1970: 100)
    func original(_ value: Int, _ acquisition: GalaxySSIHealthOriginalStore.Acquisition?)
      -> GalaxySSIHealthOriginalStore.Original {
      let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(value)))
      return .init(id: id, name: "File \(value)", kind: .pdf, fileExtension: "pdf",
                   importedAt: date, bytes: 200, sha256: "digest-\(value)", acquisition: acquisition)
    }
    var archive = GalaxySSIHealthRecords.Archive()
    var index = GalaxySSIHealthOriginalStore.Index()
    for number in 1...33 { try index.include(original(number, .camera)) }
    let linked = original(34, .uploaded)
    let wrongDigest = original(35, .uploaded)
    let unknown = original(36, nil)
    let removed = original(37, .camera)
    for item in [linked, wrongDigest, unknown, removed] { try index.include(item) }
    index.removals.pending.insert(removed.id)
    archive.originalIndex = index
    func measurement(source: GalaxySSIHealthOriginalStore.Original, sha256: String) -> GalaxySSIHealthReading {
      .init(revision: 1, metric: .weight, value: 60,
            reportSource: .init(original: source.id, sha256: sha256, page: 0, region: 0, fromOCR: false))
    }
    let reading = measurement(source: linked, sha256: linked.sha256)
    var deleted = measurement(source: unknown, sha256: unknown.sha256)
    archive.revisions = [reading, measurement(source: wrongDigest, sha256: linked.sha256), deleted]
    deleted.revision += 1
    deleted.deleted = true
    archive.revisions.append(deleted)
    for item in [linked, wrongDigest, unknown] {
      try Data().write(to: directory.appendingPathComponent(item.id.uuidString))
    }
    let snapshot = try GalaxySSIHealthDataFiles.project(JSONEncoder().encode(archive))
    let first = snapshot.page(after: nil)
    XCTAssertEqual(first.count, 30)
    XCTAssertEqual(snapshot.page(after: first.last).count, 6)
    let recent = try snapshot.recent(in: directory)
    XCTAssertEqual(recent.map(\.id), [unknown.id, wrongDigest.id, linked.id, original(33, .camera).id])
    XCTAssertEqual(recent.map(\.status), [.unlinked, .unlinked, .linked, .unavailable])
    let counts = try await snapshot.counts()
    XCTAssertEqual(counts, .init(measurements: 2, camera: 33, uploaded: 2))

    let cancelled = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await snapshot.counts()
    }
    do { _ = try await cancelled.value; XCTFail("Expected cancellation") }
    catch is CancellationError {}
  }

  @MainActor
  func testOriginalSearchMatchesOnlyCurrentConfirmedSourcesAndLocalDates() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
    let iso = ISO8601DateFormatter()
    let measured = try XCTUnwrap(iso.date(from: "2024-04-01T16:15:00Z"))
    let imported = try XCTUnwrap(iso.date(from: "2024-05-03T08:00:00Z"))
    let originals = (0..<37).map { index in
      GalaxySSIHealthOriginalStore.Original(id: UUID(), name: index == 31 ? "Lab-report final.PDF" : "Scan \(index).pdf",
        kind: .pdf, fileExtension: "pdf", importedAt: imported, bytes: 200, sha256: "digest-\(index)", acquisition: .uploaded)
    }
    func source(_ index: Int, digest: String? = nil) -> GalaxySSIHealthReportReview.Source {
      let item = originals[index]
      return .init(original: item.id, sha256: digest ?? item.sha256, page: 0, region: 0, fromOCR: true)
    }
    let reading = GalaxySSIHealthReading(revision: 2, metric: .glucose, measuredAt: measured, value: 6,
                                        reportSource: source(31))
    var old = reading
    old.revision = 1
    old.reportSource = source(33)
    var deleted = GalaxySSIHealthReading(revision: 1, metric: .glucose, measuredAt: measured, value: 6,
                                        reportSource: source(36))
    var archive = GalaxySSIHealthRecords.Archive()
    archive.revisions = [old, reading, deleted]
    deleted.revision = 2
    deleted.deleted = true
    archive.revisions.append(deleted)
    let target = GalaxySSIHealthReportReview.Target(record: reading.id, revision: reading.revision)
    archive.reportEvidence = [
      .init(target: target, source: source(32), excerpt: "confirmed"),
      .init(target: target, source: source(34, digest: "wrong"), excerpt: "wrong digest"),
      .init(target: target, source: source(35), excerpt: "removed"),
      .init(target: .init(record: reading.id, revision: 1), source: source(30), excerpt: "old revision")
    ]
    var index = GalaxySSIHealthOriginalStore.Index()
    for item in originals { try index.include(item) }
    index.removals.pending.insert(originals[35].id)
    archive.originalIndex = index
    let metadata = try JSONEncoder().encode(archive)
    func matches(_ query: String) throws -> Set<UUID> {
      try GalaxySSIHealthDataFiles.OriginalQuery(query, timeZone: zone).matches(originals, metadata: metadata)
    }
    let linked = Set([originals[31].id, originals[32].id])
    XCTAssertEqual(try matches("FINAL lab"), [originals[31].id])
    XCTAssertEqual(try matches("GLU"), linked)
    XCTAssertEqual(try matches("\u{8840}\u{7CD6}"), linked)
    XCTAssertEqual(try matches("2024-04-02"), linked)
    XCTAssertEqual(try matches("2024\u{5E74}4\u{6708}"), linked)
    XCTAssertEqual(try matches("2024-04-01"), [])
    XCTAssertEqual(try matches("2024-04-31"), [])
    XCTAssertEqual(try matches("2024/05"), Set(originals.map(\.id)).subtracting([originals[35].id]))
  }

  func testOriginalSearchCancelsBeforeOpeningArchive() async throws {
    let worker = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      let reader = GalaxySSIHealthDataFiles.Reader(file: URL(fileURLWithPath: "/unreadable"),
                                                  context: Data(), key: nil)
      return try reader.search(.init("2024-04", timeZone: .current), in: [])
    }
    do { _ = try await worker.value; XCTFail("Expected cancellation") }
    catch is CancellationError {}
  }

  @MainActor
  func testDataFilesAuthenticatesArchiveAndPersistsMeasurementExportStatus() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let file = root.appendingPathComponent("records")
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertEqual(try records.dataFilesReader().read().measurements, 0)
    let verified = try records.beginMeasurementExport(format: .csv, rows: 2, includesOriginals: false)
    let unfinished = try records.beginMeasurementExport(format: .xlsx, rows: 3, includesOriginals: true)
    try records.finishMeasurementExport(verified, verified: true)
    try records.finishMeasurementExport(verified, verified: false)
    let archive = try records.load()
    XCTAssertEqual(archive.measurementExports?.map(\.id), [verified, unfinished])
    XCTAssertEqual(archive.measurementExports?.map(\.status), [.verified, .prepared])
    XCTAssertEqual(try records.dataFilesReader().read().measurements, 0)
    let reader = try records.dataFilesReader()
    try Data("corrupted".utf8).write(to: file)
    XCTAssertThrowsError(try reader.read())
  }

  func testAppleHealthTrendPagesOriginsWithinScopeAndPinsExactContributor() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func row(_ id: String, at date: Date? = nil) -> GalaxySSIHealthReading {
      .init(revision: 2, metric: .weight, measuredAt: date ?? now, value: 60,
            healthKitSource: .init(key: id, origin: id, name: "Same name"))
    }
    let readings = (0..<35).map { row(String(format: "org.example.app%02d", $0)) }
    let extra = row("org.example.outside", at: now.addingTimeInterval(-86_400))
    let malformed = row("bad origin")
    let input = Array(readings.reversed()) + [extra, malformed]
    let first = GalaxySSIHealthTrend.origins(in: input, metric: .weight, from: now, through: now)
    XCTAssertEqual(first.options.count, 30)
    XCTAssertTrue(first.hasMore)
    let cursor = try XCTUnwrap(first.options.last?.id)
    let next = GalaxySSIHealthTrend.origins(in: input, metric: .weight, from: now, through: now, after: cursor)
    XCTAssertEqual(next.options.count, 6)
    XCTAssertFalse(next.hasMore)
    XCTAssertEqual(Set((first.options + next.options).map(\.id)).count, 36)
    XCTAssertEqual(next.options.last?.id, .unidentified)
    XCTAssertFalse(next.options.contains { $0.id == .application("org.example.outside") })

    let manual = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 70)
    let trend = GalaxySSIHealthTrend(current: input + [manual], metric: .weight, component: .value,
      now: now, dayCount: 1, calendar: calendar, source: .healthKit, healthOrigin: .application("org.example.app33"))
    XCTAssertEqual(trend.points.first?.revisions, [readings[33].id: 2])
    XCTAssertEqual(trend.points.first?.readings.first?.healthKitSource?.origin, "org.example.app33")
  }

  func testAppleHealthStepAggregatesAreNotAttributedToAnApplication() throws {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let aggregate = GalaxySSIHealthReading(metric: .steps, measuredAt: now, value: 2_000,
      healthKitSource: .init(key: "aggregate", origin: nil, name: nil))
    var app = aggregate
    app.id = UUID()
    app.healthKitSource = .init(key: "app", origin: "org.example.steps", name: "Steps")
    var malformed = aggregate
    malformed.id = UUID()
    malformed.healthKitSource = .init(key: "bad", origin: "org..bad", name: "Steps")
    let manual = GalaxySSIHealthReading(metric: .steps, measuredAt: now, value: 1_000)
    let readings = [aggregate, app, malformed, manual]
    let page = GalaxySSIHealthTrend.origins(in: readings, metric: .steps, from: now, through: now)
    XCTAssertEqual(page.options.map(\.id), [.dailySteps, .application("org.example.steps"), .unidentified])
    let trend = GalaxySSIHealthTrend(current: readings, metric: .steps, component: .value,
      now: now, dayCount: 1, calendar: .current, source: .healthKit, healthOrigin: .dailySteps)
    XCTAssertEqual(trend.points.first?.readings.map(\.id), [aggregate.id])
    XCTAssertFalse(GalaxySSIHealthTrend.Source.manual.includes(aggregate))
  }

  func testSourceAttentionOnlyShowsSelectedFailuresAndAcknowledgesExactRevision() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var ledger = GalaxySSIHealthSourceAttention()
    ledger.selected = [.weight, .sleep]
    ledger.readFinished(.heartRate, result: .failed, now: now)
    ledger.readFinished(.weight, result: .failed, now: now)
    let original = try XCTUnwrap(ledger.active.first)
    ledger.readFinished(.sleep, result: .failed, now: now.addingTimeInterval(5))
    ledger.readFinished(.weight, result: .failed, now: now.addingTimeInterval(10))
    ledger.acknowledge(original)
    XCTAssertEqual(ledger.active.map(\.scope), [.weight, .sleep])
    ledger.selected.remove(.sleep)
    XCTAssertEqual(ledger.active.map(\.scope), [.weight])
    ledger.acknowledge(try XCTUnwrap(ledger.active.first))
    XCTAssertTrue(ledger.active.isEmpty)
    ledger.selected.insert(.sleep)
    ledger.readFinished(.sleep, result: .empty, now: now)
    XCTAssertTrue(ledger.active.isEmpty)
  }

  @MainActor
  func testAppleHealthCoverageKeepsSelectionQueryAndImportHistoryIndependent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("records")
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let start = Date(timeIntervalSince1970: 1_750_000_000)
    let later = start.addingTimeInterval(120)
    try records.updateSourceAttention { $0.selected = [.weight] }
    XCTAssertNil(try records.loadSourceAttention().readHistory)

    try records.updateSourceAttention {
      $0.readFinished(.sleep, result: .failed, now: start)
      $0.readFinished(.weight, result: .samples, now: start)
      $0.readFinished(.weight, result: .empty, now: later)
    }
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let coverage = try reopened.loadSourceAttention()
    XCTAssertEqual(coverage.selected, [.weight])
    XCTAssertTrue(coverage.active.isEmpty)
    XCTAssertEqual(coverage.readHistory?[.sleep]?.result, .failed)
    XCTAssertNil(coverage.readHistory?[.sleep]?.lastSamplesAt)
    XCTAssertEqual(coverage.readHistory?[.weight]?.result, .empty)
    XCTAssertEqual(coverage.readHistory?[.weight]?.at, later)
    XCTAssertEqual(coverage.readHistory?[.weight]?.lastSamplesAt, start)
    XCTAssertNil(try reopened.load().healthKitImportedAt)

    let copy = GalaxySSIHealthReading(metric: .weight, measuredAt: start, value: 65,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: nil, name: nil))
    XCTAssertEqual(try reopened.importHealthKit([copy], at: later), 1)
    XCTAssertEqual(try reopened.importHealthKit([copy], at: later.addingTimeInterval(100)), 0)
    XCTAssertEqual(try reopened.load().healthKitImportedAt, [.weight: later])
    XCTAssertEqual(try reopened.loadSourceAttention(), coverage)
  }

  @MainActor
  func testCorruptEncryptedSourceAttentionDoesNotHideMeasurementsOrReplaceIncidents() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sidecar = file.appendingPathExtension("source-attention")
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: sidecar)
    }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let now = Date()
    try records.write(.init(metric: .weight, measuredAt: now, value: 60))
    try records.updateSourceAttention {
      $0.selected = [.weight]
      $0.readFinished(.weight, result: .failed, now: now)
    }
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertEqual(try reopened.loadSourceAttention().active.map(\.scope), [.weight])
    let foreign = GalaxySSIHealthRecords(owner: "another", secrets: secrets, isolatedFile: file)
    XCTAssertThrowsError(try foreign.loadSourceAttention())
    let corrupt = Data("corrupt fixture".utf8)
    try corrupt.write(to: sidecar)
    XCTAssertThrowsError(try reopened.loadSourceAttention())
    XCTAssertThrowsError(try reopened.updateSourceAttention { $0.selected.removeAll() })
    XCTAssertEqual(try Data(contentsOf: sidecar), corrupt)
    XCTAssertEqual(try reopened.load().current.count, 1)
  }

  func testRecordCenterSeparatesReviewDraftsAndRequiresExactOriginalIdentity() {
    let id = UUID()
    let original = GalaxySSIHealthOriginalStore.Original(id: id, name: "fixture.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: Date(), bytes: 123, sha256: String(repeating: "a", count: 64))
    let confirmed = GalaxySSIHealthReading(metric: .weight, measuredAt: Date(), value: 60)
    let pending = GalaxySSIHealthReading(metric: .weight, measuredAt: Date(), value: 70)
    let source = GalaxySSIHealthReportReview.Source(original: id, sha256: original.sha256,
      page: 2, region: 3, fromOCR: true)
    var archive = GalaxySSIHealthRecords.Archive()
    archive.revisions = [confirmed]
    archive.reportReview = [.init(version: UUID(), source: source, excerpt: "Synthetic report", reading: pending)]
    archive.draft = GalaxySSIHealthDraft()
    let snapshot = GalaxySSIHealthRecordCenterSnapshot(archive: archive, originals: [original])
    XCTAssertEqual(snapshot.confirmed.map(\.id), [confirmed.id])
    XCTAssertEqual(snapshot.pending.count, 1)
    XCTAssertEqual(snapshot.pending.first?.original, original)
    XCTAssertEqual(snapshot.pending.first?.items.first?.source.page, 2)
    XCTAssertNotNil(snapshot.draft)
    let missing = GalaxySSIHealthRecordCenterSnapshot(archive: archive, originals: [])
    XCTAssertNil(missing.pending.first?.original)
    XCTAssertEqual(missing.pending.first?.items.count, 1)
    let replaced = GalaxySSIHealthOriginalStore.Original(id: id, name: original.name, kind: .pdf,
      fileExtension: "pdf", importedAt: original.importedAt, bytes: original.bytes, sha256: String(repeating: "b", count: 64))
    XCTAssertNil(GalaxySSIHealthRecordCenterSnapshot(archive: archive, originals: [replaced]).pending.first?.original)
    var removed = confirmed
    removed.revision += 1
    removed.deleted = true
    archive.revisions.append(removed)
    XCTAssertTrue(GalaxySSIHealthRecordCenterSnapshot(archive: archive, originals: [original]).confirmed.isEmpty)
  }
  func testHealthKitPreviewBindsSourceMetadataAndRowMultiplicity() {
    let now = Date()
    let source = GalaxySSIHealthKitImport.Source(key: "sample", origin: "fixture", name: "Original")
    let original = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65, healthKitSource: source)
    let another = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 66, healthKitSource: source)
    var renamed = original
    renamed.healthKitSource = .init(key: source.key, origin: source.origin, name: "Updated")
    var reread = original
    reread.id = UUID()
    let stamp = GalaxySSIHealthKitImport.stamp
    XCTAssertEqual(stamp([original, another]), stamp([another, reread]))
    XCTAssertNotEqual(stamp([original]), stamp([renamed]))
    XCTAssertNotEqual(stamp([original]), stamp([original, original]))
  }

  @MainActor
  func testHealthKitSyncCommitsPageAndCursorTogetherAndResumesWithoutDeleting() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let floor = now.addingTimeInterval(-86_400)
    let first = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    let item = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    let broken = GalaxySSIHealthKitSync.Page(rows: [item, .init(metric: .weight, value: 66)], anchor: Data([1]),
      providerCount: 2, more: true)
    XCTAssertThrowsError(try records.commitHealthKitPage(scope: .weight, expected: first, page: broken, at: now))
    XCTAssertTrue(try records.load().current.isEmpty)
    XCTAssertNil(try records.load().healthKitSync?["weight"]?.anchor)
    let page = GalaxySSIHealthKitSync.Page(rows: [item], anchor: Data([2]), providerCount: 1, more: true)
    let saved = try records.commitHealthKitPage(scope: .weight, expected: first, page: page, at: now)
    XCTAssertEqual(saved.anchor, Data([2]))
    XCTAssertEqual(try records.load().current.map(\.id), [item.id])
    XCTAssertThrowsError(try records.commitHealthKitPage(scope: .weight, expected: first, page: page, at: now))
    try records.finishHealthKitSync(.weight, run: saved.run, status: .interrupted)
    let resumed = try records.beginHealthKitSync(.weight, floor: now, reset: false)
    XCTAssertEqual(resumed.floor, floor)
    XCTAssertEqual(resumed.anchor, saved.anchor)
    let deletionOnly = GalaxySSIHealthKitSync.Page(rows: [], anchor: Data([3]), providerCount: 1, more: false)
    XCTAssertEqual(try records.commitHealthKitPage(scope: .weight, expected: resumed, page: deletionOnly, at: now).status, .success)
    let next = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    let empty = try records.commitHealthKitPage(scope: .weight, expected: next, page: deletionOnly, at: now)
    XCTAssertEqual(empty.status, .empty)
    XCTAssertEqual(try records.load().current.map(\.id), [item.id])
    let reset = try records.beginHealthKitSync(.weight, floor: now, reset: true)
    XCTAssertTrue(reset.previousCoverageUnverified)
    XCTAssertNil(reset.anchor)
  }

  @MainActor
  func testHealthKitSyncIncidentRetriesKeepAcknowledgmentUntilRecovery() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let now = Date()
    let floor = now.addingTimeInterval(-86_400)
    let sample = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "c", count: 64), origin: "fixture", name: nil))
    let initial = try records.beginHealthKitSync(.weight, floor: floor, reset: false, at: now)
    _ = try records.commitHealthKitPage(scope: .weight, expected: initial,
      page: .init(rows: [sample], anchor: Data([1]), providerCount: 1, more: false), at: now)
    let paused = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    try records.finishHealthKitSync(.weight, run: paused.run, status: .interrupted)
    XCTAssertTrue(try records.load().syncIncidents.isEmpty)
    let failed = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    try records.finishHealthKitSync(.weight, run: failed.run, status: .failed, at: now.addingTimeInterval(1))
    let first = try XCTUnwrap(records.load().syncIncident(.weight))
    XCTAssertEqual(first.lastSuccess, now)
    XCTAssertFalse(first.handled)
    try records.recordHealthKitAuthorizationFailure([.weight, .steps], status: .permission, at: now.addingTimeInterval(2))
    let updated = try XCTUnwrap(records.load().syncIncidents.first)
    XCTAssertEqual(updated.id, first.id)
    XCTAssertEqual(updated.status, .permission)
    XCTAssertEqual(try records.load().syncIncidents.count, 1)
    XCTAssertThrowsError(try records.acknowledgeHealthKitIncident(first))
    let checkpoint = try records.load().healthKitSync?["weight"]
    try records.acknowledgeHealthKitIncident(updated, at: now.addingTimeInterval(3))
    XCTAssertEqual(try records.load().healthKitSync?["weight"], checkpoint)
    let retry = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    try records.finishHealthKitSync(.weight, run: retry.run, status: .failed, at: now.addingTimeInterval(4))
    XCTAssertTrue(try records.load().syncIncident(.weight)?.handled == true)
    let recovery = try records.beginHealthKitSync(.weight, floor: floor, reset: true)
    let recoveredAt = now.addingTimeInterval(5)
    _ = try records.commitHealthKitPage(scope: .weight, expected: recovery,
      page: .init(rows: [], anchor: Data([2]), providerCount: 0, more: false), at: recoveredAt)
    XCTAssertEqual(try records.load().syncIncident(.weight)?.resolvedAt, recoveredAt)
    let later = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    try records.finishHealthKitSync(.weight, run: later.run, status: .unavailable, at: now.addingTimeInterval(6))
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let fresh = try XCTUnwrap(reopened.load().syncIncident(.weight))
    XCTAssertNotEqual(fresh.id, first.id)
    XCTAssertEqual(fresh.lastSuccess, recoveredAt)
    XCTAssertFalse(fresh.handled)
    XCTAssertEqual(try reopened.load().current.map(\.id), [sample.id])
  }

  @MainActor
  func testHealthSyncNotificationAdoptsVisibleAlertAndNeverReplaysSameIncident() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 23)))
    let floor = now.addingTimeInterval(-86_400)
    let quietEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 8)))
    let pausedUntil = quietEnd.addingTimeInterval(600)
    try records.saveRecordingReminderSettings(.init(pausedUntil: pausedUntil), at: now)
    try records.updateHealthKitSyncSelection([.weight], enabled: true)
    try records.setSyncNotificationsEnabled(true)
    let run = try records.beginHealthKitSync(.weight, floor: floor, reset: false, at: now)
    try records.finishHealthKitSync(.weight, run: run.run, status: .failed, at: now)
    let first = try records.reconcileSyncDelivery(now: now, calendar: calendar, permitted: true, scheduled: [], delivered: [])
    let receipt = try XCTUnwrap(first.pending.first)
    XCTAssertEqual(receipt.due, pausedUntil)
    let request = try XCTUnwrap(GalaxySSIHealthSyncDelivery.request(receipt, title: "GalaxySSI reminder",
      body: "Open GalaxySSI to review.", now: now))
    XCTAssertTrue(request.content.userInfo.isEmpty)
    XCTAssertTrue(request.content.attachments.isEmpty)
    XCTAssertNil(request.content.sound)
    XCTAssertFalse(request.identifier.contains(receipt.incident.uuidString))
    let retry = try records.beginHealthKitSync(.weight, floor: floor, reset: false, at: now)
    try records.finishHealthKitSync(.weight, run: retry.run, status: .permission, at: now.addingTimeInterval(1))
    let pending = try records.reconcileSyncDelivery(now: now, calendar: calendar, permitted: true,
      scheduled: [receipt.token], delivered: [])
    XCTAssertEqual(pending.pending.first?.token, receipt.token)
    let afterDelivery = pausedUntil.addingTimeInterval(1)
    let adopted = try records.reconcileSyncDelivery(now: afterDelivery, calendar: calendar, permitted: true,
      scheduled: [], delivered: [receipt.token])
    XCTAssertTrue(adopted.pending.isEmpty)
    XCTAssertEqual(adopted.keepDelivered, [receipt.token])
    let archive = try records.load()
    let settings = try XCTUnwrap(archive.recordingReminders?.settings)
    let delivery = try XCTUnwrap(archive.healthKitSyncDelivery)
    XCTAssertEqual(GalaxySSIHealthSyncDelivery.target(token: receipt.token, state: delivery, selected: [.weight],
      incidents: archive.syncIncidents, settings: settings, now: afterDelivery), .weight)
    XCTAssertNil(GalaxySSIHealthSyncDelivery.target(token: receipt.token, state: delivery, selected: [],
      incidents: archive.syncIncidents, settings: settings, now: afterDelivery))
    let dismissed = try records.reconcileSyncDelivery(now: afterDelivery, calendar: calendar, permitted: true,
      scheduled: [], delivered: [])
    XCTAssertTrue(dismissed.pending.isEmpty)
    let current = try XCTUnwrap(archive.syncIncident(.weight))
    try records.acknowledgeHealthKitIncident(current, at: afterDelivery)
    XCTAssertThrowsError(try records.markSyncDeliverySubmitted(receipt, calendar: calendar))
    let handled = try records.reconcileSyncDelivery(now: afterDelivery, calendar: calendar, permitted: true,
      scheduled: [], delivered: [receipt.token])
    XCTAssertTrue(handled.keepDelivered.isEmpty)
    XCTAssertTrue(try records.load().current.isEmpty)
  }

  @MainActor
  func testHealthSyncNotificationDenialAndDeselectDoNotReplayPendingOutages() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date(), floor = Date().addingTimeInterval(-86_400)
    try records.updateHealthKitSyncSelection([.sleep, .weight], enabled: true)
    try records.recordHealthKitAuthorizationFailure([.sleep], status: .permission, at: now)
    try records.setSyncNotificationsEnabled(true)
    try records.recordHealthKitAuthorizationFailure([.sleep, .weight], status: .permission, at: now)
    let waiting = try XCTUnwrap(records.load().healthKitSyncDelivery)
    XCTAssertEqual(Set(waiting.receipts.keys), [.weight])
    try records.updateHealthKitSyncSelection([.weight], enabled: false)
    try records.updateHealthKitSyncSelection([.weight], enabled: true)
    try records.recordHealthKitAuthorizationFailure([.weight], status: .failed, at: now)
    XCTAssertTrue(try XCTUnwrap(records.load().healthKitSyncDelivery).receipts.isEmpty)
    let checkpoint = try records.beginHealthKitSync(.weight, floor: floor, reset: false, at: now)
    _ = try records.commitHealthKitPage(scope: .weight, expected: checkpoint,
      page: .init(rows: [], anchor: nil, providerCount: 0, more: false), at: now)
    try records.recordHealthKitAuthorizationFailure([.weight], status: .permission, at: now)
    let denied = try records.reconcileSyncDelivery(now: now, calendar: .current, permitted: false, scheduled: [], delivered: [])
    XCTAssertTrue(denied.pending.isEmpty)
    let allowed = try records.reconcileSyncDelivery(now: now, calendar: .current, permitted: true, scheduled: [], delivered: [])
    XCTAssertTrue(allowed.pending.isEmpty)
    XCTAssertEqual(try records.load().syncIncidents.count, 2)
  }

  @MainActor
  func testHealthKitSyncIncidentLegacyFailureSurvivesBeginningARetry() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let floor = Date().addingTimeInterval(-86_400)
    var archive = try records.load()
    archive.healthKitSync = ["weight": .init(floor: floor, status: .failed),
                             "sleep": .init(floor: floor, status: .interrupted)]
    try records.commitRestore(archive, receipt: UUID())
    let original = try XCTUnwrap(records.load().syncIncident(.weight))
    XCTAssertNil(original.failedAt)
    _ = try records.beginHealthKitSync(.weight, floor: floor, reset: false)
    XCTAssertEqual(try records.load().syncIncidents, [original])
  }

  @MainActor
  func testHealthKitSyncRecoversExpiredCursorAndRejectsPageAfterLeavingForeground() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let now = Date()
    let oldFloor = now.addingTimeInterval(-90 * 86_400)
    let floor = now.addingTimeInterval(-30 * 86_400)
    let reading = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "c", count: 64), origin: "fixture", name: nil))
    let old = try records.beginHealthKitSync(.weight, floor: oldFloor, reset: false)
    _ = try records.commitHealthKitPage(scope: .weight, expected: old,
      page: .init(rows: [reading], anchor: Data("stale-anchor-fixture".utf8), providerCount: 1, more: false), at: now)
    XCTAssertNil(try Data(contentsOf: file).range(of: Data("stale-anchor-fixture".utf8)))
    var published: [GalaxySSIHealthKitSync.Checkpoint] = []
    let result = try await GalaxySSIHealthKitSync.run(scope: .weight, records: records, floor: floor,
      reset: false, isActive: { true }, read: { checkpoint in
        if checkpoint.anchor != nil { throw GalaxySSIHealthKitSync.Failure.invalidAnchor }
        XCTAssertEqual(checkpoint.floor, floor)
        return .init(rows: [reading], anchor: Data([1]), providerCount: 1, more: false)
      }, onCheckpoint: { published.append($0) })
    XCTAssertEqual(published.count, 3)
    XCTAssertTrue(result.previousCoverageUnverified)
    XCTAssertEqual(result.status, .success)
    XCTAssertEqual(result.insertedThisRun, 0)
    XCTAssertEqual(try records.load().current.map(\.id), [reading.id])
    var active = true
    do {
      _ = try await GalaxySSIHealthKitSync.run(scope: .weight, records: records, floor: floor,
        reset: false, isActive: { active }, read: { _ in
          active = false
          return .init(rows: [], anchor: Data([2]), providerCount: 0, more: false)
        }, onCheckpoint: { _ in })
      XCTFail("A page must not commit after the scene is no longer active.")
    } catch is CancellationError {}
    let saved = try XCTUnwrap(records.load().healthKitSync?["weight"])
    XCTAssertEqual(saved.status, .interrupted)
    XCTAssertEqual(saved.anchor, Data([1]))
    XCTAssertThrowsError(try records.beginHealthKitSync(.steps, floor: floor, reset: false))
  }

  @MainActor
  func testHealthKitImportKeepsOriginsEditsAndTombstones() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let first = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture.a", name: "A"))
    let second = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "b", count: 64), origin: "fixture.b", name: "B"))
    XCTAssertThrowsError(try records.importHealthKit([first, .init(metric: .weight, value: 60)]))
    XCTAssertTrue(try records.load().current.isEmpty)
    XCTAssertEqual(try records.importHealthKit([first, second]), 2)
    var edited = try XCTUnwrap(records.load().current.first { $0.id == first.id })
    edited.value = 67
    try records.write(edited)
    var removed = try XCTUnwrap(records.load().current.first { $0.id == second.id })
    removed.deleted = true
    try records.write(removed)
    XCTAssertEqual(try records.importHealthKit([first, second]), 0)
    XCTAssertEqual(try records.load().current.map(\.value), [67])
  }

  func testSleepReminderCoverageNormalizationAndRevocation() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)))
    let readings = try (1...21).filter { $0 != 2 && $0 != 8 }.map { offset in
      let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: now))
      return GalaxySSIHealthReading(revision: 1, metric: .sleepDuration, measuredAt: date,
        value: offset <= 7 ? 435 : 8, unitOverride: offset <= 7 ? "min" : "h")
    }
    var ledger = GalaxySSIHealthSleepReminder.Ledger()
    ledger.preferences.enabled = true
    ledger.reconcile(current: readings, allowed: true, now: now, calendar: calendar)
    let episode = try XCTUnwrap(ledger.episodes.first)
    XCTAssertEqual(episode.latest.decrease, 45)
    XCTAssertEqual(episode.latest.days.filter { $0.minutes == nil }.count, 2)
    ledger.reconcile(current: readings, allowed: true, now: now.addingTimeInterval(60), calendar: calendar)
    XCTAssertEqual(ledger.episodes, [episode])
    ledger.reconcile(current: Array(readings.dropFirst(2)), allowed: true, now: now, calendar: calendar)
    XCTAssertEqual(ledger.episodes.first?.closed, true)
    ledger.reconcile(current: readings, allowed: false, now: now, calendar: calendar)
    XCTAssertFalse(ledger.episodes.contains { !$0.closed })
  }

  @MainActor
  func testAssistantWeeklyReportKeepsHistoricalScopeAndRechecksSelectedComparisonRows() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
    let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
    let earlier = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: start))
    let recentWeight = GalaxySSIHealthReading(metric: .weight, measuredAt: start, value: 65)
    let previousWeight = GalaxySSIHealthReading(metric: .weight, measuredAt: earlier, value: 64)
    let heart = GalaxySSIHealthReading(metric: .heartRate, measuredAt: start, value: 70)
    for row in [recentWeight, previousWeight, heart] { try records.write(row) }
    try records.setOverviewPermission(true)
    try records.setWeeklyReportAllowed(true)
    let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: start, end: end), metrics: [.weight, .heartRate])
    let current = try records.load().current
    let link = GalaxySSIHealthAnalysis.ReportScope(scope: scope, calendar: calendar, compare: true, current: current)
    XCTAssertEqual(link.comparison, DateInterval(start: earlier, end: start))
    XCTAssertEqual(link.calendar.timeZone, calendar.timeZone)
    XCTAssertEqual(link.interval.duration, 7 * 86_400 - 3_600)
    let weight = try XCTUnwrap(GalaxySSIWeeklyHealthReport(current: current, assistantScope: link, selected: [.weight]))
    XCTAssertNil(weight.sleepEvidence)
    XCTAssertEqual(weight.readings.map(\.id), [recentWeight.id])
    XCTAssertEqual(weight.comparisonReadings.map(\.id), [previousWeight.id])
    XCTAssertNil(GalaxySSIWeeklyHealthReport(current: current, assistantScope: link, selected: [.glucose]))

    var updatedHeart = try XCTUnwrap(current.first { $0.id == heart.id })
    updatedHeart.value = 71
    try records.write(updatedHeart)
    XCTAssertFalse(link.isCurrent(try records.load().current, selected: scope.metrics))
    try records.prepareWeeklyExport(weight, includeRows: false)

    var updatedComparison = try XCTUnwrap(current.first { $0.id == previousWeight.id })
    updatedComparison.value = 63
    try records.write(updatedComparison)
    XCTAssertThrowsError(try records.prepareWeeklyExport(weight, includeRows: true))
    let latest = try records.load().current
    let refreshed = link.refreshed(latest)
    let report = try XCTUnwrap(GalaxySSIWeeklyHealthReport(current: latest, assistantScope: refreshed, selected: [.weight]))
    XCTAssertEqual(report.comparisonReadings.first?.revision, 2)
    XCTAssertEqual(report.interval, scope.interval)
    try records.setOverviewPermission(false)
    XCTAssertThrowsError(try records.prepareWeeklyExport(report, includeRows: true))
    XCTAssertEqual(try records.load().weeklyExportRequests?.count, 1)
  }

  @MainActor
  func testSleepEvidencePinsBothCohortsAcrossDSTAndProtectsWeeklyExport() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)))
    for offset in 1...21 {
      let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: day))
      try records.write(.init(metric: .sleepDuration, measuredAt: date, value: offset <= 7 ? 7 : 8))
    }
    try records.write(.init(metric: .weight, measuredAt: day, value: 60))
    try records.setOverviewPermission(true)
    try records.setWeeklyReportAllowed(true)
    let current = try records.load().current
    let initial = try XCTUnwrap(GalaxySSIHealthSleepReminder.evidence(current, at: day, calendar: calendar, threshold: 45))
    let baseline = try XCTUnwrap(initial.contributors(current, baseline: true))
    let recent = try XCTUnwrap(initial.contributors(current, baseline: false))
    XCTAssertEqual(baseline.count, 14)
    XCTAssertEqual(recent.count, 7)
    let report = try XCTUnwrap(GalaxySSIWeeklyHealthReport(current: current, sleepEvidence: initial))
    XCTAssertNil(report.assistantScope)
    XCTAssertEqual(report.metrics, [.sleepDuration])
    XCTAssertEqual(report.readings, recent)
    XCTAssertEqual(report.interval.duration, 7 * 86_400 - 3_600)
    try records.prepareWeeklyExport(report, includeRows: false)
    XCTAssertEqual(try records.load().weeklyExportRequests?.last?.includeRows, false)

    var edited = try XCTUnwrap(baseline.first)
    edited.value = 9
    try records.write(edited)
    let updated = try records.load().current
    XCTAssertNil(initial.contributors(updated, baseline: true))
    XCTAssertNil(initial.contributors(updated, baseline: false))
    XCTAssertNil(GalaxySSIWeeklyHealthReport(current: updated, sleepEvidence: initial))
    XCTAssertThrowsError(try records.prepareWeeklyExport(report, includeRows: true))
    let latest = try XCTUnwrap(GalaxySSIHealthSleepReminder.evidence(updated, at: day, calendar: calendar, threshold: 45))
    let refreshed = try XCTUnwrap(GalaxySSIWeeklyHealthReport(current: updated, sleepEvidence: latest))
    XCTAssertEqual(refreshed.readings, recent)
    try records.setOverviewPermission(false)
    XCTAssertThrowsError(try records.prepareWeeklyExport(refreshed, includeRows: true))
    XCTAssertEqual(try records.load().weeklyExportRequests?.count, 1)
  }

  @MainActor
  func testReportDuplicateEvidenceUsesExactRevisionAndAtomicConsent() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("records")
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets,
                                             fixtureDirectory: root, restoreRecordsFile: file)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "fixture.pdf")
    let original = try XCTUnwrap(store.list().originals.first)
    let beforeLink = try store.previewRemoval(original)
    let date = Date()
    try records.write(.init(metric: .weight, measuredAt: date, value: 65))
    func item(_ page: Int) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
        page: page, region: 0, fromOCR: true)
      return .init(version: UUID(), source: source, excerpt: "fixture",
        reading: .init(metric: .weight, measuredAt: date, value: 65, reportSource: source))
    }
    let first = item(0), second = item(1)
    try records.stageReportItem(first, replacing: nil)
    try records.stageReportItem(second, replacing: nil)
    let target = try XCTUnwrap(GalaxySSIHealthReportReview.exactTarget(for: first, current: records.load().current))
    let stale = GalaxySSIHealthReportReview.Target(record: target.record, revision: target.revision + 1)
    XCTAssertThrowsError(try records.linkReportDuplicates([first.version: target, second.version: stale],
                                                           original: original, store: store))
    XCTAssertNil(try records.load().reportEvidence)
    XCTAssertEqual(try records.load().reportReview?.count, 2)
    try records.linkReportDuplicates([first.version: target], original: original, store: store)
    XCTAssertThrowsError(try store.remove(beforeLink))
    XCTAssertEqual(try store.previewRemoval(original).links.count, 1)
    XCTAssertThrowsError(try records.stageReportItem(first, replacing: nil))
    var edited = try XCTUnwrap(records.load().current.first)
    edited.notes = "later"
    try records.write(edited)
    XCTAssertThrowsError(try records.linkReportDuplicates([second.version: target], original: original, store: store))
    let archive = try records.load()
    let links = GalaxySSIHealthReportReview.linked(original: original, revisions: archive.revisions,
      current: archive.current, evidence: archive.reportEvidence ?? [])
    XCTAssertEqual(links.first?.reading.revision, target.revision)
    XCTAssertTrue(links.first?.secondary == true)
    XCTAssertEqual(archive.current.count, 1)
    let exported = try GalaxySSIHealthReportReview.export(links, pdf: store.read(original))
    XCTAssertNotNil(exported.range(of: Data("measurements.csv".utf8)))
    XCTAssertNotNil(exported.range(of: Data("original.pdf".utf8)))
    XCTAssertNil(exported.range(of: Data("later".utf8)))
    let deletion = try records.previewMetricDeletion(edited.metric)
    try records.deleteMetricHistory(deletion)
    XCTAssertEqual(try records.load().reportEvidence?.count, 0)
    XCTAssertEqual(try store.read(original), pdf)
  }

  func testReviewNotificationPlanDefersAndDoesNotReplayDelivery() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 23)))
    let job = GalaxySSIHealthReviewReminders.Job(target: UUID(), kind: .report, versions: [UUID()], at: now)
    var state = GalaxySSIHealthReviewReminders.State()
    state.enabled = true
    state.notificationPreferences = .init(enabled: true)
    let plan = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: now,
      calendar: calendar, permitted: true, scheduled: [], delivered: [])
    var ticket = try XCTUnwrap(plan.pending.first)
    XCTAssertEqual(calendar.component(.hour, from: ticket.due), 8)
    XCTAssertFalse(ticket.identifier.contains(job.target.uuidString))
    let request = GalaxySSIHealthReviewDelivery.request(ticket, title: "GalaxySSI reminder",
      body: "Open GalaxySSI to review.", now: now)
    XCTAssertTrue(request.content.userInfo.isEmpty)
    XCTAssertTrue(request.content.attachments.isEmpty)
    XCTAssertNil(request.content.sound)
    XCTAssertEqual(request.identifier, ticket.identifier)
    state.deliveries = plan.tickets
    let later = ticket.due.addingTimeInterval(5)
    let adopted = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: true, scheduled: [], delivered: [ticket.token])
    XCTAssertTrue(adopted.pending.isEmpty)
    XCTAssertEqual(adopted.keepDelivered, [ticket.token])
    state.deliveries = adopted.tickets
    ticket = try XCTUnwrap(adopted.tickets[job.key])
    XCTAssertTrue(ticket.submitted)
    let dismissed = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: true, scheduled: [], delivered: [])
    XCTAssertTrue(dismissed.pending.isEmpty)
    XCTAssertEqual(GalaxySSIHealthReviewDelivery.target(for: ticket.token, jobs: [job], state: state, now: later), job)
    let revised = GalaxySSIHealthReviewReminders.Job(target: job.target, kind: .report, versions: [UUID()], at: now)
    XCTAssertNil(GalaxySSIHealthReviewDelivery.target(for: ticket.token, jobs: [revised], state: state, now: later))
    let snooze = later.addingTimeInterval(3_600)
    state.actions[job.key] = .init(versions: job.versions, action: .snoozed(snooze))
    let delayed = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: true, scheduled: [], delivered: [ticket.token])
    XCTAssertEqual(delayed.pending.first?.due, snooze)
    XCTAssertNotEqual(delayed.pending.first?.token, ticket.token)
    XCTAssertTrue(delayed.keepDelivered.isEmpty)
    state.notificationPreferences?.pausedUntil = snooze.addingTimeInterval(600)
    state.deliveries = delayed.tickets
    let paused = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: true, scheduled: Set(delayed.pending.map(\.token)), delivered: [])
    XCTAssertEqual(paused.pending.first?.due, state.notificationPreferences?.pausedUntil)
    let denied = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: false, scheduled: [], delivered: [])
    XCTAssertTrue(denied.pending.isEmpty)
    state.deliveries = denied.tickets
    let reauthorized = GalaxySSIHealthReviewDelivery.plan(jobs: [job], state: state, now: later,
      calendar: calendar, permitted: true, scheduled: [], delivered: [])
    XCTAssertTrue(reauthorized.pending.isEmpty)
  }

  @MainActor
  func testReviewNotificationOptInDoesNotReplayExistingDraftsAndRoutesExactVersion() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    let old = GalaxySSIHealthReviewReminders.TableDraft(id: UUID(), name: "private-old.csv", at: now,
      data: data, mapping: mapping, worksheet: nil, retainOriginal: false)
    try records.saveTableReview(old, replacing: nil)
    try records.setReviewRemindersEnabled(true)
    let prefs = GalaxySSIHealthReviewDelivery.Preferences(enabled: true, quietStart: 0, quietEnd: 0)
    try records.setReviewNotificationPreferences(prefs)
    let fresh = GalaxySSIHealthReviewReminders.TableDraft(id: UUID(), name: "private-new.csv", at: now,
      data: data, mapping: mapping, worksheet: nil, retainOriginal: false)
    try records.saveTableReview(fresh, replacing: nil)
    let plan = try records.reconcileReviewDelivery(now: now, calendar: .current, permitted: true,
      scheduled: [], delivered: [], availableOriginals: [])
    XCTAssertEqual(plan.pending.count, 1)
    let ticket = try XCTUnwrap(plan.pending.first)
    XCTAssertEqual(ticket.versions, [fresh.version])
    try records.markReviewDeliverySubmitted(ticket, calendar: .current)
    let archive = try records.load()
    let state = try XCTUnwrap(archive.reviewReminderState)
    XCTAssertEqual(GalaxySSIHealthReviewDelivery.target(for: ticket.token, jobs: GalaxySSIHealthReviewReminders.jobs(in: archive),
      state: state, now: ticket.due)?.target, fresh.id)
    try records.setReviewNotificationPreferences(.init(enabled: false))
    try records.setReviewNotificationPreferences(prefs)
    let after = try records.reconcileReviewDelivery(now: now, calendar: .current, permitted: true,
      scheduled: [ticket.token], delivered: [], availableOriginals: [])
    XCTAssertTrue(after.pending.isEmpty)
    XCTAssertEqual(try records.load().tableReviews?.count, 2)
    XCTAssertTrue(try records.load().current.isEmpty)
  }

  @MainActor
  func testReviewReminderActionsDoNotConfirmAndTableCommitClearsDraft() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    let draft = GalaxySSIHealthReviewReminders.TableDraft(id: UUID(), name: "fixture.csv", at: now,
      data: data, mapping: mapping, worksheet: nil, retainOriginal: false)
    try records.saveTableReview(draft, replacing: nil)
    try records.setReviewRemindersEnabled(true)
    var archive = try records.load()
    let job = try XCTUnwrap(GalaxySSIHealthReviewReminders.jobs(in: archive).first)
    try records.updateReviewReminder(job, action: .snoozed(now.addingTimeInterval(60)))
    archive = try records.load()
    let state = try XCTUnwrap(archive.reviewReminderState)
    XCTAssertTrue(GalaxySSIHealthReviewReminders.visible([job], state: state, now: now).isEmpty)
    XCTAssertEqual(GalaxySSIHealthReviewReminders.visible([job], state: state, now: now.addingTimeInterval(61)), [job])
    try records.updateReviewReminder(job, action: .handled)
    XCTAssertTrue(try records.load().current.isEmpty)
    XCTAssertEqual(try records.load().tableReviews?.first?.id, draft.id)
    let sibling = GalaxySSIHealthReviewReminders.TableDraft(id: UUID(), name: "another.csv", at: now,
      data: data, mapping: mapping, worksheet: nil, retainOriginal: true)
    try records.saveTableReview(sibling, replacing: nil)
    var changed = draft
    changed.version = UUID()
    try records.saveTableReview(changed, replacing: draft.version)
    XCTAssertThrowsError(try records.discardTableReview(draft))
    XCTAssertThrowsError(try records.importTable(data, name: draft.name, json: false, mapping: mapping,
      expected: [.ready], reviewVersion: draft.version))
    let refreshed = try records.load()
    let visible = GalaxySSIHealthReviewReminders.visible(GalaxySSIHealthReviewReminders.jobs(in: refreshed),
      state: try XCTUnwrap(refreshed.reviewReminderState), now: now)
    XCTAssertEqual(Set(visible.map(\.target)), [draft.id, sibling.id])
    XCTAssertEqual(try records.importTable(data, name: draft.name, json: false, mapping: mapping,
                                           expected: [.ready], retainOriginal: false, reviewVersion: changed.version), 1)
    XCTAssertEqual(try records.load().tableBatches?.first?.data, Data())
    XCTAssertEqual(GalaxySSIHealthReviewReminders.jobs(in: try records.load()).map(\.target), [sibling.id])
    XCTAssertEqual(try records.undoTableBatch(XCTUnwrap(records.load().tableBatches?.first?.id)), 1)
    XCTAssertEqual(GalaxySSIHealthReviewReminders.jobs(in: try records.load()).map(\.target), [sibling.id])
    XCTAssertThrowsError(try records.updateReviewReminder(job, action: .handled))
  }

  @MainActor
  func testReportReviewReminderUsesExactVersionsAndStableCursor() throws {
    let now = Date()
    var archive = GalaxySSIHealthRecords.Archive()
    func item(original: UUID, region: Int) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original, sha256: String(repeating: "a", count: 64),
        page: 0, region: region, fromOCR: true)
      return .init(version: UUID(), source: source, excerpt: "fixture",
                   reading: .init(metric: .weight, measuredAt: now, value: 65, reportSource: source))
    }
    let original = UUID()
    archive.reportReview = (0..<32).map { _ in item(original: UUID(), region: 0) } + [item(original: original, region: 0)]
    let all = GalaxySSIHealthReviewReminders.jobs(in: archive)
    let first = GalaxySSIHealthReviewReminders.page(all, after: nil)
    let second = GalaxySSIHealthReviewReminders.page(all, after: try XCTUnwrap(first.jobs.last))
    XCTAssertEqual(first.jobs.count, 30)
    XCTAssertTrue(first.hasMore)
    XCTAssertEqual(second.jobs.count, 3)
    XCTAssertFalse(second.hasMore)
    XCTAssertEqual(first.jobs + second.jobs, all)
    let job = try XCTUnwrap(all.first { $0.target == original })
    var state = GalaxySSIHealthReviewReminders.State()
    state.enabled = true
    state.actions[job.key] = .init(versions: job.versions, action: .handled)
    XCTAssertFalse(GalaxySSIHealthReviewReminders.visible(all, state: state, now: now).contains(job))
    archive.reportReview?.append(item(original: original, region: 1))
    let next = GalaxySSIHealthReviewReminders.jobs(in: archive)
    XCTAssertEqual(next.count, all.count)
    XCTAssertTrue(GalaxySSIHealthReviewReminders.visible(next, state: state, now: now).contains {
      $0.target == original && $0.versions.count == 2
    })
  }

  @MainActor
  func testRecognitionCheckpointResumesAndCancellationRejectsLatePages() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "fixture.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: Date(), bytes: 1, sha256: String(repeating: "a", count: 64))
    try records.enqueueRecognition(original: original, pageCount: 2)
    let job = try XCTUnwrap(records.load().recognitionJobs?.first)
    let run = try records.beginRecognitionJob(id: job.id, expected: job.version)
    let bounds = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    let line = GalaxySSIHealthRecognitionJobs.line(.init(id: 1, text: "fixture value", bounds: bounds, highlight: nil))
    let reordered = GalaxySSIHealthRecognitionJobs.line(.init(id: 8, text: "fixture value", bounds: bounds, highlight: nil))
    XCTAssertEqual(line.id, reordered.id)
    let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256, page: 0,
      region: line.ordinal, fromOCR: true, evidenceKey: line.id)
    let moved = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256, page: 0,
      region: reordered.ordinal, fromOCR: true, evidenceKey: reordered.id)
    XCTAssertEqual(Set([source, moved]).count, 1)
    XCTAssertNotEqual(source, .init(original: original.id, sha256: original.sha256, page: 0,
                                   region: line.ordinal, fromOCR: true))
    let first = GalaxySSIHealthRecognitionJobs.Page(index: 0, fromOCR: true, lines: [line])
    let second = GalaxySSIHealthRecognitionJobs.Page(index: 1, fromOCR: true, lines: [line])
    try records.commitRecognitionPage(id: job.id, run: run, page: first)
    let saved = try XCTUnwrap(records.load().recognitionJobs?.first)
    XCTAssertThrowsError(try records.beginRecognitionJob(id: job.id, expected: job.version))
    let resumed = try records.beginRecognitionJob(id: job.id, expected: saved.version)
    XCTAssertThrowsError(try records.commitRecognitionPage(id: job.id, run: run, page: second))
    try records.finishRecognitionJob(id: job.id, run: resumed, phase: .cancelled)
    XCTAssertThrowsError(try records.commitRecognitionPage(id: job.id, run: resumed, page: second))
    let archive = try records.load()
    let cancelled = try XCTUnwrap(archive.recognitionJobs?.first)
    XCTAssertThrowsError(try records.beginRecognitionJob(id: job.id, expected: cancelled.version))
    XCTAssertEqual(archive.recognitionJobs?.first?.pages, [first])
    XCTAssertTrue(archive.current.isEmpty)
    XCTAssertNil(try Data(contentsOf: file).range(of: Data("fixture value".utf8)))
  }

  @MainActor
  func testRecognitionRepairRequiresExactOriginalAndCannotResurrectRemoval() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let file = root.appendingPathComponent("records")
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root, restoreRecordsFile: file)
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "report.pdf", acquisition: .camera)
    let original = try XCTUnwrap(store.list().originals.first)
    try records.enqueueRecognition(original: original, pageCount: 1)
    try FileManager.default.removeItem(at: root.appendingPathComponent(original.id.uuidString))
    XCTAssertThrowsError(try store.repairRecognitionOriginal(original, data: pdf + Data([0])))
    try store.repairRecognitionOriginal(original, data: pdf)
    XCTAssertEqual(try store.list().originals, [original])
    XCTAssertEqual(try store.read(original), pdf)
    XCTAssertEqual(try records.load().recognitionJobs?.first?.original, original)
    try store.remove(store.previewRemoval(original))
    XCTAssertThrowsError(try store.repairRecognitionOriginal(original, data: pdf))
    XCTAssertTrue(try store.list().originals.isEmpty)
  }

  @MainActor
  func testReportReviewBatchIsAtomicAndVersionPinned() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "report.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: Date(), bytes: 1, sha256: String(repeating: "a", count: 64))
    let date = Date()
    func item(_ page: Int, value: Decimal) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
        page: page, region: 0, fromOCR: true)
      return .init(version: UUID(), source: source, excerpt: "Fixture",
        reading: .init(metric: .weight, measuredAt: date, value: value, reportSource: source))
    }
    let first = item(0, value: 61)
    let second = item(1, value: 62)
    try records.stageReportItem(first, replacing: nil)
    try records.stageReportItem(second, replacing: nil)
    let updated = item(1, value: 63)
    try records.stageReportItem(updated, replacing: second.version)
    XCTAssertThrowsError(try records.confirmReportItems([first.version, second.version], original: original))
    try records.write(.init(metric: .weight, measuredAt: date, value: 63))
    XCTAssertThrowsError(try records.confirmReportItems([first.version, updated.version], original: original))
    XCTAssertEqual(try records.load().current.count, 1)
    XCTAssertEqual(try records.load().reportReview?.count, 2)
    try records.confirmReportItems([first.version], original: original)
    XCTAssertEqual(try records.load().current.count, 2)
    XCTAssertEqual(try records.load().reportReview?.map(\.version), [updated.version])
  }

  @MainActor
  func testMetricDeletionIncludesSoftDeletedHistoryAndKeepsOtherMetricsAndOriginals() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: root.appendingPathComponent("records"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try originals.store(pdf, name: "fixture.pdf")
    let original = try XCTUnwrap(originals.list().originals.first)
    let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-01T12:00:00Z"))
    let manual = GalaxySSIHealthReading(metric: .weight, measuredAt: date, value: 60)
    try records.write(manual)
    let table = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    let parsed = try GalaxySSIHealthTableImport.parse(table, json: false)
    let rows = try GalaxySSIHealthTableImport.preview(parsed, mapping: mapping, current: records.load().current)
    let row = try XCTUnwrap(rows.first)
    let target = try XCTUnwrap(row.duplicateTarget)
    XCTAssertEqual(try records.importTable(table, name: "fixture.csv", json: false, mapping: mapping,
                                           expected: [.duplicate], linkDuplicates: [row.id: target]), 0)
    var tombstone = try XCTUnwrap(records.load().current.first)
    tombstone.deleted = true
    try records.write(tombstone, rememberDeletion: true)
    let apple = GalaxySSIHealthReading(metric: .weight, measuredAt: date.addingTimeInterval(100), value: 61,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    XCTAssertEqual(try records.importHealthKit([apple]), 1)
    func report(_ metric: GalaxySSIHealthMetric, region: Int) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
        page: 0, region: region, fromOCR: true)
      return .init(version: UUID(), source: source, excerpt: "Fixture",
        reading: .init(metric: metric, measuredAt: date, value: 65, reportSource: source))
    }
    let reviewed = report(.weight, region: 0)
    let staged = report(.weight, region: 1)
    let otherStaged = report(.heartRate, region: 2)
    try records.stageReportItem(reviewed, replacing: nil)
    try records.confirmReportItems([reviewed.version], original: original)
    try records.stageReportItem(staged, replacing: nil)
    try records.stageReportItem(otherStaged, replacing: nil)
    try records.storeDraft(.init(metric: .weight))
    try records.setHealthOnlinePermission(true)
    let other = GalaxySSIHealthReading(metric: .heartRate, measuredAt: date, value: 70)
    try records.write(other)

    let preview = try records.previewMetricDeletion(.weight)
    XCTAssertEqual(preview.scope.sources, [.manual: 1, .appleHealth: 1, .report: 1])
    XCTAssertEqual(preview.scope.earliest, date)
    XCTAssertEqual(preview.scope.latest, apple.measuredAt)
    XCTAssertEqual(preview.scope.drafts, 2)
    try records.deleteMetricHistory(preview)

    let archive = try records.load()
    XCTAssertEqual(archive.current.map(\.id), [other.id])
    XCTAssertEqual(archive.revisions.map(\.id), [other.id])
    XCTAssertNil(archive.draft)
    XCTAssertNil(archive.lastMeasurementDeletion)
    XCTAssertEqual(archive.reportReview?.map(\.version), [otherStaged.version])
    XCTAssertEqual(archive.tableEvidence?.count, 0)
    XCTAssertEqual(archive.tableBatches?.first?.data, table)
    XCTAssertEqual(try originals.read(original), pdf)
    XCTAssertNotNil(archive.healthOnlinePermission)
    XCTAssertEqual(archive.metricDeletionHistory?.first?.scope, preview.scope)
    XCTAssertEqual(try records.importHealthKit([apple]), 1)
  }

  @MainActor
  func testMetricDeletionRejectsChangedRevisionWithSamePreviewCounts() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.write(.init(metric: .weight, value: 60))
    let before = try records.previewMetricDeletion(.weight)
    var updated = try XCTUnwrap(records.load().current.first)
    updated.value = 61
    try records.write(updated)
    let after = try records.previewMetricDeletion(.weight)
    XCTAssertEqual(before.scope, after.scope)
    XCTAssertThrowsError(try records.deleteMetricHistory(before)) { error in
      guard case GalaxySSIHealthRecords.Failure.stale = error else { return XCTFail("Expected stale preview") }
    }
    XCTAssertEqual(try records.load().current.first?.value, 61)
    XCTAssertNil(try records.load().metricDeletionHistory)
    try records.storeDraft(.init(metric: .heartRate))
    try records.deleteMetricHistory(after)
    XCTAssertEqual(try records.load().draft?.metric, .heartRate)
    XCTAssertTrue(try records.previewMetricDeletion(.weight).scope.isEmpty)
  }

  @MainActor
  func testAppleHealthLocalEraseKeepsSameMetricFromOtherSourcesAndLeavesPermissionsAlone() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(),
                                         isolatedFile: root.appendingPathComponent("records"))
    let now = Date()
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let bluetooth = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet)
      .reading(conditions: "")
    let manual = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 120, diastolic: 80)
    let apple = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 120, diastolic: 80,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    let otherApple = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 65,
      healthKitSource: .init(key: String(repeating: "b", count: 64), origin: "fixture", name: nil))
    try records.write(bluetooth)
    try records.write(manual, allowDuplicate: true)
    XCTAssertEqual(try records.importHealthKit([apple, otherApple]), 2)
    try records.updateSourceAttention { $0.selected = [.bloodPressure, .weight] }
    let attention = try records.loadSourceAttention()
    let source = GalaxySSIHealthReportReview.Source(original: UUID(), sha256: String(repeating: "c", count: 64),
                                                   page: 0, region: 0, fromOCR: true)
    let report = GalaxySSIHealthReportReview.Item(version: UUID(), source: source, excerpt: "Fixture",
      reading: .init(metric: .bloodPressure, measuredAt: now, value: 121, diastolic: 79, reportSource: source))
    try records.stageReportItem(report, replacing: nil)
    let archivedApple = try XCTUnwrap(records.load().current.first { $0.id == apple.id })
    try records.storeDraft(.init(existing: archivedApple, metric: .bloodPressure))
    let withDraft = try records.previewMetricDeletion(.bloodPressure, filter: .appleHealth)
    XCTAssertEqual(withDraft.scope.drafts, 1)
    XCTAssertEqual(withDraft.scope.sources, [.appleHealth: 1])
    var tombstone = archivedApple
    tombstone.deleted = true
    tombstone.measuredAt = now.addingTimeInterval(-120)
    try records.write(tombstone, rememberDeletion: true)
    XCTAssertThrowsError(try records.deleteMetricHistory(withDraft))

    try records.storeDraft(.init(metric: .bloodPressure))
    let reviewed = try records.previewMetricDeletion(.bloodPressure, filter: .appleHealth)
    XCTAssertEqual(reviewed.scope.count, 1)
    XCTAssertEqual(reviewed.scope.drafts, 0)
    XCTAssertEqual(reviewed.scope.earliest, tombstone.measuredAt)
    XCTAssertEqual(reviewed.scope.latest, now)
    try records.deleteMetricHistory(reviewed)

    let archive = try records.load()
    XCTAssertEqual(Set(archive.current.map(\.id)), Set([manual.id, bluetooth.id, otherApple.id]))
    XCTAssertFalse(archive.revisions.contains { $0.id == apple.id })
    XCTAssertEqual(archive.draft?.metric, .bloodPressure)
    XCTAssertNil(archive.lastMeasurementDeletion)
    XCTAssertEqual(archive.reportReview?.map(\.version), [report.version])
    XCTAssertEqual(archive.metricDeletionHistory?.first?.scope.filter, .appleHealth)
    XCTAssertNil(archive.derivesOverview)
    XCTAssertEqual(try records.loadSourceAttention(), attention)
    XCTAssertEqual(try records.importHealthKit([apple]), 1)
  }

  @MainActor
  func testAppleHealthLocalEraseClearsOnlyDraftLinkedToRemovedCopy() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let copy = GalaxySSIHealthReading(metric: .weight, value: 65,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: nil, name: nil))
    XCTAssertEqual(try records.importHealthKit([copy]), 1)
    let saved = try XCTUnwrap(records.load().current.first)
    try records.storeDraft(.init(existing: saved, metric: .weight))
    let reviewed = try records.previewMetricDeletion(.weight, filter: .appleHealth)
    XCTAssertEqual(reviewed.scope.drafts, 1)
    try records.deleteMetricHistory(reviewed)
    XCTAssertNil(try records.load().draft)
    XCTAssertTrue(try records.previewMetricDeletion(.weight, filter: .appleHealth).scope.isEmpty)
  }

  @MainActor
  func testHealthBackupHistoryKeepsVerifiedSaveAfterInterruptionAndPruning() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let history = GalaxySSIHealthBackupHistory(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let id = try history.begin()
    let data = Data("synthetic sealed package".utf8)
    try history.publish(data, id: id)
    let first = try history.beginSave(id)
    let destination = root.appendingPathComponent("external")
    try data.write(to: destination)
    XCTAssertTrue(try GalaxySSIHealthBackupHistory.verifyDestination(destination, entry: first))
    try history.finishSave(id, verified: true)
    let saved = try XCTUnwrap(history.entries().first?.lastVerifiedAt)
    _ = try history.beginSave(id)
    let interrupted = try history.begin()
    try history.recover()
    let recovered = try history.entries()
    XCTAssertEqual(recovered.first { $0.id == interrupted }?.generation, .interrupted)
    XCTAssertEqual(recovered.first { $0.id == id }?.latestSave, .interrupted)
    for _ in 0..<2 { try history.publish(data, id: history.begin()) }
    let old = try XCTUnwrap(history.entries().first { $0.id == id })
    XCTAssertEqual(old.lastVerifiedAt, saved)
    XCTAssertFalse(history.hasCopy(old))
    XCTAssertThrowsError(try history.readCopy(old))
  }

  @MainActor
  func testProtectedHealthPDFRetainsExactBytesAndEnforcesExtractionPermission() throws {
    let bytes = NSMutableData()
    let consumer = try XCTUnwrap(CGDataConsumer(data: bytes as CFMutableData))
    let options: [String: Any] = [
      kCGPDFContextUserPassword as String: "fixture-reader",
      kCGPDFContextOwnerPassword as String: "fixture-owner",
      kCGPDFContextAllowsCopying as String: false
    ]
    var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, options as CFDictionary))
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
    let pdf = bytes as Data
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.pageCount(pdf)) {
      guard case GalaxySSIHealthPDFText.Failure.locked = $0 else { return XCTFail("Expected locked PDF") }
    }
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.pageCount(pdf, password: "wrong")) {
      guard case GalaxySSIHealthPDFText.Failure.incorrectPassword = $0 else { return XCTFail("Expected wrong password") }
    }
    XCTAssertEqual(try GalaxySSIHealthPDFText.pageCount(pdf, password: "fixture-reader"), 1)
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.read(pdf, page: 0, password: "fixture-reader")) {
      guard case GalaxySSIHealthPDFText.Failure.extractionRestricted = $0 else { return XCTFail("Expected restricted extraction") }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    try store.store(pdf, name: "protected.pdf")
    let original = try XCTUnwrap(store.list().originals.first)
    XCTAssertEqual(try store.read(original), pdf)
  }

  @MainActor
  func testDailyHealthReminderDoesNotBackfillAndRejectsStaleActions() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12)))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var settings = try records.loadRecordingReminders(at: now, calendar: calendar).settings
    settings.enabled = true
    settings.notifications = true
    try records.saveRecordingReminderSettings(settings, at: now)
    XCTAssertTrue(try records.loadRecordingReminders(at: now, calendar: calendar).history.isEmpty)
    let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: now))
    let ledger = try records.loadRecordingReminders(at: later, calendar: calendar)
    let first = try XCTUnwrap(ledger.history.first)
    XCTAssertEqual(ledger.history.count, 1)
    try records.updateRecordingReminder(first, complete: false, at: later, calendar: calendar)
    XCTAssertThrowsError(try records.updateRecordingReminder(first, complete: true, at: later, calendar: calendar))
    let refreshed = try records.loadRecordingReminders(at: later, calendar: calendar)
    XCTAssertEqual(refreshed.history.first?.snoozedUntil, later.addingTimeInterval(3_600))
    XCTAssertEqual(refreshed.upcoming(at: later, calendar: calendar).first?.1, later.addingTimeInterval(3_600))
    let snoozed = try XCTUnwrap(refreshed.history.first)
    try records.updateRecordingReminder(snoozed, complete: true, at: later, calendar: calendar)
    XCTAssertNotEqual(try records.loadRecordingReminders(at: later, calendar: calendar)
      .upcoming(at: later, calendar: calendar).first?.0, snoozed.day)
  }

  @MainActor
  func testExactTableDuplicateLinksToReviewedRevisionWithoutRewritingMeasurement() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-01-01T12:00:00Z"))
    try records.write(.init(metric: .weight, measuredAt: date, value: 60))
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n60,2025-01-01T12:00:10Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    let table = try GalaxySSIHealthTableImport.parse(data, json: false)
    let rows = try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: records.load().current)
    XCTAssertEqual(rows.map(\.status), [.duplicate, .duplicate])
    let target = try XCTUnwrap(rows[0].duplicateTarget)
    XCTAssertNil(rows[1].duplicateTarget)
    XCTAssertEqual(try records.importTable(data, name: "fixture.csv", json: false, mapping: mapping,
      expected: rows.map(\.status), linkDuplicates: [rows[0].id: target]), 0)
    var archive = try records.load()
    XCTAssertEqual(archive.revisions.count, 1)
    let batch = try XCTUnwrap(archive.tableBatches?.first)
    XCTAssertEqual(batch.linked, 1)
    var edited = try XCTUnwrap(archive.current.first)
    edited.notes = "later edit"
    try records.write(edited)
    XCTAssertThrowsError(try records.importTable(data, name: "fixture.csv", json: false, mapping: mapping,
      expected: rows.map(\.status), linkDuplicates: [rows[0].id: target]))
    archive = try records.load()
    let linked = GalaxySSIHealthTableImport.linkedReadings(batch: batch, revisions: archive.revisions,
      current: archive.current, evidence: archive.tableEvidence ?? [])
    XCTAssertEqual(linked.first?.reading.revision, 1)
    XCTAssertTrue(linked.first?.secondary == true)
    let zip = try GalaxySSIHealthTableImport.exportLinkedReadings(linked, batch: batch)
    XCTAssertNotNil(zip.range(of: data))
    XCTAssertEqual(try records.undoTableBatch(batch.id), 0)
    XCTAssertTrue(try records.load().tableEvidence?.isEmpty == true)
    XCTAssertEqual(try records.load().current.first?.notes, "later edit")
  }

  @MainActor
  func testUndoMeasurementRestoresExactSourceAndRejectsConflictsAndStaleVersions() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    XCTAssertEqual(try records.importTable(data, name: "weight.csv", json: false, mapping: mapping,
                                           expected: [.ready]), 1)
    let original = try XCTUnwrap(records.load().current.first)
    let oldEditor = GalaxySSIHealthDraft(existing: original)
    try records.storeDraft(oldEditor)
    var tombstone = original
    tombstone.deleted = true
    try records.write(tombstone, rememberDeletion: true)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let deletion = try XCTUnwrap(reopened.load().lastMeasurementDeletion)
    XCTAssertEqual(deletion.revision, 2)
    XCTAssertTrue(try reopened.load().current.isEmpty)
    XCTAssertNil(try reopened.load().draft)
    XCTAssertThrowsError(try reopened.storeDraft(oldEditor)) {
      guard case GalaxySSIHealthRecords.Failure.stale = $0 else { return XCTFail("Expected stale editor") }
    }
    XCTAssertThrowsError(try reopened.undoMeasurementDeletion(.init(id: UUID(), revision: 2)))
    let conflict = GalaxySSIHealthReading(metric: .weight, measuredAt: original.measuredAt, value: 60)
    try reopened.write(conflict)
    XCTAssertThrowsError(try reopened.undoMeasurementDeletion(deletion))
    XCTAssertEqual(try reopened.load().lastMeasurementDeletion, deletion)
    var removeConflict = try XCTUnwrap(reopened.load().current.first)
    removeConflict.deleted = true
    try reopened.write(removeConflict)
    let restored = try reopened.undoMeasurementDeletion(deletion)
    XCTAssertEqual(restored.id, original.id)
    XCTAssertEqual(restored.revision, 3)
    XCTAssertEqual(restored.tableSource, original.tableSource)
    XCTAssertThrowsError(try reopened.storeDraft(oldEditor))
    try reopened.storeDraft(.init(existing: restored))
    XCTAssertEqual(try reopened.load().draft?.existing?.revision, 3)
    XCTAssertNil(try reopened.load().lastMeasurementDeletion)
    XCTAssertThrowsError(try reopened.undoMeasurementDeletion(deletion))
  }

  func testSavedBluetoothHistoryKeepsExactDeviceAndBothDates() throws {
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let now = Date()
    let sameName = (0..<34).map { index -> GalaxySSIHealthReading in
      let receipt = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now.addingTimeInterval(Double(index)),
        packet: packet, deviceName: "Same monitor")
      var reading = receipt.reading(conditions: "")
      reading.measuredAt = now.addingTimeInterval(Double(-index - 60))
      return reading
    }
    var tombstone = sameName[0]
    tombstone.id = UUID()
    tombstone.deleted = true
    let history = GalaxySSIHealthBluetoothHistory(current: sameName + [tombstone,
      .init(metric: .bloodPressure, value: 120, diastolic: 80)])
    XCTAssertEqual(history.devices.count, 34)
    XCTAssertEqual(history.devices.dropFirst(30).count, 4)
    let device = try XCTUnwrap(history.devices.first)
    XCTAssertEqual(device.name, "Same monitor")
    XCTAssertEqual(history.readings(for: device.id).map(\.id), [sameName[0].id])
    XCTAssertEqual(device.latest.measuredAt, now.addingTimeInterval(-60))
    XCTAssertEqual(device.latest.bluetoothReceipt?.receivedAt, now)
    XCTAssertEqual(Set(history.devices.map(\.ordinal)).count, 34)
  }

  @MainActor
  func testSavedBluetoothHistoryTracksPrivacyAndOrdersOnlySelectedDeviceRecords() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let now = Date()
    let id = UUID()
    let newest = GalaxySSIHealthBluetoothReceipt(device: id, receivedAt: now, packet: packet, deviceName: " ")
      .reading(conditions: "")
    let older = GalaxySSIHealthBluetoothReceipt(device: id, receivedAt: now.addingTimeInterval(-90),
                                                 packet: packet, deviceName: "Monitor")
      .reading(conditions: "")
    let other = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet, deviceName: "Monitor")
      .reading(conditions: "")
    try records.write(newest)
    try records.write(older)
    try records.write(other)
    XCTAssertNil(try GalaxySSIHealthBluetoothHistory(visibleArchive: records.load()))
    try records.setOverviewPermission(true)
    let history = try XCTUnwrap(GalaxySSIHealthBluetoothHistory(visibleArchive: records.load()))
    XCTAssertEqual(history.devices.first { $0.id == id }?.name, "Monitor")
    XCTAssertEqual(history.readings(for: id).map(\.id), [newest.id, older.id])
    XCTAssertEqual(history.readings(for: UUID()).count, 0)
    try records.setOverviewPermission(false)
    XCTAssertNil(try GalaxySSIHealthBluetoothHistory(visibleArchive: records.load()))
    XCTAssertEqual(try records.load().current.count, 3)
  }

  @MainActor
  func testBluetoothErasurePinsDeviceHistoryAndAccessWithoutLoggingIdentity() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(Data([0, 120, 0, 80, 0, 90, 0])))
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let device = UUID(), sameNameDevice = UUID()
    func reading(_ id: UUID, _ seconds: TimeInterval) -> GalaxySSIHealthReading {
      GalaxySSIHealthBluetoothReceipt(device: id, receivedAt: now.addingTimeInterval(seconds),
                                      packet: packet, deviceName: "Private monitor").reading(conditions: "")
    }
    let first = reading(device, 0), second = reading(device, -120), other = reading(sameNameDevice, 0)
    let manual = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 120, diastolic: 80)
    let apple = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now, value: 120, diastolic: 80,
      healthKitSource: .init(key: String(repeating: "a", count: 64), origin: "fixture", name: nil))
    try records.write(first)
    try records.write(second)
    try records.write(other)
    try records.write(manual, allowDuplicate: true)
    XCTAssertEqual(try records.importHealthKit([apple]), 1)
    XCTAssertThrowsError(try records.previewBluetoothHistoryDeletion(device: device))
    try records.setOverviewPermission(true)
    var removed = try XCTUnwrap(records.load().current.first { $0.id == second.id })
    removed.deleted = true
    try records.write(removed, rememberDeletion: true)
    let active = try XCTUnwrap(records.load().current.first { $0.id == first.id })
    let draft = GalaxySSIHealthDraft(existing: active, metric: .bloodPressure)
    try records.storeDraft(draft)
    let before = try records.previewBluetoothHistoryDeletion(device: device)
    XCTAssertEqual(before.scope.count, 2)
    XCTAssertEqual(before.scope.earliest, second.measuredAt)
    XCTAssertEqual(before.scope.drafts, 1)
    try records.setOverviewPermission(false)
    XCTAssertThrowsError(try records.deleteMetricHistory(before))
    try records.setOverviewPermission(true)
    XCTAssertThrowsError(try records.deleteMetricHistory(before))
    let refreshed = try records.previewBluetoothHistoryDeletion(device: device)
    let later = reading(device, 120)
    try records.write(later)
    XCTAssertThrowsError(try records.deleteMetricHistory(refreshed))
    XCTAssertNil(try records.load().metricDeletionHistory)
    XCTAssertEqual(try records.load().draft?.id, draft.id)

    let confirmed = try records.previewBluetoothHistoryDeletion(device: device)
    XCTAssertEqual(confirmed.scope.count, 3)
    try records.deleteMetricHistory(confirmed)
    let archive = try records.load()
    XCTAssertEqual(Set(archive.current.map(\.id)), Set([other.id, manual.id, apple.id]))
    XCTAssertFalse(archive.revisions.contains { $0.bluetoothReceipt?.device == device })
    XCTAssertNil(archive.draft)
    XCTAssertNil(archive.lastMeasurementDeletion)
    XCTAssertThrowsError(try records.storeDraft(draft))
    let audit = try XCTUnwrap(archive.metricDeletionHistory?.first)
    XCTAssertEqual(audit.scope.filter, .bluetooth)
    XCTAssertEqual(audit.scope.count, 3)
    let encoded = String(decoding: try JSONEncoder().encode(audit), as: UTF8.self)
    XCTAssertFalse(encoded.contains(device.uuidString))
    XCTAssertFalse(encoded.contains("Private monitor"))
    try records.write(reading(device, 240))
  }

  @MainActor
  func testProfileBackgroundSelectionPinsEntriesAndAuditsOnlyCount() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: file.appendingPathExtension("profile"))
    }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let selected = GalaxySSIHealthProfile.Background(kind: .history, title: "private-selected-fixture", notes: "private-note")
    let other = GalaxySSIHealthProfile.Background(kind: .allergy, title: "unselected-fixture", notes: "")
    var profile = GalaxySSIHealthProfile()
    profile.background = [selected, other]
    try records.writeProfile(profile)
    try records.setOverviewPermission(true)
    try records.setProfileAnalysisAllowed(true)
    profile = try records.loadProfile()
    let version = try XCTUnwrap(profile.backgroundVersion(profile.background[0]))
    let selection = [selected.id: version]
    let snapshot = try XCTUnwrap(records.captureProfileAnalysis([], background: selection))
    XCTAssertEqual(snapshot.background.map(\.id), [selected.id])
    XCTAssertEqual(try records.load().profileAnalysisAudit?.last?.backgroundCount, 1)
    profile.background[1].title = "changed unrelated entry"
    try records.writeProfile(profile)
    XCTAssertTrue(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    profile = try records.loadProfile()
    profile.background.removeFirst()
    try records.writeProfile(profile)
    XCTAssertThrowsError(try records.captureProfileAnalysis([], background: selection))
    XCTAssertFalse(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    XCTAssertEqual(try records.load().profileAnalysisAudit?.count, 1)
    profile = try records.loadProfile()
    profile.background.append(selected)
    try records.writeProfile(profile)
    XCTAssertThrowsError(try records.captureProfileAnalysis([], background: selection))
    profile = try records.loadProfile()
    let renewed = try XCTUnwrap(profile.backgroundVersion(profile.background[1]))
    let allergy = try XCTUnwrap(profile.backgroundVersion(profile.background[0]))
    let combined = try XCTUnwrap(records.captureProfileAnalysis([], background: [selected.id: renewed, other.id: allergy]))
    XCTAssertEqual(Set(combined.background.map(\.id)), [selected.id, other.id])
    XCTAssertEqual(try records.load().profileAnalysisAudit?.last?.backgroundCount, 2)
    let audit = try JSONEncoder().encode(records.load().profileAnalysisAudit)
    XCTAssertNil(audit.range(of: Data(selected.title.utf8)))
    XCTAssertNil(audit.range(of: Data(selected.notes.utf8)))
    try records.setProfileAnalysisAllowed(false)
    XCTAssertThrowsError(try records.captureProfileAnalysis([], background: [selected.id: renewed]))
    let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: Date(), duration: 60), metrics: [.weight])
    let data = try GalaxySSIHealthAnalysis(scope: scope, current: [], calendar: .current).requestJSON()
    XCTAssertNil(data.range(of: Data(selected.title.utf8)))
    XCTAssertNil(data.range(of: Data(selected.notes.utf8)))
  }

  @MainActor
  func testProfileAnalysisBindsOnlySelectedFieldsAndPermission() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: file.appendingPathExtension("profile"))
    }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var profile = try records.loadProfile()
    profile.height = 170
    profile.context = "private fixture"
    try records.writeProfile(profile)
    try records.setOverviewPermission(true)
    XCTAssertThrowsError(try records.captureProfileAnalysis([.height]))
    try records.setProfileAnalysisAllowed(true)
    XCTAssertNil(try records.captureProfileAnalysis([]))
    XCTAssertNil(try records.load().profileAnalysisAudit)
    let snapshot = try XCTUnwrap(records.captureProfileAnalysis([.height, .birthDate]))
    XCTAssertEqual(snapshot.values[.height], .height(170, .cm))
    XCTAssertNil(snapshot.values[.context])
    XCTAssertNil(snapshot.values[.birthDate])
    profile = try records.loadProfile()
    profile.context = "unrelated update"
    try records.writeProfile(profile)
    XCTAssertTrue(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    profile = try records.loadProfile()
    profile.height = 171
    try records.writeProfile(profile)
    XCTAssertFalse(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    profile = try records.loadProfile()
    profile.height = 170
    try records.writeProfile(profile)
    XCTAssertFalse(try snapshot.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    let latest = try XCTUnwrap(records.captureProfileAnalysis([.height]))
    try records.setProfileAnalysisAllowed(false)
    try records.setProfileAnalysisAllowed(true)
    XCTAssertFalse(try latest.isCurrent(profile: records.loadProfile(), permission: records.load().profileAnalysisPermission))
    XCTAssertEqual(try records.load().profileAnalysisAudit?.first?.fields, [.height, .birthDate])
    let audit = try XCTUnwrap(records.load().profileAnalysisAudit)
    let serialized = String(decoding: try JSONEncoder().encode(audit), as: UTF8.self)
    XCTAssertFalse(serialized.contains("private fixture"))
    XCTAssertFalse(serialized.contains("unrelated update"))
    XCTAssertEqual(try records.load().privacyEvents?.filter { $0.scope == .profileAnalysis }.map(\.enabled), [true, false, true])
  }

  @MainActor
  func testHealthBackupV2RestoresSecondaryLinksWithoutReplacingMeasurements() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    for folder in [source, target] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: source.appendingPathComponent("records"))
    let destination = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: target.appendingPathComponent("records"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: source,
      restoreRecordsFile: records.isolatedFile)
    let existingFiles = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: target,
      restoreRecordsFile: destination.isolatedFile)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try originals.store(pdf, name: "report.pdf")
    try existingFiles.store(pdf, name: "same-report.pdf")
    let report = try XCTUnwrap(originals.list().originals.first)
    let reusedPDF = try XCTUnwrap(existingFiles.list().originals.first)
    XCTAssertNotEqual(reusedPDF.id, report.id)
    let png = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).pngData { _ in }
    try originals.store(png, name: "image-report.png")
    try existingFiles.store(png, name: "same-image-report.png")
    let image = try XCTUnwrap(originals.list().originals.first { $0.kind == .image })
    let reusedImage = try XCTUnwrap(existingFiles.list().originals.first { $0.kind == .image })
    XCTAssertNotEqual(reusedImage.id, image.id)

    let reading = GalaxySSIHealthReading(metric: .weight, value: 65)
    try records.write(reading)
    try destination.write(reading)
    var revised = try XCTUnwrap(records.load().current.first)
    revised.notes = "current"
    try records.write(revised)
    var archive = try records.load()
    let current = try XCTUnwrap(archive.current.first)
    let csv = Data("value,time\n65,2025-01-01T12:00:00Z\n".utf8)
    let tableHash = GalaxySSIHealthTableImport.digest(csv)
    let table = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "table.csv", at: Date(), data: csv, inserted: 0)
    archive.tableBatches = [table]
    try records.commitRestore(archive, receipt: UUID())
    let previousPlan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    archive.reportEvidence = (0..<35).map { region in
      let original = region == 0 ? image : report
      return .init(target: .init(record: current.id, revision: region == 34 ? 1 : current.revision),
        source: .init(original: original.id, sha256: original.sha256, page: 0, region: region, fromOCR: region != 1),
        excerpt: "private report fixture")
    }
    archive.tableEvidence = [.init(target: .init(record: current.id, revision: current.revision),
      source: .init(batch: table.id, row: 0, sha256: tableHash))]
    try records.commitRestore(archive, receipt: UUID())
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.prepare(previousPlan, records: records, originals: originals))
    let plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    let (plain, summary) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
    XCTAssertEqual(summary.secondaryLinks, 35)
    let password = "fixture-password"
    let package = try GalaxySSIHealthPortableBackup.seal(plain, password: password)
    XCTAssertTrue(package.starts(with: Data("GalaxySSI-Health-Backup-v2\n".utf8)))
    XCTAssertNil(package.range(of: Data("private report fixture".utf8)))
    let input = try GalaxySSIHealthPortableBackup.unlock(package, password: password)

    let otherTable = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "same-table.csv", at: Date(), data: csv, inserted: 0)
    var local = try destination.load()
    local.tableBatches = [otherTable]
    try destination.commitRestore(local, receipt: UUID())
    let conflict = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: existingFiles)
    XCTAssertEqual(conflict.skippedLinks, 35)
    try destination.write(revised)
    let preview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: existingFiles)
    XCTAssertEqual(preview.newLinks, 35)
    XCTAssertEqual(preview.missing, 0)
    XCTAssertEqual(preview.originals, 0)
    XCTAssertEqual(preview.tables, 0)
    try GalaxySSIHealthPortableBackup.restore(input, expected: preview, records: destination, originals: existingFiles)
    let restored = try destination.load()
    XCTAssertEqual(restored.revisions.count, 2)
    XCTAssertEqual(restored.reportEvidence?.count, 34)
    XCTAssertTrue(restored.reportEvidence?.allSatisfy {
      $0.source.original == ($0.source.region == 0 ? reusedImage.id : reusedPDF.id) &&
        $0.source.fromOCR == ($0.source.region != 1) &&
        $0.target.revision == current.revision
    } == true)
    XCTAssertEqual(restored.tableEvidence?.first?.source.batch, otherTable.id)
    XCTAssertEqual(try existingFiles.read(reusedPDF), pdf)
    let repeated = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: existingFiles)
    XCTAssertEqual(repeated.reusedLinks, 35)
    XCTAssertFalse(repeated.hasChanges)

    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
    legacy.removeValue(forKey: "sourceFrames")
    let salt = Data(repeating: 0x12, count: 16)
    let header = Data("GalaxySSI-Health-Backup-v1\n".utf8) + salt
    let key = SymmetricKey(data: try GalaxySSIBackupManager.pbkdf2SHA256(
      password: password, salt: salt, iterations: 600_000, keyByteCount: 32))
    let sealed = try AES.GCM.seal(JSONSerialization.data(withJSONObject: legacy), using: key, authenticating: header)
    let v1 = try GalaxySSIHealthPortableBackup.unlock(header + XCTUnwrap(sealed.combined), password: password)
    XCTAssertEqual(v1.summary.secondaryLinks, 0)
    XCTAssertEqual(v1.summary.readings, 1)
  }

  @MainActor
  func testHealthBackupAuthenticatesOriginalsAndLeavesLocalRecordsUntouched() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets,
                                         isolatedFile: root.appendingPathComponent("measurements"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root)
    let oldPlan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    try records.write(.init(metric: .weight, value: 65, notes: "private backup fixture marker"))
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.prepare(oldPlan, records: records, originals: originals))
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try originals.store(pdf, name: "fixture.pdf")
    let plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    let (payload, expected) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
    let sealed = try GalaxySSIHealthPortableBackup.seal(payload, password: "fixture-password")
    XCTAssertNil(sealed.range(of: Data("private backup fixture marker".utf8)))
    XCTAssertEqual(try GalaxySSIHealthPortableBackup.verify(sealed, password: "fixture-password"), expected)
    XCTAssertEqual(expected.readings, 1)
    XCTAssertEqual(expected.originals, 1)
    XCTAssertEqual(expected.missing, 0)
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.verify(sealed + Data([1]), password: "fixture-password"))
    XCTAssertEqual(try records.load().current.count, 1)
  }

  @MainActor
  func testHealthBluetoothSameNameAndEqualValuesStaySeparated() throws {
    let bytes = Data([30, 120, 0, 80, 0, 90, 0, 234, 7, 11, 5, 12, 30, 0, 64, 0, 2, 1, 0])
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(bytes))
    let now = Date()
    let a = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet, deviceName: "Monitor")
    let b = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: now, packet: packet, deviceName: "Monitor")
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.write(a.reading(conditions: ""))
    try records.write(b.reading(conditions: ""))
    let saved = try records.load().current
    XCTAssertEqual(saved.count, 2)
    XCTAssertEqual(GalaxySSIHealthTrendDevice.options(in: saved, metric: .bloodPressure).count, 2)
    let selected = GalaxySSIHealthTrendDevice.matching(saved, device: a.device)
    XCTAssertEqual(selected.map { $0.bluetoothReceipt?.device }, [a.device])
    let trend = GalaxySSIHealthTrend(current: selected, metric: .bloodPressure, component: .value,
                                    now: now, dayCount: 7, calendar: .current)
    XCTAssertEqual(trend.points.last?.readings.count, 1)
    let export = try GalaxySSIHealthMeasurementExport.encode(saved, as: .json, includeNotes: false)
    XCTAssertNil(export.range(of: Data(a.device.uuidString.utf8)))
    XCTAssertNil(export.range(of: Data("Monitor".utf8)))
  }

  @MainActor
  func testHealthRestoreRetainsTombstonesAndPublishesExactOriginalWithReceipt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    for directory in [source, target] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: source.appendingPathComponent("records"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: source)
    let destination = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: target.appendingPathComponent("records"))
    let files = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: target,
                                             restoreRecordsFile: destination.isolatedFile)
    let deleted = GalaxySSIHealthReading(metric: .weight, value: 65)
    try records.write(deleted)
    try records.write(.init(metric: .glucose, value: 6))
    try destination.write(deleted)
    var tombstone = try XCTUnwrap(destination.load().current.first)
    tombstone.deleted = true
    try destination.write(tombstone)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try originals.store(pdf, name: "fixture.pdf")
    let manifest = try XCTUnwrap(originals.list().originals.first)
    let abandonedReceipt = UUID()
    try files.withRestoreLease { lease in
      try files.stageRestore([(manifest, pdf)], receipt: abandonedReceipt, lease: lease)
      XCTAssertThrowsError(try files.list()) { error in
        guard case GalaxySSIHealthOriginalStore.Failure.restoreBusy = error else { return XCTFail("Expected active restore lease") }
      }
      let staged = target.appendingPathComponent("restore-staging").appendingPathComponent(abandonedReceipt.uuidString)
      XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }
    XCTAssertTrue(try files.list().originals.isEmpty)
    let plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    let (payload, _) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
    let sealed = try GalaxySSIHealthPortableBackup.seal(payload, password: "fixture-password")
    let input = try GalaxySSIHealthPortableBackup.unlock(sealed, password: "fixture-password")
    let preview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: files)
    XCTAssertEqual(preview.readings, 1)
    XCTAssertEqual(preview.conflicts.map(\.id), [deleted.id])
    try destination.write(.init(metric: .steps, value: 12))
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.restore(input, expected: preview, records: destination, originals: files))
    let fresh = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: files)
    try GalaxySSIHealthPortableBackup.restore(input, expected: fresh, records: destination, originals: files)
    XCTAssertEqual(try destination.load().restoreReceipts?.count, 1)
    XCTAssertFalse(try destination.load().current.contains { $0.id == deleted.id })
    XCTAssertEqual(try files.read(manifest), pdf)
    XCTAssertFalse(try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: files).hasChanges)
    let foreign = GalaxySSIHealthRecords(owner: "different", secrets: secrets, isolatedFile: destination.isolatedFile)
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.previewRestore(input, records: foreign, originals: files))
    try files.remove(files.previewRemoval(manifest))
    let pendingReceipt = UUID()
    try files.withRestoreLease { lease in
      try files.stageRestore([(manifest, pdf)], receipt: pendingReceipt, lease: lease)
      try destination.commitRestore(destination.load(), receipt: pendingReceipt, originals: [manifest], notify: false)
    }
    XCTAssertEqual(try files.list().originals, [manifest])
    XCTAssertEqual(try files.read(manifest), pdf)
  }

  @MainActor
  func testCommittedHealthRestoreAuthenticatesStagedOriginalBeforePublishing() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("records")
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets,
                                             fixtureDirectory: root, restoreRecordsFile: file)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "fixture.pdf")
    let original = try XCTUnwrap(store.list().originals.first)
    try store.remove(store.previewRemoval(original))
    let receipt = UUID()
    try store.withRestoreLease { lease in
      try store.stageRestore([(original, pdf)], receipt: receipt, lease: lease)
      try records.commitRestore(records.load(), receipt: receipt, originals: [original], notify: false)
    }
    let folder = root.appendingPathComponent("restore-staging").appendingPathComponent(receipt.uuidString)
    let staged = folder.appendingPathComponent(original.id.uuidString)
    let valid = try Data(contentsOf: staged)
    var corrupted = valid
    corrupted[corrupted.count - 1] ^= 1
    try corrupted.write(to: staged)
    XCTAssertThrowsError(try store.list())
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(original.id.uuidString).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    XCTAssertTrue(try records.load().restoreReceipts?.contains(receipt) == true)

    try valid.write(to: staged)
    XCTAssertEqual(try store.list().originals, [original])
    XCTAssertEqual(try store.read(original), pdf)
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    XCTAssertEqual(try store.list().originals, [original])
  }

  @MainActor
  func testHealthOriginalIndexMigratesLegacyCommittedBytesWithoutRewritingThem() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("records")
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root, restoreRecordsFile: file)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "legacy.pdf", kind: .pdf, fileExtension: "pdf",
      importedAt: Date(), bytes: pdf.count, sha256: GalaxySSIHealthLinkedExport.digest(pdf))
    let receipt = UUID()
    let staged = root.appendingPathComponent("restore-staging").appendingPathComponent(receipt.uuidString)
      .appendingPathComponent(original.id.uuidString)
    var legacyBytes = Data()
    try store.withRestoreLease { lease in
      try store.stageRestore([(original, pdf)], receipt: receipt, lease: lease)
      legacyBytes = try Data(contentsOf: staged)
      try records.commitRestore(records.load(), receipt: receipt, notify: false)
    }
    XCTAssertNil(try records.load().originalIndex)
    XCTAssertEqual(try store.list().originals, [original])
    XCTAssertEqual(try records.load().originalIndex?.originals[original.id], original)
    let path = root.appendingPathComponent(original.id.uuidString)
    XCTAssertEqual(try Data(contentsOf: path), legacyBytes)
    try FileManager.default.removeItem(at: path)
    XCTAssertEqual(try store.list().unavailableOriginals, [original])
    try store.store(pdf, name: "reimport.pdf")
    XCTAssertEqual(try store.list().originals, [original])
    XCTAssertEqual(try store.read(original), pdf)
  }

  @MainActor
  func testHealthOriginalIndexRejectsConflictingMetadataWithoutPublishingMeasurements() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("records")
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root, restoreRecordsFile: file)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "fixture.pdf")
    let original = try XCTUnwrap(store.list().originals.first)
    let conflicting = GalaxySSIHealthOriginalStore.Original(id: original.id, name: "conflicting.pdf", kind: original.kind,
      fileExtension: original.fileExtension, importedAt: original.importedAt, bytes: original.bytes, sha256: original.sha256)
    let receipt = UUID()
    try store.withRestoreLease { lease in
      try store.stageRestore([(conflicting, pdf)], receipt: receipt, lease: lease)
      var proposed = try records.load()
      proposed.revisions.append(.init(revision: 1, metric: .weight, value: 65))
      XCTAssertThrowsError(try records.commitRestore(proposed, receipt: receipt, originals: [conflicting], notify: false))
    }
    XCTAssertTrue(try records.load().current.isEmpty)
    XCTAssertFalse(try records.load().restoreReceipts?.contains(receipt) == true)
    XCTAssertEqual(try store.list().originals, [original])
    XCTAssertEqual(try store.read(original), pdf)
  }

  @MainActor
  func testHealthRestoreOnlyAppendsSelectedEligibleConflictRevisions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let source = root.appendingPathComponent("source")
    let target = root.appendingPathComponent("target")
    for directory in [source, target] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: source.appendingPathComponent("records"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: source)
    let destination = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: target.appendingPathComponent("records"))
    let files = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: target,
      restoreRecordsFile: destination.isolatedFile)
    let selected = GalaxySSIHealthReading(metric: .weight, value: 65)
    let untouched = GalaxySSIHealthReading(metric: .glucose, value: 5)
    let deleted = GalaxySSIHealthReading(metric: .heartRate, value: 70)
    let changedSource = GalaxySSIHealthReading(metric: .weight, value: 80)
    for reading in [selected, untouched] {
      try records.write(reading)
      var local = reading
      local.value = reading.metric == .weight ? 66 : 6
      try destination.write(local)
    }
    try records.write(deleted)
    try destination.write(deleted)
    var tombstone = try XCTUnwrap(destination.load().current.first { $0.id == deleted.id })
    tombstone.deleted = true
    try destination.write(tombstone)
    try records.write(changedSource)
    var imported = changedSource
    imported.healthKitSource = .init(key: "fixture-healthkit", origin: "fixture", name: nil)
    try destination.write(imported)
    let plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    let (payload, _) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
    let encrypted = try GalaxySSIHealthPortableBackup.seal(payload, password: "fixture-password")
    let input = try GalaxySSIHealthPortableBackup.unlock(encrypted, password: "fixture-password")
    let preview = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: files)
    XCTAssertFalse(preview.hasChanges)
    XCTAssertEqual(preview.conflicts.filter { $0.restriction == nil }.count, 2)
    XCTAssertEqual(preview.conflicts.first { $0.id == deleted.id }?.restriction, .deleted)
    XCTAssertEqual(preview.conflicts.first { $0.id == changedSource.id }?.restriction, .source)
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.restore(input, expected: preview,
      records: destination, originals: files, replacing: [untouched.id, changedSource.id]))
    XCTAssertEqual(try destination.load().current.first { $0.id == untouched.id }?.value, 6)
    let local = try XCTUnwrap(destination.load().current.first { $0.id == selected.id })
    try destination.storeDraft(.init(existing: local))
    XCTAssertThrowsError(try GalaxySSIHealthPortableBackup.restore(input, expected: preview,
      records: destination, originals: files, replacing: [selected.id]))
    let blocked = try GalaxySSIHealthPortableBackup.previewRestore(input, records: destination, originals: files)
    XCTAssertEqual(blocked.conflicts.first { $0.id == selected.id }?.restriction, .draft)
    try GalaxySSIHealthPortableBackup.restore(input, expected: blocked, records: destination,
      originals: files, replacing: [untouched.id])
    let restored = try destination.load()
    XCTAssertEqual(restored.revisions.filter { $0.id == untouched.id }.compactMap(\.value), [6, 5])
    XCTAssertEqual(restored.current.first { $0.id == selected.id }?.value, 66)
    XCTAssertFalse(restored.current.contains { $0.id == deleted.id })
    XCTAssertEqual(restored.current.first { $0.id == changedSource.id }?.healthKitSource, imported.healthKitSource)
    XCTAssertEqual(restored.draft?.existing?.id, selected.id)
  }

  @MainActor
  func testLinkedHealthExportDeduplicatesExactOriginalsAndDetectsRemoval() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData {
      $0.beginPage()
      $0.beginPage()
    }
    try store.store(pdf, name: "camera.pdf", acquisition: .camera)
    let original = try XCTUnwrap(store.list().originals.first)
    let readings = (0..<2).map { page in
      GalaxySSIHealthReading(revision: 1, metric: .weight, value: Decimal(65 + page),
        reportSource: .init(original: original.id, sha256: original.sha256, page: page, region: 0, fromOCR: true))
    }
    let uploadOnly = try GalaxySSIHealthLinkedExport.prepare(readings, batches: [], store: store, choices: .init(uploaded: true))
    XCTAssertEqual(uploadOnly.links.map(\.status), [.unselected, .unselected])
    let camera = GalaxySSIHealthLinkedExport.Choices(camera: true)
    let package = try GalaxySSIHealthLinkedExport.prepare(readings, batches: [], store: store, choices: camera)
    XCTAssertEqual(package.links.map(\.status), [.included, .included])
    XCTAssertEqual(package.files.map(\.data), [pdf])
    let data = try GalaxySSIHealthMeasurementExport.encode(readings, as: .csv, includeNotes: false)
    let zip = try package.zip(measurements: data, format: .csv)
    XCTAssertNotNil(zip.range(of: Data("manifest.json".utf8)))
    for format in GalaxySSIHealthMeasurementExport.Format.allCases {
      let content = try GalaxySSIHealthMeasurementExport.encode(readings, as: format, includeNotes: false)
      let archive = try package.zip(measurements: content, format: format)
      XCTAssertNotNil(archive.range(of: Data(("measurements." + format.rawValue).utf8)))
      XCTAssertNotNil(archive.range(of: content))
      XCTAssertNotNil(archive.range(of: pdf))
    }
    let artifact = try store.stageScopedExport(zip)
    XCTAssertNil(try Data(contentsOf: artifact.file).range(of: pdf))
    XCTAssertEqual(try artifact.read(), zip)
    artifact.discard()
    XCTAssertThrowsError(try artifact.read())
    let selected = readings[0]
    let csv = Data("value\n65\n".utf8)
    let table = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "fixture.csv", at: Date(), data: csv, inserted: 0)
    let secondary: [GalaxySSIHealthTableImport.Evidence] = [1, 2].map { revision in
      .init(target: .init(record: selected.id, revision: revision),
        source: .init(batch: table.id, row: revision, sha256: GalaxySSIHealthTableImport.digest(csv), columns: ["value": 0]))
    }
    let mixed = try GalaxySSIHealthLinkedExport.prepare(readings, batches: [table], store: store,
      choices: .init(camera: true, uploaded: true), tableEvidence: secondary)
    XCTAssertEqual(mixed.links.filter(\.secondary).map(\.location), [1])
    XCTAssertEqual(mixed.files.count, 2)
    let proof = GalaxySSIHealthOriginalStore.ExportAttempt(id: UUID(), at: Date(), originals: [], bytes: zip.count,
      sha256: GalaxySSIHealthLinkedExport.digest(zip), outcome: .prepared)
    let destination = root.appendingPathComponent("export.zip")
    try zip.write(to: destination)
    XCTAssertTrue(try GalaxySSIHealthOriginalStore.verifyDestination(destination, for: proof))
    try Data(zip.dropLast()).write(to: destination)
    XCTAssertFalse(try GalaxySSIHealthOriginalStore.verifyDestination(destination, for: proof))
    try store.remove(store.previewRemoval(original))
    let stale = try GalaxySSIHealthLinkedExport.prepare(readings, batches: [], store: store, choices: camera)
    XCTAssertEqual(stale.links.map(\.status), [.missing, .missing])
    XCTAssertNotEqual(package.links, stale.links)
  }

  @MainActor
  func testLinkedHealthExportIncludesVerifiedImageEvidenceOnlyOnItsSingleOCRPage() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let png = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).pngData { _ in }
    try store.store(png, name: "camera.png", acquisition: .camera)
    let original = try XCTUnwrap(store.list().originals.first)
    let reading = GalaxySSIHealthReading(revision: 1, metric: .weight, value: 65,
      reportSource: .init(original: original.id, sha256: original.sha256, page: 0, region: 0, fromOCR: true))
    let target = GalaxySSIHealthReportReview.Target(record: reading.id, revision: reading.revision)
    let evidence: [GalaxySSIHealthReportReview.Evidence] = [
      .init(target: target, source: .init(original: original.id, sha256: original.sha256,
        page: 0, region: 1, fromOCR: true), excerpt: "Verified image evidence"),
      .init(target: target, source: .init(original: original.id, sha256: original.sha256,
        page: 1, region: 1, fromOCR: true), excerpt: "Invalid image page"),
      .init(target: target, source: .init(original: original.id, sha256: original.sha256,
        page: 0, region: 2, fromOCR: false), excerpt: "Invalid native image text"),
      .init(target: target, source: .init(original: original.id, sha256: String(repeating: "0", count: 64),
        page: 0, region: 3, fromOCR: true), excerpt: "Wrong digest")
    ]
    let package = try GalaxySSIHealthLinkedExport.prepare([reading], batches: [], store: store,
      choices: .init(camera: true), reportEvidence: evidence)
    XCTAssertEqual(package.links.map(\.status), [.included, .included, .mismatched, .mismatched, .mismatched])
    XCTAssertEqual(package.links.map(\.path), [original.entryPath, original.entryPath, nil, nil, nil])
    XCTAssertEqual(package.files.map(\.data), [png])
    let unselected = try GalaxySSIHealthLinkedExport.prepare([reading], batches: [], store: store,
      choices: .init(uploaded: true))
    XCTAssertEqual(unselected.links.map(\.status), [.unselected])
    XCTAssertTrue(unselected.files.isEmpty)
  }

  func testMeasurementExportKeepsComponentsAndProtectsCSVFormulas() throws {
    var reading = GalaxySSIHealthReading(metric: .bloodPressure, value: 120, diastolic: 80, pulse: 65)
    reading.conditions = " =2+2"
    reading.notes = "a\r\nb\nc\rd,\"quoted\""
    let csv = String(decoding: try GalaxySSIHealthMeasurementExport.encode([reading], as: .csv, includeNotes: true),
                     as: UTF8.self)
    XCTAssertTrue(csv.contains("\"120\",\"mmHg\",\"80\",\"65\""))
    XCTAssertTrue(csv.contains("\"' =2+2\""))
    XCTAssertTrue(csv.contains("\"a\r\nb\nc\rd,\"\"quoted\"\"\""))
    let json = try GalaxySSIHealthMeasurementExport.encode([reading], as: .json, includeNotes: false)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
    let row = try XCTUnwrap((object["measurements"] as? [[String: String]])?.first)
    XCTAssertEqual(row["diastolic"], "80")
    XCTAssertNil(row["conditions"])
    XCTAssertNil(row["notes"])
  }

  func testMeasurementXLSXUsesLiteralTextAndPreservesExactNotation() throws {
    var reading = GalaxySSIHealthReading(metric: .weight, value: try XCTUnwrap(Decimal(string: "60.123456789012345678")))
    reading.notes = "=2+2\r\n<&> _x000D_\u{0000}"
    let data = try GalaxySSIHealthMeasurementExport.encode([reading], as: .xlsx, includeNotes: true)
    let workbook = try GalaxySSIHealthXLSX(data)
    let sheet = try XCTUnwrap(workbook.sheets.first)
    let rows = try workbook.rows(sheet.id)
    XCTAssertTrue(try XCTUnwrap(rows.last).formulas.isEmpty)
    let table = try workbook.table(.init(sheet: sheet.id, header: 1))
    XCTAssertEqual(table.rows.first?[4], "60.123456789012345678")
    XCTAssertEqual(table.rows.first?[9], reading.notes)
    let withoutNotes = try GalaxySSIHealthMeasurementExport.encode([reading], as: .xlsx, includeNotes: false)
    let privateWorkbook = try GalaxySSIHealthXLSX(withoutNotes)
    let privateSheet = try XCTUnwrap(privateWorkbook.sheets.first)
    XCTAssertFalse(try privateWorkbook.table(.init(sheet: privateSheet.id, header: 1)).headers.contains("notes"))
  }

  @MainActor
  func testProfileIsSeparateAndStaleDraftCannotRestoreClearedFacts() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let profileFile = file.appendingPathExtension("profile")
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: profileFile)
    }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.write(.init(metric: .weight, value: 65))
    var profile = try records.loadProfile()
    profile.name = "private profile marker"
    profile.background = [.init(kind: .allergy, title: "fixture", notes: "")]
    try records.writeProfile(profile)
    XCTAssertNil(String(decoding: try Data(contentsOf: profileFile), as: UTF8.self).range(of: profile.name))
    let stale = try records.loadProfile()
    XCTAssertEqual(stale.background.count, 1)
    var cleared = GalaxySSIHealthProfile()
    cleared.revision = stale.revision
    try records.writeProfile(cleared)
    XCTAssertThrowsError(try records.writeProfile(stale))
    XCTAssertTrue(try records.loadProfile().name.isEmpty)
    XCTAssertTrue(try records.loadProfile().background.isEmpty)
    XCTAssertEqual(try records.load().current.count, 1)
  }

  @MainActor
  func testPrivacyEventsRecordOnlyEffectiveScopedChanges() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    try records.setOverviewPermission(false)
    try records.setOverviewPermission(true)
    try records.setOverviewPermission(true)
    try records.setWeeklyReportAllowed(true)
    try records.setOverviewPermission(false)
    let archive = try records.load()
    let history = try XCTUnwrap(archive.privacyEvents)
    XCTAssertEqual(history.map(\.scope), [.overview, .weeklyReport, .overview])
    XCTAssertEqual(history.map(\.enabled), [true, true, false])
    XCTAssertEqual(archive.derivesOverview, false)
    XCTAssertEqual(archive.weeklyReportAllowed, true)
    XCTAssertNil(String(decoding: try Data(contentsOf: file), as: UTF8.self).range(of: "privacyEvents"))
  }

  @MainActor
  func testImportOriginalRetentionIsEncryptedAndIndependentOfOnlineConsent() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertTrue(try records.load().keepsNewImportOriginals)
    try records.setHealthOnlinePermission(true)
    let onlinePermission = try XCTUnwrap(records.load().healthOnlinePermission)
    try records.setPrivacy(.importOriginals, enabled: true)
    XCTAssertNil(try records.load().privacyEvents)
    try records.setPrivacy(.importOriginals, enabled: false)
    try records.setPrivacy(.importOriginals, enabled: false)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    let archive = try reopened.load()
    XCTAssertFalse(archive.keepsNewImportOriginals)
    XCTAssertEqual(archive.healthOnlinePermission, onlinePermission)
    XCTAssertEqual(archive.privacyEvents?.map(\.scope), [.importOriginals])
    XCTAssertEqual(archive.privacyEvents?.map(\.enabled), [false])
    XCTAssertNil(String(decoding: try Data(contentsOf: file), as: UTF8.self).range(of: "retainImportOriginals"))
  }

  func testImportRetentionChoiceDoesNotFallBackWhenPolicyIsUnavailable() {
    XCTAssertEqual(GalaxySSIHealthImportRetentionChoice.useDefault.resolve(default: false), false)
    XCTAssertEqual(GalaxySSIHealthImportRetentionChoice.useDefault.resolve(default: true), true)
    XCTAssertEqual(GalaxySSIHealthImportRetentionChoice.keep.resolve(default: false), true)
    XCTAssertEqual(GalaxySSIHealthImportRetentionChoice.reviewOnly.resolve(default: true), false)
    for choice in [GalaxySSIHealthImportRetentionChoice.useDefault, .keep, .reviewOnly] {
      XCTAssertNil(choice.resolve(default: nil))
    }
  }

  func testOverviewUsesConfirmedLatestReadingsAndLocalDayBoundary() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
    let boundary = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 4)))
    let weight = GalaxySSIHealthReading(metric: .weight, measuredAt: boundary, value: 65)
    let older = GalaxySSIHealthReading(metric: .weight, measuredAt: boundary.addingTimeInterval(-1), value: 60)
    let stale = GalaxySSIHealthReading(metric: .heartRate, measuredAt: boundary.addingTimeInterval(-1), value: 65)
    let future = GalaxySSIHealthReading(metric: .weight, measuredAt: now.addingTimeInterval(1), value: 90)
    let deleted = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 5, deleted: true)
    let overview = GalaxySSIHealthOverview(current: [older, weight, stale, future, deleted],
                                          now: now, calendar: calendar)
    XCTAssertEqual(overview.recentCount, 1)
    XCTAssertEqual(overview.metrics.first { $0.metric == .weight }?.reading?.id, weight.id)
    XCTAssertEqual(overview.metrics.first { $0.metric == .heartRate }?.freshness, .stale)
    XCTAssertEqual(overview.metrics.first { $0.metric == .glucose }?.freshness, .missing)
  }

  @MainActor
  func testOverviewPermissionIsOptInAndSurvivesReopening() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertNil(try records.load().derivesOverview)
    try records.setOverviewPermission(true)
    let reopened = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    XCTAssertEqual(try reopened.load().derivesOverview, true)
    try reopened.setOverviewPermission(false)
    XCTAssertEqual(try records.load().derivesOverview, false)
  }

  @MainActor
  func testWeeklyExportRequiresPermissionAndUnchangedSelectedRevisions() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let now = Date()
    try records.write(.init(metric: .weight, measuredAt: now, value: 65))
    let preview = GalaxySSIWeeklyHealthReport(current: try records.load().current,
      interval: DateInterval(start: now.addingTimeInterval(-60), duration: 120), metrics: [.weight], through: now)
    XCTAssertThrowsError(try records.prepareWeeklyExport(preview, includeRows: false))
    try records.setWeeklyReportAllowed(true)
    try records.write(.init(metric: .glucose, measuredAt: now, value: 5))
    try records.prepareWeeklyExport(preview, includeRows: false)
    var weight = try XCTUnwrap(preview.readings.first)
    weight.value = 64
    try records.write(weight)
    XCTAssertThrowsError(try records.prepareWeeklyExport(preview, includeRows: true))
    XCTAssertEqual(try records.load().weeklyExportRequests?.count, 1)
  }

  @MainActor
  func testPartialDraftIsEncryptedAndClearedOnlyByMatchingCommit() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    var draft = GalaxySSIHealthDraft()
    draft.value = "120."
    draft.notes = "private partial fixture marker"
    try records.storeDraft(draft)
    XCTAssertNil(String(decoding: try Data(contentsOf: file), as: UTF8.self).range(of: draft.notes))
    XCTAssertEqual(try records.load().draft?.value, "120.")
    try records.discardDraft(id: UUID())
    XCTAssertEqual(try records.load().draft?.id, draft.id)
    let invalid = GalaxySSIHealthReading(metric: .bloodPressure, value: 120)
    XCTAssertThrowsError(try records.write(invalid, draftId: draft.id))
    XCTAssertEqual(try records.load().draft?.id, draft.id)
    try records.write(GalaxySSIHealthReading(metric: .bloodPressure, value: 120, diastolic: 80),
                      draftId: draft.id)
    XCTAssertNil(try records.load().draft)
    XCTAssertEqual(try records.load().current.count, 1)
  }

  @MainActor
  func testDuplicateRevisionDeletionAndCorruption() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: file)
    var reading = GalaxySSIHealthReading(metric: .bloodPressure, value: 120, diastolic: 80)
    reading.notes = "private fixture marker"
    XCTAssertTrue(try records.load().current.isEmpty)
    try records.write(reading)
    XCTAssertNil(String(decoding: try Data(contentsOf: file), as: UTF8.self).range(of: reading.notes))
    XCTAssertThrowsError(try records.write(reading)) { error in
      guard case GalaxySSIHealthRecords.Failure.stale = error else { return XCTFail("\(error)") }
    }
    var duplicate = reading
    duplicate.id = UUID()
    XCTAssertThrowsError(try records.write(duplicate)) { error in
      guard case GalaxySSIHealthRecords.Failure.duplicate = error else { return XCTFail("\(error)") }
    }
    try records.write(duplicate, allowDuplicate: true)
    reading = try XCTUnwrap(records.load().current.first { $0.id == reading.id })
    reading.deleted = true
    try records.write(reading)
    XCTAssertEqual(try records.load().current.map(\.id), [duplicate.id])
    XCTAssertEqual(try records.load().revisions.count, 3)
    let otherOwner = GalaxySSIHealthRecords(owner: "other", secrets: secrets, isolatedFile: file)
    XCTAssertThrowsError(try otherOwner.load())
    try Data([1, 2, 3]).write(to: file)
    XCTAssertThrowsError(try records.write(duplicate))
    XCTAssertEqual(try Data(contentsOf: file), Data([1, 2, 3]))
  }

  @MainActor
  func testBluetoothPressureDecodesOptionalFieldsAndDoesNotResurrectDeletedReading() throws {
    let bytes = Data([30, 120, 0, 80, 0, 90, 0, 234, 7, 11, 5, 12, 30, 0, 64, 0, 2, 1, 0])
    let packet = try XCTUnwrap(GalaxySSIHealthBluetoothPacket.decode(bytes))
    XCTAssertEqual(packet.deviceClock, "2026-11-05 12:30:00")
    XCTAssertEqual(packet.slot, 2)
    XCTAssertEqual(packet.status, 1)
    XCTAssertEqual(packet.pulse, 64)
    XCTAssertNil(GalaxySSIHealthBluetoothPacket.decode(Data(bytes.dropLast())))
    XCTAssertNil(GalaxySSIHealthBluetoothPacket.decode(Data([0, 255, 7, 80, 0, 90, 0])))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let receipt = GalaxySSIHealthBluetoothReceipt(device: UUID(), receivedAt: Date(), packet: packet)
    try records.write(receipt.reading(conditions: ""))
    var saved = try XCTUnwrap(records.load().current.first)
    saved.deleted = true
    try records.write(saved)
    let replay = GalaxySSIHealthBluetoothReceipt(device: receipt.device,
      receivedAt: receipt.receivedAt.addingTimeInterval(600), packet: packet)
    XCTAssertThrowsError(try records.write(replay.reading(conditions: ""), allowDuplicate: true))
    XCTAssertTrue(try records.load().current.isEmpty)
  }

  @MainActor
  func testOriginalLibraryKeepsExactBytesAndRejectsTamperedPayload() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "private-test-name.pdf")
    try store.store(pdf, name: "duplicate.pdf")
    let originals = try store.list().originals
    XCTAssertEqual(originals.count, 1)
    let item = try XCTUnwrap(originals.first)
    XCTAssertEqual(try store.read(item), pdf)
    let zip = try store.makeZIP([item])
    XCTAssertNotNil(zip.range(of: pdf))
    XCTAssertNotNil(zip.range(of: Data("manifest.json".utf8)))
    let file = root.appendingPathComponent(item.id.uuidString)
    var sealed = try Data(contentsOf: file)
    XCTAssertNil(sealed.range(of: Data(item.name.utf8)))
    XCTAssertNil(sealed.range(of: pdf))
    sealed[sealed.count - 1] ^= 1
    try sealed.write(to: file)
    XCTAssertThrowsError(try store.makeZIP([item]))
  }

  @MainActor
  func testOriginalZIPReceiptChecksReadbackAndPreservesPriorSuccess() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "private.pdf")
    let originals = try store.list().originals
    let output = root.appendingPathComponent("destination.zip")
    let (firstZIP, first) = try store.prepareExport(originals)
    XCTAssertTrue(store.hasShareArtifact(first))
    XCTAssertEqual(try store.readShareArtifact(first), firstZIP)
    XCTAssertEqual(try store.exportHistory().first?.outcome, .prepared)
    let artifact = root.appendingPathComponent("export-artifacts-v1").appendingPathComponent(first.id.uuidString)
    var sealedArtifact = try Data(contentsOf: artifact)
    XCTAssertNil(sealedArtifact.range(of: firstZIP))
    sealedArtifact[sealedArtifact.count - 1] ^= 1
    try sealedArtifact.write(to: artifact)
    XCTAssertThrowsError(try store.readShareArtifact(first))
    try firstZIP.write(to: output)
    XCTAssertTrue(try GalaxySSIHealthOriginalStore.verifyDestination(output, for: first))
    try store.finishExport(id: first.id, verified: true)
    let (secondZIP, second) = try store.prepareExport(originals)
    try Data(secondZIP.dropLast()).write(to: output)
    XCTAssertFalse(try GalaxySSIHealthOriginalStore.verifyDestination(output, for: second))
    var tampered = secondZIP
    tampered[tampered.count - 1] ^= 1
    try tampered.write(to: output)
    XCTAssertFalse(try GalaxySSIHealthOriginalStore.verifyDestination(output, for: second))
    try store.finishExport(id: second.id, verified: false)
    try store.finishExport(id: first.id, verified: false)
    let history = try store.exportHistory()
    XCTAssertEqual(history.map(\.outcome), [.unverified, .verified])
    XCTAssertEqual(history.last?.originals, originals)
    XCTAssertEqual(try store.list().originals, originals)
  }

  @MainActor
  func testSingleOriginalSaveChecksExactBytesAndRejectsReimportedSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root,
                                             restoreRecordsFile: root.appendingPathComponent("records"))
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "private.pdf")
    let source = try XCTUnwrap(store.list().originals.first)
    let output = root.appendingPathComponent("destination.pdf")
    let bytes = try store.read(source)
    XCTAssertEqual(bytes, pdf)
    XCTAssertTrue(try store.singleSaveHistory().isEmpty)
    try bytes.write(to: output)
    let matched = try GalaxySSIHealthOriginalStore.verifyDestination(output, bytes: source.bytes, sha256: source.sha256)
    XCTAssertTrue(matched)
    XCTAssertTrue(try store.finishSingleSave(source, destinationVerified: matched))

    var tampered = bytes
    tampered[tampered.count - 1] ^= 1
    try tampered.write(to: output)
    let corrupted = try GalaxySSIHealthOriginalStore.verifyDestination(output, bytes: source.bytes, sha256: source.sha256)
    XCTAssertFalse(corrupted)
    XCTAssertFalse(try store.finishSingleSave(source, destinationVerified: corrupted))

    try store.remove(store.previewRemoval(source))
    try store.store(pdf, name: source.name)
    XCTAssertThrowsError(try store.read(source))
    XCTAssertFalse(try store.finishSingleSave(source, destinationVerified: matched))
    let history = try store.singleSaveHistory()
    XCTAssertEqual(history.map(\.verified), [false, false, true])
    let receipt = try XCTUnwrap(history.first)
    let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
    XCTAssertEqual(Set(fields.keys), Set(["at", "kind", "bytes", "verified"]))
    let audit = root.appendingPathComponent("single-save-v1")
    var sealed = try Data(contentsOf: audit)
    sealed[sealed.count - 1] ^= 1
    try sealed.write(to: audit)
    XCTAssertThrowsError(try store.singleSaveHistory())
  }

  @MainActor
  func testOriginalRemovalRequiresFreshLinkedRevisionsAndRetainsMetadataAndCopies() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: root.appendingPathComponent("records"))
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root,
                                             restoreRecordsFile: records.isolatedFile)
    let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)).pdfData { $0.beginPage() }
    try store.store(pdf, name: "private.pdf")
    let original = try XCTUnwrap(store.list().originals.first)
    let (zip, export) = try store.prepareExport([original])
    let now = Date()
    func item(_ index: Int) -> GalaxySSIHealthReportReview.Item {
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
                                                      page: index, region: 0, fromOCR: true)
      let reading = GalaxySSIHealthReading(metric: .weight, measuredAt: now.addingTimeInterval(Double(-120 * index)),
                                            value: 60, reportSource: source)
      return .init(version: UUID(), source: source, excerpt: "Fixture", reading: reading)
    }
    let linked = (1...35).map(item)
    for row in linked { try records.stageReportItem(row, replacing: nil) }
    try records.confirmReportItems(Set(linked.dropLast().map(\.version)), original: original)
    let initial = try store.previewRemoval(original)
    XCTAssertEqual(initial.links.count, 34)
    XCTAssertTrue(try store.removalHistory().isEmpty)
    XCTAssertEqual(try store.read(original), pdf)

    var edited = try XCTUnwrap(records.load().current.first)
    edited.notes = "Changed revision"
    try records.write(edited)
    XCTAssertThrowsError(try store.remove(initial)) { error in
      guard case GalaxySSIHealthOriginalStore.Failure.stale = error else { return XCTFail("Expected stale preview") }
    }
    let afterEdit = try store.previewRemoval(original)
    XCTAssertEqual(afterEdit.links.count, 34)
    try records.confirmReportItems([try XCTUnwrap(linked.last?.version)], original: original)
    XCTAssertThrowsError(try store.remove(afterEdit))
    let draft = item(36)
    try records.stageReportItem(draft, replacing: nil)
    let fresh = try store.previewRemoval(original)
    XCTAssertEqual(fresh.links.count, 35)
    try store.remove(fresh)

    let listing = try store.list()
    XCTAssertTrue(listing.originals.isEmpty)
    XCTAssertEqual(listing.removed, [original])
    XCTAssertTrue(listing.pendingRemovals.isEmpty)
    XCTAssertThrowsError(try store.read(original))
    XCTAssertEqual(try records.load().current.count, 35)
    XCTAssertEqual(try records.load().reportReview?.map(\.version), [draft.version])
    XCTAssertEqual(try store.readShareArtifact(export), zip)
    let history = try store.removalHistory()
    XCTAssertEqual(history.map(\.linkedMeasurements), [35])
    let encoded = try JSONEncoder().encode(history)
    let serialized = String(decoding: encoded, as: UTF8.self)
    XCTAssertFalse(serialized.contains(original.id.uuidString))
    XCTAssertFalse(serialized.contains(original.name))
    XCTAssertFalse(serialized.contains(original.sha256))
  }

  @MainActor
  func testHealthReportPDFReadsNativePageAndKeepsPageBounds() throws {
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 240, height: 200)).pdfData { context in
      context.beginPage()
      ("Synthetic report line 12345" as NSString).draw(at: CGPoint(x: 12, y: 18),
        withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
      context.beginPage()
    }
    XCTAssertEqual(try GalaxySSIHealthPDFText.pageCount(data), 2)
    let result = try GalaxySSIHealthPDFText.read(data, page: 0)
    XCTAssertEqual(result.method, .native)
    let text = try XCTUnwrap(result.regions.first)
    XCTAssertTrue(text.text.contains("Synthetic report"))
    XCTAssertTrue(result.crop.contains(text.bounds))
    let highlight = try XCTUnwrap(text.highlight)
    XCTAssertNotNil(result.preview)
    XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(highlight))
    XCTAssertLessThan(highlight.minY, 0.25)
    XCTAssertThrowsError(try GalaxySSIHealthPDFText.read(data, page: 2))
  }

  func testHealthPDFHighlightClipsToViewportAndFlipsVerticalAxis() throws {
    let viewport = CGRect(x: 20, y: 40, width: 100, height: 200)
    let region = CGRect(x: 10, y: 190, width: 35, height: 40)
    let highlight = try XCTUnwrap(GalaxySSIHealthPDFText.normalizedTopOrigin(region, in: viewport))
    XCTAssertEqual(highlight.minX, 0, accuracy: 0.0001)
    XCTAssertEqual(highlight.minY, 0.05, accuracy: 0.0001)
    XCTAssertEqual(highlight.width, 0.25, accuracy: 0.0001)
    XCTAssertNil(GalaxySSIHealthPDFText.normalizedTopOrigin(CGRect(x: 400, y: 0, width: 10, height: 10), in: viewport))
  }

  func testTrendAuditPinsContributorsAndExtremumRevision() throws {
    let now = Date()
    let readings = (0..<34).map {
      GalaxySSIHealthReading(revision: $0 + 1, metric: .glucose, measuredAt: now,
        value: Decimal(40 - $0))
    }
    let excluded = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 1, unitOverride: "mg/dL")
    func point(_ inputs: [GalaxySSIHealthReading]) throws -> GalaxySSIHealthTrend.Point {
      try XCTUnwrap(GalaxySSIHealthTrend(current: inputs, metric: .glucose, component: .value,
        now: now, dayCount: 7, calendar: .current, source: .manual).points.last)
    }
    let original = try point(readings + [excluded])
    XCTAssertEqual(original.readings.count, 34)
    XCTAssertEqual(original.value(.min, component: .value), 7)
    XCTAssertEqual(original.value(.max, component: .value), 40)
    XCTAssertEqual(original.extremum(.min, component: .value)?.revision, 34)
    XCTAssertEqual(original.revisions, try point(Array(readings.reversed())).revisions)
    var revised = readings
    revised[33].revision += 1
    XCTAssertNotEqual(original.revisions, try point(revised).revisions)
  }

  func testHealthAssistantSendsOnlyAggregatesAndRejectsUnknownEvidence() throws {
    let now = Date()
    let reading = GalaxySSIHealthReading(revision: 2, metric: .glucose, measuredAt: now, value: 6)
    let other = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 100, unitOverride: "mg/dL")
    let unrelated = GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 72)
    let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: now, duration: 86_400), metrics: [.glucose])
    let analysis = GalaxySSIHealthAnalysis(scope: scope, current: [reading, other, unrelated], calendar: .current)
    XCTAssertEqual(analysis.evidence.count, 2)
    XCTAssertEqual(analysis.evidence.first?.aggregate.mean, "6")
    XCTAssertEqual(analysis.evidence.first?.readings.map(\.id), [reading.id])
    XCTAssertTrue(analysis.isCurrent([other, reading]))
    XCTAssertFalse(analysis.isCurrent([other]))
    let data = try analysis.requestJSON()
    let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(packet.keys), ["requestedDays", "aggregates"])
    let aggregates = try XCTUnwrap(packet["aggregates"] as? [[String: Any]])
    XCTAssertEqual(Set(try XCTUnwrap(aggregates.first).keys),
      ["id", "metric", "component", "unit", "count", "observedDays", "minimum", "maximum", "mean"])
    let output = #"{"evidence":["e1"],"next_step":"review_sources"}"#
    XCTAssertEqual(try analysis.recommendation(output).evidence, ["e1"])
    XCTAssertThrowsError(try analysis.recommendation(#"{"evidence":["e99"],"next_step":"review_sources"}"#))
    XCTAssertThrowsError(try analysis.recommendation(#"{"evidence":["e1"],"next_step":"review_sources","text":"extra"}"#))
  }

  func testHealthFollowUpSendsOnlyScopedFactsAndPreviousVerifiedSelections() throws {
    let now = Date()
    let reading = GalaxySSIHealthReading(revision: 2, metric: .weight, measuredAt: now, value: 60, notes: "private notes")
    let previous = GalaxySSIHealthReading(revision: 3, metric: .weight,
      measuredAt: now.addingTimeInterval(-86_400), value: 58)
    let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: now, duration: 86_400), metrics: [.weight])
    let previousScope = GalaxySSIHealthAnalysis.Scope(
      interval: DateInterval(start: now.addingTimeInterval(-86_400), end: now), metrics: [.weight])
    let analysis = GalaxySSIHealthAnalysis(scope: scope, current: [reading, previous], calendar: .current)
    let baseline = GalaxySSIHealthAnalysis(scope: previousScope, current: [reading, previous], calendar: .current)
    let first = try GalaxySSIHealthFollowUp(analysis: analysis, baseline: baseline,
      question: "  First question\r\nsecond line ", previous: nil)
    let response = #"{"status":"PARTIAL","sections":[{"topic":"CHANGES","fact_ids":["e1"]}],"actions":["WEEKLY_REPORT"]}"#
    let answer = try first.answer(response)
    XCTAssertEqual(answer.status, .partial)
    XCTAssertEqual(first.comparisons["e1"]?.delta, "2")
    XCTAssertEqual(first.comparisons["e1"]?.evidence.readings.map(\.revision), [3])
    XCTAssertFalse(baseline.isCurrent([reading]))

    let next = try GalaxySSIHealthFollowUp(analysis: analysis, baseline: baseline, question: "Why?", previous: answer)
    let data = String(decoding: next.payload, as: UTF8.self)
    let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: next.payload) as? [String: Any])
    XCTAssertEqual(Set(packet.keys), ["question", "requestedDays", "facts", "allowed_topics", "allowed_actions", "previous_answer"])
    XCTAssertEqual(packet["question"] as? String, "Why?")
    XCTAssertEqual(packet["allowed_topics"] as? [String], ["CHANGES", "COVERAGE", "SOURCES"])
    for privateValue in ["First question", "private notes", reading.id.uuidString, previous.id.uuidString, "measuredAt"] {
      XCTAssertFalse(data.contains(privateValue))
    }
    let newAnalysis = GalaxySSIHealthAnalysis(scope: scope, current: [reading], calendar: .current)
    let fresh = try GalaxySSIHealthFollowUp(analysis: newAnalysis, baseline: nil, question: "Why?", previous: answer)
    XCTAssertFalse(String(decoding: fresh.payload, as: UTF8.self).contains("previous_answer"))
    XCTAssertThrowsError(try fresh.answer(response))
    XCTAssertEqual(GalaxySSIHealthFollowUp.question("  First\r\nsecond  "), "First\nsecond")
    XCTAssertNil(GalaxySSIHealthFollowUp.question(String(repeating: "a", count: 601)))
    XCTAssertNil(GalaxySSIHealthFollowUp.question("bad\u{0000}"))
  }

  func testHealthFollowUpRejectsInventedFactsProseAndAmbiguousJSON() throws {
    let now = Date()
    let scope = GalaxySSIHealthAnalysis.Scope(interval: DateInterval(start: now, duration: 86_400), metrics: [.weight])
    let analysis = GalaxySSIHealthAnalysis(scope: scope,
      current: [GalaxySSIHealthReading(metric: .weight, measuredAt: now, value: 60)], calendar: .current)
    let packet = try GalaxySSIHealthFollowUp(analysis: analysis, baseline: nil, question: "What do I have?", previous: nil)
    let valid = #"{"status":"ANSWERED","sections":[{"topic":"COVERAGE","fact_ids":["e1"]}],"actions":[]}"#
    XCTAssertEqual(try packet.answer(valid).sections.first?.factIDs, ["e1"])
    XCTAssertEqual(try packet.answer(#"{"status":"OUT_OF_SCOPE","sections":[],"actions":[]}"#).status, .outOfScope)
    for invalid in [
      valid.replacingOccurrences(of: "e1", with: "e9"),
      valid.replacingOccurrences(of: #""e1""#, with: #""e1","e1""#),
      valid.replacingOccurrences(of: #""topic":"COVERAGE""#, with: #""topic":"SOURCES","topic":"COVERAGE""#),
      valid.replacingOccurrences(of: #""status":"ANSWERED""#, with: #""status":"ANSWERED","answer":"123""#),
      valid.replacingOccurrences(of: "ANSWERED", with: "OUT_OF_SCOPE"),
      valid.replacingOccurrences(of: "COVERAGE", with: "CHANGES"),
      valid + " additional prose",
    ] {
      XCTAssertThrowsError(try packet.answer(invalid), invalid)
    }
  }

  func testHealthFollowUpProviderOutputRejectsToolCallsAndUnsafeEndpoints() throws {
    func output(_ json: String, _ style: GalaxySSICloudAPIStyle) throws -> String {
      try GalaxySSIHealthFollowUpTransport.output(Data(json.utf8), style: style)
    }
    XCTAssertEqual(try output(#"{"choices":[{"finish_reason":"stop","message":{"content":"{}"}}]}"#, .openAICompatible), "{}")
    XCTAssertEqual(try output(#"{"stop_reason":"end_turn","content":[{"type":"text","text":"{}"}]}"#, .anthropic), "{}")
    XCTAssertEqual(try output(#"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"{}"}]}}]}"#, .gemini), "{}")
    XCTAssertThrowsError(try output(#"{"choices":[{"finish_reason":"stop","message":{"content":"{}","tool_calls":[]}}]}"#, .openAICompatible))
    XCTAssertThrowsError(try output(#"{"stop_reason":"end_turn","content":[{"type":"tool_use","text":"{}"}]}"#, .anthropic))
    XCTAssertThrowsError(try output(#"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"{}","functionCall":{}}]}}]}"#, .gemini))
    var model = CloudModelConfig(id: "fixture", displayName: "Fixture", provider: "Custom", modelId: "model",
      endpoint: "https://example.test/v1/chat/completions", apiStyle: .openAICompatible, keychainAccount: "", updatedAt: Date())
    XCTAssertNotNil(GalaxySSIHealthFollowUpTransport.endpoint(for: model))
    for endpoint in ["http://example.test", "https://example.test/?secret=x", "https://user@example.test", "https://example.test/#fragment"] {
      model.endpoint = endpoint
      XCTAssertNil(GalaxySSIHealthFollowUpTransport.endpoint(for: model))
    }
    model.apiStyle = .gemini
    model.endpoint = "https://example.test/v1/models/fixture"
    XCTAssertNil(GalaxySSIHealthFollowUpTransport.endpoint(for: model))
    model.endpoint += ":generateContent"
    XCTAssertNotNil(GalaxySSIHealthFollowUpTransport.endpoint(for: model))
  }

  func testTrendKeepsCalendarGapsAndExactComponentCohorts() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))
    let first = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))
    let one = GalaxySSIHealthReading(revision: 2, metric: .bloodPressure, measuredAt: first,
                                   value: 120, diastolic: 80, pulse: 64)
    let two = GalaxySSIHealthReading(revision: 3, metric: .bloodPressure, measuredAt: now,
                                   value: 124, diastolic: 82, pulse: 69)
    let missing = GalaxySSIHealthReading(metric: .bloodPressure, measuredAt: now,
                                       value: 126, diastolic: 84)
    let trend = GalaxySSIHealthTrend(current: [two, one, missing], metric: .bloodPressure,
                                    component: .pulse, now: now, dayCount: 3, calendar: calendar)
    XCTAssertEqual(trend.validDays, 2)
    XCTAssertNil(trend.points[1].mean)
    XCTAssertEqual(trend.points[2].readings.map(\.revision), [3])
    XCTAssertEqual(trend.mean, Decimal(string: "66.5"))
    XCTAssertEqual(trend.minimum, 64)
    XCTAssertEqual(trend.maximum, 69)
  }

  func testHealthCatalogRefreshAnchorsToSurvivingVisibleRecord() throws {
    let anchor = try XCTUnwrap(GalaxySSIHealthCatalogAnchor.restoration(
      visible: [29, 30], updated: [100, 101] + Array(0..<29) + [30, 31], limit: 30))
    XCTAssertEqual(anchor.id, 30)
    XCTAssertEqual(anchor.limit, 32)
    XCTAssertNil(GalaxySSIHealthCatalogAnchor.restoration(visible: [29], updated: [30], limit: 30))
  }

  func testHealthCatalogTypedResultsDoNotEnterNumericTrendsOrMixUnits() throws {
    XCTAssertEqual(GalaxySSIHealthMetric.allCases.count, 27)
    XCTAssertTrue(GalaxySSIHealthMetric.hemoglobin.matches("HGB g/L"))
    let bound = try XCTUnwrap(GalaxySSIHealthReportedResult.parse("< 2.50", metric: .glucose))
    XCTAssertEqual(bound.kind, .comparison)
    XCTAssertEqual(bound.canonical, "<2.5")
    XCTAssertEqual(GalaxySSIHealthReportedResult.parse("1 - 4", metric: .glucose)?.kind, .range)
    XCTAssertNil(GalaxySSIHealthReportedResult.parse("4 - 1", metric: .glucose))
    let label = try XCTUnwrap(GalaxySSIHealthReportedResult.parse("Negative", metric: .urineProtein))
    XCTAssertTrue(GalaxySSIHealthReading(metric: .urineProtein, value: nil, reported: label).isValid)
    XCTAssertFalse(GalaxySSIHealthReading(metric: .urineProtein, value: 0).isValid)
    XCTAssertTrue(GalaxySSIHealthReading(metric: .steps, value: 0).isValid)
    XCTAssertFalse(GalaxySSIHealthReading(metric: .steps, value: Decimal(string: "1.5")).isValid)
    let now = Date()
    let range = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: nil, reported: bound)
    let standard = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 6)
    let otherUnit = GalaxySSIHealthReading(metric: .glucose, measuredAt: now, value: 100, unitOverride: "mg/dL")
    let trend = GalaxySSIHealthTrend(current: [range, standard, otherUnit], metric: .glucose,
      component: .value, now: now, dayCount: 7, calendar: .current)
    XCTAssertEqual(trend.mean, 6)
    XCTAssertEqual(trend.points.last?.readings.map(\.id), [standard.id])
  }

  func testHealthOCRLabRowsKeepTypedNotationAndOnlyAcceptExplicitReference() throws {
    let comparison = try XCTUnwrap(GalaxySSIHealthOCRLabRow.parse("12. ALT: \u{2264} 40 U/L H; Reference: 0\u{2013}40"))
    XCTAssertEqual(comparison.metric, .alt)
    XCTAssertEqual(comparison.notation, "\u{2264} 40")
    XCTAssertEqual(comparison.unit, "U/L")
    XCTAssertEqual(comparison.reference, "0\u{2013}40")
    let range = try XCTUnwrap(GalaxySSIHealthOCRLabRow.parse("WBC 4.0\u{FF5E}10.0 \u{00D7}10\u{2079}/L"))
    XCTAssertEqual(range.unit, "10^9/L")
    XCTAssertEqual(GalaxySSIHealthReportedResult.parse(range.notation, metric: range.metric)?.kind, .range)
    let translated = try XCTUnwrap(GalaxySSIHealthOCRLabRow.parse("\u{808C}\u{9150} (\u{03BC}mol/L): 55\u{81F3}85"))
    XCTAssertEqual(translated.metric, .creatinine)
    XCTAssertEqual(translated.unit, "umol/L")
    let urine = try XCTUnwrap(GalaxySSIHealthOCRLabRow.parse("\u{5C3F}\u{86CB}\u{767D}\u{FF1A}\u{9634}\u{6027}"))
    XCTAssertEqual(urine.metric, .urineProtein)
    XCTAssertEqual(urine.unit, "")
    XCTAssertEqual(GalaxySSIHealthOCRLabRow.parse("Urine protein: 1+")?.notation, "1+")
    let competing = try XCTUnwrap(GalaxySSIHealthOCRLabRow.parse("Glucose <5.6 mmol/L (<101 mg/dL)"))
    XCTAssertEqual(competing.notation, "<5.6")
    XCTAssertNil(competing.unit)
    let missing = try XCTUnwrap(GalaxySSIHealthOCRLabRow.parse("Glucose \u{FF1C} 5,60"))
    XCTAssertNil(missing.unit)
    XCTAssertEqual(GalaxySSIHealthReportedResult.parse(missing.notation, metric: missing.metric)?.canonical, "<5.6")
    for rejected in ["Patient name: Glucose 5.6 mmol/L", "Glucose 5.6 mmol/L 3.9-6.1",
                     "Glucose 5.6 mmol/L; Note: verify", "Glucose 2026-11-03", "ALT 40 mg/dL",
                     "Glucose negative", "Urine protein arbitrary text", "Urine protein 20 mg/dL", "PRO 1+", "UA 10 mg/dL"] {
      XCTAssertNil(GalaxySSIHealthOCRLabRow.parse(rejected), rejected)
    }
  }

  @MainActor
  func testHealthOCRLabBatchRetainsUnresolvedUnitAndOnlyExactNumbersEnterTrend() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    let original = GalaxySSIHealthOriginalStore.Original(id: UUID(), name: "fixture.pdf", kind: .pdf,
      fileExtension: "pdf", importedAt: Date(), bytes: 1, sha256: String(repeating: "b", count: 64))
    let date = Date()
    func item(_ raw: String, region: Int) throws -> GalaxySSIHealthReportReview.Item {
      let row = try XCTUnwrap(GalaxySSIHealthOCRLabRow.parse(raw))
      let source = GalaxySSIHealthReportReview.Source(original: original.id, sha256: original.sha256,
        page: 1, region: region, fromOCR: true)
      let result = GalaxySSIHealthReportedResult.parse(row.notation, metric: row.metric)
      let value = result == nil ? GalaxySSIHealthReportedResult.number(row.notation) : nil
      return .init(version: UUID(), source: source, excerpt: raw,
        reading: .init(metric: row.metric, measuredAt: date, value: value, reported: result,
          reportedNotation: row.notation, unitOverride: row.unit ?? "", referenceInterval: row.reference, reportSource: source))
    }
    let items = try [
      item("Glucose <= 2.50 mmol/L; Reference: 3.9-6.1", region: 0),
      item("Glucose 4.0-5.0 mmol/L", region: 1), item("Urine protein: trace", region: 2),
      item("Glucose 6.0 mmol/L", region: 3), item("Glucose > 7.2", region: 4)
    ]
    for item in items { try records.stageReportItem(item, replacing: nil) }
    let unresolved = try XCTUnwrap(items.last)
    XCTAssertTrue(unresolved.requiresUnitReview)
    XCTAssertNil(GalaxySSIHealthReportReview.exactTarget(for: unresolved, current: []))
    XCTAssertThrowsError(try records.confirmReportItems(Set(items.map(\.version)), original: original))
    XCTAssertTrue(try records.load().current.isEmpty)
    try records.confirmReportItems(Set(items.dropLast().map(\.version)), original: original)
    let archive = try records.load()
    XCTAssertEqual(archive.reportReview?.map(\.version), [unresolved.version])
    let comparison = try XCTUnwrap(archive.current.first { $0.reportSource == items[0].source })
    XCTAssertEqual(comparison.reported?.raw, "<= 2.50")
    XCTAssertEqual(comparison.referenceInterval, "3.9-6.1")
    XCTAssertEqual(Set(archive.current.compactMap { $0.reported?.kind.rawValue }), ["comparison", "range", "qualitative"])
    let trend = GalaxySSIHealthTrend(current: archive.current, metric: .glucose, component: .value,
      now: date, dayCount: 7, calendar: .current)
    XCTAssertEqual(trend.mean, 6)
    XCTAssertEqual(trend.points.last?.readings.map(\.id), [items[3].reading.id])
  }

  @MainActor
  func testStructuredImportKeepsExactSourceAndUndoPreservesEdits() throws {
    let data = Data("value,time,note\r\n60,2025-01-01T12:00:00Z,\"line\r\nnext\"\r\n61,2025-01-02T12:00:00Z,\r\n60,2025-01-01T12:00:00Z,\r\n".utf8)
    let table = try GalaxySSIHealthTableImport.parse(data, json: false)
    XCTAssertEqual(table.rows.first?[2], "line\r\nnext")
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, notes: 2, confirmedUnit: true)
    let rows = try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: [])
    XCTAssertEqual(rows.map(\.status), [.ready, .ready, .duplicate])
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(), isolatedFile: file)
    XCTAssertEqual(try records.importTable(data, name: "fixture.csv", json: false, mapping: mapping,
                                           expected: rows.map(\.status)), 2)
    XCTAssertThrowsError(try records.importTable(data, name: "fixture.csv", json: false, mapping: mapping,
                                                  expected: rows.map(\.status)))
    let archive = try records.load()
    let batch = try XCTUnwrap(archive.tableBatches?.first)
    XCTAssertEqual(batch.data, data)
    XCTAssertNil(try Data(contentsOf: file).range(of: data))
    var edited = try XCTUnwrap(archive.current.first)
    edited.value = 62
    try records.write(edited)
    XCTAssertEqual(try records.undoTableBatch(batch.id), 1)
    XCTAssertEqual(try records.load().current.map(\.value), [62])
    XCTAssertEqual(try records.undoTableBatch(batch.id), 0)
  }

  @MainActor
  func testReviewOnlyTablePreservesSourceReferenceWithoutArchivingBytes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = HealthFixtureSecrets()
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: secrets, isolatedFile: root.appendingPathComponent("records"))
    let originals = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: secrets, fixtureDirectory: root)
    let data = Data("value,time\n60,2025-01-01T12:00:00Z\n".utf8)
    let mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true)
    try records.setPrivacy(.importOriginals, enabled: false)
    let pendingRetention = try XCTUnwrap(GalaxySSIHealthImportRetentionChoice.useDefault.resolve(
      default: records.load().keepsNewImportOriginals))
    try records.setPrivacy(.importOriginals, enabled: true)
    XCTAssertEqual(try records.importTable(data, name: "review.csv", json: false, mapping: mapping,
                                           expected: [.ready], retainOriginal: pendingRetention), 1)
    let archive = try records.load()
    let batch = try XCTUnwrap(archive.tableBatches?.first)
    let source = try XCTUnwrap(archive.current.first?.tableSource)
    XCTAssertTrue(batch.data.isEmpty)
    XCTAssertEqual(source.batch, batch.id)
    XCTAssertEqual(source.sha256, batch.sourceDigest)
    XCTAssertNil(GalaxySSIHealthTableImport.Batch.original(for: batch.id, in: [batch]))
    let independent = GalaxySSIHealthTableImport.Batch(id: UUID(), name: "archived.csv", at: Date(),
                                                       data: data, inserted: 1, undone: nil)
    XCTAssertEqual(GalaxySSIHealthTableImport.Batch.original(for: batch.id, in: [batch, independent])?.id, independent.id)
    let plan = try GalaxySSIHealthPortableBackup.plan(records: records, originals: originals)
    let (_, summary) = try GalaxySSIHealthPortableBackup.prepare(plan, records: records, originals: originals)
    XCTAssertEqual(summary.tables, 0)
    XCTAssertEqual(summary.links, 1)
  }

  func testStructuredOriginalPreviewBoundsDoNotMutateSourceTable() throws {
    let long = String(repeating: "x", count: 300)
    let columns = (0..<13).map { "column\($0)" }
    let rows = Array(repeating: Array(repeating: long, count: 13), count: 31)
    let table = GalaxySSIHealthTableImport.Table(headers: columns, rows: rows)
    let sample = GalaxySSIHealthTableSourceSample(table)
    XCTAssertTrue(sample.limited)
    XCTAssertEqual(sample.headers.count, 12)
    XCTAssertEqual(sample.rows.count, 30)
    XCTAssertEqual(sample.rows.first?.first?.count, 256)
    XCTAssertEqual(table.rows.first?.first, long)
  }

  func testXLSXUsesWorksheetRelationshipsPhysicalRowsAndExplicitFormulaConsent() throws {
    let xml = [
      "xl/workbook.xml": #"<workbook xmlns:r="urn:test"><workbookPr date1904="1"/><sheets><sheet name="Weight" r:id="rId7"/></sheets></workbook>"#,
      "xl/_rels/workbook.xml.rels": #"<Relationships><Relationship Id="rId7" Type="urn:test/worksheet" Target="worksheets/sheet3.xml"/></Relationships>"#,
      "xl/worksheets/sheet3.xml": #"<worksheet><sheetData><row r="3"><c r="A3" t="inlineStr"><is><t>Value</t></is></c><c r="C3" t="inlineStr"><is><t>Time</t></is></c></row><row r="8"><c r="A8"><f>1+60</f><v>61</v></c><c r="C8"><v>1.5</v></c></row></sheetData></worksheet>"#
    ]
    let data = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: xml.map { .init(path: $0.key, data: Data($0.value.utf8)) })
    let workbook = try GalaxySSIHealthXLSX(data)
    let table = try workbook.table(.init(sheet: "rId7", header: 3))
    XCTAssertEqual(table.headers, ["Value", "", "Time"])
    XCTAssertEqual(table.sheetPath, "xl/worksheets/sheet3.xml")
    let sample = GalaxySSIHealthTableSourceSample(sheetRows: try workbook.rows("rId7"))
    XCTAssertEqual(sample.rowNumbers, [3, 8])
    XCTAssertEqual(sample.rows.last?.first, "=1+60\n61")
    let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    var mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 2,
                                                     confirmedUnit: true, dateStyle: .excel, localZone: utc)
    XCTAssertEqual(try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: []).first?.status, .invalid)
    mapping.useFormulaCache = true
    let row = try XCTUnwrap(GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: []).first)
    XCTAssertEqual(row.id, 8)
    XCTAssertEqual(row.reading?.value, 61)
    XCTAssertEqual(row.reading?.measuredAt, ISO8601DateFormatter().date(from: "1904-01-02T12:00:00Z"))
    XCTAssertEqual(row.excelDate1904, true)
    XCTAssertNil(row.dateOnlyDecision)
    XCTAssertNil(GalaxySSIHealthXLSX.date(serial: 60, date1904: false, zone: utc))
    var damaged = data
    let cached = try XCTUnwrap(damaged.range(of: Data("<v>61</v>".utf8)))
    damaged[cached.lowerBound + 3] = 55
    XCTAssertThrowsError(try GalaxySSIHealthXLSX(damaged))
    var nativeParts = xml
    let sheetPath = "xl/worksheets/sheet3.xml"
    nativeParts[sheetPath] = try XCTUnwrap(xml[sheetPath]).replacingOccurrences(
      of: #"<c r="C8"><v>1.5</v></c>"#,
      with: #"<c r="C8" t="d"><v>2025-11-02T01:30:00-04:00</v></c>"#)
    let nativeData = AgentRuntimeProjectArchiveBuilder.buildStoredZip(entries: nativeParts.map {
      .init(path: $0.key, data: Data($0.value.utf8))
    })
    let nativeWorkbook = try GalaxySSIHealthXLSX(nativeData)
    let nativeRow = try XCTUnwrap(nativeWorkbook.rows("rId7").last)
    XCTAssertEqual(nativeRow.isoDates, [2])
    XCTAssertEqual(nativeRow.formulaText[0], "1+60")
    XCTAssertEqual(nativeRow.cells[2], "2025-11-02T01:30:00-04:00")
  }

  func testXLSXTypedDatesPreserveOffsetAndRejectAmbiguousWallTimes() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let expected = ISO8601DateFormatter().date(from: "2025-11-02T05:30:00Z")
    XCTAssertEqual(GalaxySSIHealthXLSX.isoDate("2025-11-02T01:30:00-04:00", zone: utc, dateOnlyMinute: nil), expected)
    XCTAssertNil(GalaxySSIHealthXLSX.isoDate("2025-11-02T01:30:00", zone: zone, dateOnlyMinute: nil))
    XCTAssertNil(GalaxySSIHealthXLSX.isoDate("2025-03-09T02:30:00", zone: zone, dateOnlyMinute: nil))
    XCTAssertNil(GalaxySSIHealthXLSX.isoDate("2025-02-30T12:00:00Z", zone: utc, dateOnlyMinute: nil))
    XCTAssertNil(GalaxySSIHealthXLSX.isoDate("2025-11-02", zone: zone, dateOnlyMinute: nil))
    XCTAssertEqual(GalaxySSIHealthXLSX.isoDate("2025-11-02", zone: zone, dateOnlyMinute: 720),
                   ISO8601DateFormatter().date(from: "2025-11-02T17:00:00Z"))
    let table = GalaxySSIHealthTableImport.Table(headers: ["Value", "Time"],
      rows: [["61", "2025-11-02T01:30:00-04:00"], ["62", "44500"]], rowNumbers: [4, 9],
      formulas: [[], []], date1904: false, isoDates: [[1], []])
    var mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1,
      confirmedUnit: true, dateStyle: .excel, localZone: zone)
    let unconfirmed = try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: [])
    XCTAssertEqual(unconfirmed.map(\.status), [.ready, .missing])
    XCTAssertEqual(unconfirmed.last?.needsDateOnlyTime, true)
    mapping.dateOnlyMinute = 8 * 60 + 15
    let rows = try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: [])
    XCTAssertEqual(rows.map(\.status), [.ready, .ready])
    XCTAssertEqual(rows.first?.reading?.measuredAt, expected)
    XCTAssertEqual(rows.first?.rawDate, "2025-11-02T01:30:00-04:00")
    XCTAssertNil(rows.first?.dateOnlyDecision)
    XCTAssertEqual(rows.last?.dateOnlyDecision?.sourceDate, "44500")
    XCTAssertEqual(rows.last?.dateOnlyDecision?.clock, "08:15")
    XCTAssertEqual(rows.last?.excelDate1904, false)
  }

  func testTableDateOnlyFormatsRequireTimeAndKeepSourceOffsets() throws {
    typealias Import = GalaxySSIHealthTableImport
    let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let iso = ISO8601DateFormatter()
    let formats: [(Import.DateStyle, String)] = [
      (.iso, "2024-02-29"), (.day, "2024-02-29"), (.localMinute, "2024-02-29"), (.localTime, "2024-02-29"),
      (.slashYearFirst, "2024/02/29"), (.slashDayFirst, "29/02/2024"), (.slashMonthFirst, "02/29/2024")
    ]
    var mapping = Import.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true, localZone: zone)
    for (style, date) in formats {
      let csv = Data("value,time\n61,\(date)\n".utf8)
      let json = Data("[{\"value\":61,\"time\":\"\(date)\"}]".utf8)
      for (data, isJSON) in [(csv, false), (json, true)] {
        let table = try Import.parse(data, json: isJSON)
        mapping.value = try XCTUnwrap(table.headers.firstIndex(of: "value"))
        mapping.date = try XCTUnwrap(table.headers.firstIndex(of: "time"))
        mapping.dateStyle = style
        mapping.dateOnlyMinute = nil
        let missing = try XCTUnwrap(Import.preview(table, mapping: mapping, current: []).first)
        XCTAssertEqual(missing.status, .missing)
        XCTAssertTrue(missing.needsDateOnlyTime)
        mapping.dateOnlyMinute = 0
        let ready = try XCTUnwrap(Import.preview(table, mapping: mapping, current: []).first)
        XCTAssertEqual(ready.status, .ready)
        XCTAssertEqual(ready.dateOnlyDecision?.sourceDate, date)
        XCTAssertEqual(ready.dateOnlyDecision?.chosenMinute, 0)
        XCTAssertEqual(ready.reading?.measuredAt, iso.date(from: "2024-02-29T05:00:00Z"))
      }
    }
    mapping = Import.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true,
                             localZone: zone, dateOnlyMinute: 90)
    let table = Import.Table(headers: ["value", "time"], rows: [
      ["61", "2024-02-29+08:00"], ["62", "2024-11-03"], ["63", "2024-02-30"], ["64", "2024-11-03T01:30:00-04:00"]
    ])
    let rows = try Import.preview(table, mapping: mapping, current: [])
    XCTAssertEqual(rows.map(\.status), [.ready, .invalid, .invalid, .ready])
    XCTAssertEqual(rows.first?.reading?.measuredAt, iso.date(from: "2024-02-28T17:30:00Z"))
    XCTAssertEqual(rows.last?.reading?.measuredAt, iso.date(from: "2024-11-03T05:30:00Z"))
    XCTAssertNil(rows.last?.dateOnlyDecision)
    mapping.dateOnlyMinute = 150
    let spring = Import.Table(headers: table.headers, rows: [["61", "2024-03-10"]])
    XCTAssertEqual(try Import.preview(spring, mapping: mapping, current: []).first?.status, .invalid)
  }

  @MainActor
  func testDateOnlyTableDecisionSurvivesEncryptedImportAndBatchUndo() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let records = GalaxySSIHealthRecords(owner: "fixture", secrets: HealthFixtureSecrets(),
                                         isolatedFile: root.appendingPathComponent("records"))
    let data = Data("value,time\n61,2024-02-29\n".utf8)
    let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    var mapping = GalaxySSIHealthTableImport.Mapping(metric: .weight, value: 0, date: 1, confirmedUnit: true, localZone: utc)
    XCTAssertEqual(try records.importTable(data, name: "review.csv", json: false, mapping: mapping, expected: [.missing]), 0)
    mapping.dateOnlyMinute = 495
    XCTAssertEqual(try records.importTable(data, name: "review.csv", json: false, mapping: mapping,
                                           expected: [.ready], retainOriginal: false), 1)
    let archive = try records.load()
    let batch = try XCTUnwrap(archive.tableBatches?.first)
    let source = try XCTUnwrap(archive.current.first?.tableSource)
    XCTAssertEqual(source.dateOnlyDecision?.sourceDate, "2024-02-29")
    XCTAssertEqual(source.dateOnlyDecision?.clock, "08:15")
    XCTAssertEqual(source.dateOnlyDecision?.resolvedTime, archive.current.first?.measuredAt)
    XCTAssertTrue(batch.data.isEmpty)
    XCTAssertThrowsError(try records.importTable(data, name: "review.csv", json: false,
                                                 mapping: mapping, expected: [.ready]))
    XCTAssertEqual(try records.undoTableBatch(batch.id), 1)
    XCTAssertTrue(try records.load().current.isEmpty)
  }

  func testPaperEdgeSuggestionConvertsOriginAndRejectsClippedOrSmallRectangles() throws {
    let accepted = try XCTUnwrap(GalaxySSIHealthPaperEdges.paddedCrop(
      visionBounds: CGRect(x: 0.15, y: 0.10, width: 0.6, height: 0.5)))
    XCTAssertEqual(accepted.minX, 0.125, accuracy: 0.0001)
    XCTAssertEqual(accepted.minY, 0.375, accuracy: 0.0001)
    XCTAssertEqual(accepted.height, 0.55, accuracy: 0.0001)
    XCTAssertNil(GalaxySSIHealthPaperEdges.paddedCrop(visionBounds: CGRect(x: 0, y: 0.1, width: 0.6, height: 0.5)))
    XCTAssertNil(GalaxySSIHealthPaperEdges.paddedCrop(visionBounds: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)))
  }

  @MainActor
  func testEncryptedReportCropKeepsOriginalAndRejectsStaleReplacement() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = GalaxySSIHealthOriginalStore(owner: "fixture", secrets: HealthFixtureSecrets(), fixtureDirectory: root)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let png = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80), format: format).pngData { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
    }
    try store.store(png, name: "fixture.png")
    let original = try XCTUnwrap(store.list().originals.first)
    let output = try GalaxySSIHealthCropEncoder.encode(png, bounds: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    XCTAssertEqual(output.width, 50)
    XCTAssertEqual(output.height, 40)
    let saved = try store.saveCrop(output, for: original, replacing: nil)
    XCTAssertEqual(try store.readCrop(for: original)?.metadata, saved)
    XCTAssertEqual(try store.readCrop(for: original)?.png, output.png)
    XCTAssertThrowsError(try store.saveCrop(output, for: original, replacing: nil))
    XCTAssertEqual(try store.read(original), png)
    let sealed = root.appendingPathComponent("report-crops-v1").appendingPathComponent(original.id.uuidString)
    XCTAssertNil(try Data(contentsOf: sealed).range(of: output.png))
    let cropRoot = sealed.deletingLastPathComponent()
    let interrupted = cropRoot.appendingPathComponent(UUID().uuidString).appendingPathExtension("pending")
    let unrelated = cropRoot.appendingPathComponent("unrelated.pending")
    try Data([1, 2, 3]).write(to: interrupted)
    try Data([4]).write(to: unrelated)
    let committed = try Data(contentsOf: sealed)
    let reopened = GalaxySSIHealthOriginalStore(owner: store.owner, secrets: store.secrets, fixtureDirectory: root)
    try reopened.recoverInterruptedCrops()
    XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    XCTAssertEqual(try Data(contentsOf: sealed), committed)
    XCTAssertEqual(try reopened.readCrop(for: original)?.metadata, saved)
    XCTAssertEqual(try reopened.read(original), png)
  }
}

private final class HealthFixtureSecrets: GalaxySSISecretStore {
  private var values: [String: String] = [:]
  func setString(_ value: String, account: String) throws { values[account] = value }
  func string(account: String) -> String? { values[account] }
  func delete(account: String) { values.removeValue(forKey: account) }
}
