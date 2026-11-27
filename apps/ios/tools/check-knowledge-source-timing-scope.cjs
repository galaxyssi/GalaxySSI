const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
require('./check-knowledge-source-preparation-scope.cjs');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, 'GalaxySSI', name), 'utf8');
const telemetry = read('AgentLatencyTelemetry.swift');
const timing = read('AgentKnowledgeSourceWriteTiming.swift');
for (const phase of ['total', 'stage', 'prepare', 'commit', 'ownership', 'apply', 'observe']) {
  for (const boundary of ['started', 'finished']) {
    assert.ok(telemetry.includes(`"phone_runtime_knowledge_source_${phase}_${boundary}"`), `${phase} ${boundary}`);
  }
  assert.ok(telemetry.includes(`"phone_runtime_knowledge_source_${phase}_ms"`), phase);
  assert.ok(telemetry.includes(`"knowledge_source_${phase}"`), phase);
}
assert.match(timing, /private let correlation = UUID\(\).uuidString/);
assert.match(timing, /deferJournal: Bool = true/);
assert.match(timing, /phase: phase.runtime, deferJournal: deferJournal/);
assert.doesNotMatch(timing, /AgentKnowledgeItem|\.source|\.content|\.path|localizedDescription|print\(/);
assert.match(telemetry, /pendingOpaqueLimit = 256/);
assert.match(telemetry, /guard pendingOpaquePoints < Self.pendingOpaqueLimit else \{ lock.unlock\(\); return \}/);
assert.match(telemetry, /journalQueue.async \{ \[self\] in\s+journal.append\(point\)\s+lock.lock\(\); pendingOpaquePoints -= 1; lock.unlock\(\)/);
assert.match(telemetry, /if error is CancellationError \{ resultOutcome = "cancelled" \}/);
const database = read('AgentKnowledgeDatabase.swift');
const replacement = database.slice(database.indexOf('  func replaceSource('), database.indexOf('  private func validatePreparedIdentity('));
for (const phase of ['stage', 'prepare', 'commit', 'ownership', 'apply', 'observe']) {
  assert.equal(replacement.split(`timing.measure(.${phase})`).length - 1, 1, phase);
}
assert.ok(replacement.indexOf('timing.measure(.stage)') < replacement.indexOf('try stage.accept(item)'));
assert.ok(replacement.indexOf('timing.measure(.prepare)') < replacement.indexOf('try readCommitted'));
assert.ok(replacement.indexOf('timing.measure(.commit)') < replacement.indexOf('try locked'));
assert.ok(replacement.indexOf('timing.measure(.ownership)') < replacement.indexOf('try validatePreparedIdentity'));
assert.ok(replacement.indexOf('timing.measure(.apply)') < replacement.indexOf('try removeSourceRecord'));
assert.ok(replacement.indexOf('timing.measure(.observe)') < replacement.indexOf('knowledgeSourceMutation(stage: stage)'));
assert.ok(replacement.indexOf('try enqueueSourceObservation') < replacement.indexOf('execute("COMMIT")'));
assert.match(replacement, /prepareSourceReplacement\(source, next: next, timing: timing\)/);
assert.match(replacement, /commitSourceReplacement\(prepared, timing: timing/);
const store = read('GalaxySSIStoreKnowledge.swift');
const adapter = store.slice(store.indexOf('  private func replaceAgentKnowledgeSourceResult('), store.indexOf('  func upsertAgentKnowledge('));
assert.match(adapter, /let timing = AgentKnowledgeSourceWriteTiming\(\)/);
assert.match(adapter, /return try timing.measure\(.total\)/);
assert.match(adapter, /\}, timing: timing, beforeCommit:/);
for (const text of ['defer { mutation.stage.close() }', 'publishingCommittedKnowledgeCache = true', '.startIndexing()', 'save()']) {
  assert.ok(adapter.includes(text), text);
}
const tests = fs.readFileSync(path.join(root, 'GalaxySSITests/AgentKnowledgeSourceWriteTimingTests.swift'), 'utf8');
for (const name of ['SuccessfulProductionReplacementHasSevenNestedOpaqueSpans',
  'TelemetryContainsNoSourceIdentityBodyPathOrErrorText', 'SeparateReplacementsHaveIndependentCorrelationEvenForSameSource',
  'InputFailurePreservesExceptionAndDoesNotEnterPreparationOrWriter', 'PreparationFailureDoesNotEmitCommit',
  'OwnershipFailureIsNotSuccessfulApplyAndDoesNotMutateSource', 'ApplyCancellationRollsBackAndIsExcludedFromSuccessPercentiles',
  'PrecommitFailureDoesNotMisreportACompletedObservationAsDurableCommit', 'NoopDoesNotClaimObservationAndEmptySequenceRetainsDeletionSemantics',
  'BrokenJournalDoesNotRetryOrPreventSuccessfulCanonicalWrite', 'DisabledTimingExecutesOnceAndPreservesThrownIdentity',
  'MissingFinishRemainsIncompleteNotSuccessful', 'RevisionConflictDoesNotEnterOwnershipOrApply',
  'ObservationOutboxFailureRollsBackAndDoesNotBlameApply']) assert.ok(tests.includes(`func test${name}(`), name);
console.log('iOS source replacement timing source checks passed (not native execution)');
