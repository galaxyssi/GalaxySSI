// Source contracts only; no native dispatch, storage/fault/recovery or XCTest acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '9a0b8feaacd42e5caacd6bd6faaa35b5d91075f3';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => clean(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function section(source, first, last) {
  const start = source.indexOf(first), end = source.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  assert.equal(source.split(first).length, 2, first);
  return source.slice(start, end);
}
function retainedSequentialServices(source) {
  source = require('./check-planning-context-timing-scope.cjs').retainedPlanningServices(source);
  if (!source.includes('AgentSequentialPlanNodeDispatch.replay(')) return source;
  const prior = show(base, app + 'GalaxySSIServices.swift');
  source = source.replace(section(source, '  private func executeLocalNativeAction(\n', '  private func refreshAutomaticConnectorAction('),
    section(prior, '  private func executeLocalNativeAction(\n', '  private func refreshAutomaticConnectorAction('));
  return source.replace(section(source, '  private func checkpointSequentialPlanNodeDispatch(', '  private func retainWaitingNativeConnector('),
    section(prior, '  private func checkpointNativeConnectorDispatch(', '  private func retainWaitingNativeConnector('));
}
function validateSequentialPlanDispatch() {
  const services = read(app + 'GalaxySSIServices.swift');
  assert.equal(retainedSequentialServices(services), show(base, app + 'GalaxySSIServices.swift'),
    'Only sequential execution/checkpoint hooks change; parallel/confirmation/capture/browser/model-loop/session-recovery and results retained');
  const execute = section(services, '  private func executeLocalNativeAction(\n', '  private func refreshAutomaticConnectorAction(');
  for (const token of ['permitsEffectRecoveryActions', 'rejectReadOnlyAnalysisAction', 'AgentSequentialPlanNodeDispatch.replay(',
    'replay?.result ?? runtime.nativeActionExecutor.observedConnectorDispatch', 'replay?.action ??',
    'if priorDispatch == nil {',
    'checkpointSequentialPlanNodeDispatch(executionAction', 'AgentSequentialPlanNodeDispatch.execute(dispatch,',
    'AgentSupervisorRecoveryPolicy.stopReason', 'checkpointSequentialPlanNodeDispatch(fallbackAction',
    'AgentSequentialPlanNodeDispatch.execute(fallbackDispatch,', 'finishLocalNativeAction(']) assert(execute.includes(token), token);
  assert(execute.indexOf('AgentSequentialPlanNodeDispatch.replay(') < execute.indexOf('refreshAutomaticConnectorAction('));
  assert(execute.indexOf('checkpointSequentialPlanNodeDispatch(executionAction') < execute.indexOf('runtime.actionExecutor.execute('));
  const save = section(services, '  private func checkpointSequentialPlanNodeDispatch(', '  private func retainWaitingNativeConnector(');
  for (const token of ['AgentSequentialPlanNodeDispatch.prepare(', 'task.activePlan = prepared.plan',
    'task.planContext = AgentTaskPlanContext(plan: prepared.plan)', 'store.commitOwnedAgentTaskState(expected: previous, updated: task)',
    'return prepared', 'task.phase = .blocked', 'return nil']) assert(save.includes(token), token);
  const helper = read(app + 'AgentSequentialPlanNodeDispatch.swift');
  for (const token of ['plan.actions.filter({ $0.id == action.id }).count == 1', 'running.status = .running',
    'AgentExecutionContinuity.checkpointBefore', 'checkpoint.planRevision == plan.revision',
    'AgentPlanNodeKey.make', 'journal.observe(key)', 'let dispatch = try journal.readDispatch(key)',
    'checkpoint.planRevision == plan.revision', 'actions.count <= 1, checkpoints.count <= 1',
    'dispatch.action.id == actionId, dispatch.checkpoint == checkpoint',
    'prepared.checkpoint.planRevision == prepared.plan.revision',
    'dispatch.checkpoint == prepared.checkpoint',
    'else if claim == .acquired { throw AgentPlanNodeJournalError.missingDispatch }',
    'observation.verified && observation.result.actionId == actionId', 'prepared.plan.actions.filter',
    'journal.claim(prepared.key, action: prepared.action, checkpoint: prepared.checkpoint)',
    'let result = operation()', 'try journal.record(prepared.key', '"observation_commit_failed"',
    '"plan_node_outcome_unknown": "true"', '"execution_started": "false"', '"non_retriable": "true"']) assert(helper.includes(token), token);
  assert(helper.indexOf('journal.claim(prepared.key') < helper.indexOf('let result = operation()'));
  assert(helper.indexOf('checkpoint.planRevision == plan.revision', helper.indexOf('  static func replay(')) < helper.indexOf('journal.observe(key)'));
  assert(helper.indexOf('let dispatch = try journal.readDispatch(prepared.key)') < helper.indexOf('let result = operation()'));
  assert(helper.indexOf('let result = operation()') < helper.indexOf('try journal.record(prepared.key'));
  assert(!/URLSession|grantedPermissions|grantedConsents|Task\.detached|\.clear\(/.test(helper));
  for (const name of ['AgentPlanNodeJournal', 'AgentPlanLifecyclePolicy', 'AgentExecutionContinuity', 'AgentActionEffectExecutor',
    'AgentModelToolLoop', 'AgentIOSNativeActionExecutor']) assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name);
  const reference = show('65655f0c79c6ab04121150229a65b089180f82f2', 'apps/android/app/src/main/java/com/galaxyssi/chat/MobileNativeAgentExecution.kt');
  assert(reference.includes('// Persist the checkpoint, audits and final dispatched input together before any external operation.\n    persistSession()'));
  assert(reference.includes('appendAudits(AgentAuditRecord('));
  const tests = read('apps/ios/GalaxySSITests/AgentSequentialPlanNodeDispatchTests.swift');
  for (const name of ['SequentialDispatchStagesFinalInputAndCheckpointBeforeOperation', 'SequentialDispatchReplaysObservedResultWithoutExecutingAgain',
    'SequentialPendingAndLegacyClaimsCannotGainNewExecutionAuthority', 'SequentialUnreadableClaimPreventsExternalOperation',
    'SequentialObservationCommitFailureDoesNotBecomeVerifiedSuccess', 'SequentialFallbackInputHasDistinctDurableSpecificationAndReplaysOnce',
    'SequentialPreparationRejectsMissingDuplicateAndStaleRevision', 'SequentialPreparedIdentityCannotBeChangedBeforeClaim',
    'SequentialReplayRejectsPriorRevisionAndForgedPreparedRevision', 'SequentialReplayRejectsMismatchedStoredCheckpointBeforeUsingResult',
    'SequentialReplayDoesNotLeakReceiptAcrossSessionConversationOrTurn',
    'SequentialPreparationAndReplayRejectAmbiguousActiveCheckpointAndInvalidRevision']) assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentSequentialPlanNodeDispatch', 'AgentSequentialPlanNodeDispatchTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedSequentialServices, validateSequentialPlanDispatch};
if (require.main === module) {
  validateSequentialPlanDispatch();
  console.log('iOS sequential plan-node preparation, prior-result replay and pre-effect dispatch claim source contracts passed; no native acceptance');
}
