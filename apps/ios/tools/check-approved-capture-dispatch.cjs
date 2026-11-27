// Source-only checks; no camera, microphone, Swift or native fault-injection execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '43fa7602dad7ba6df27ac67c992421d5b25cf408';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const pairingFile = path.join(__dirname, 'check-pairing-history.cjs');
const pairing = fs.existsSync(pairingFile) && fs.readFileSync(pairingFile, 'utf8').includes('function retainedPairingStore(') ? require(pairingFile) : null;
function section(source) {
  const begin = source.indexOf('  private func dispatchApprovedCapture(\n');
  const end = source.indexOf('  private func recordCapturePermissionEvent(\n', begin);
  assert(begin >= 0 && end > begin);
  assert.equal(source.split('  private func dispatchApprovedCapture(\n').length, 2);
  return source.slice(begin, end);
}
function retainedApprovedCaptureServices(source) {
  if (!source.includes('AgentApprovedCaptureDispatch.prepare(')) return source;
  return source.replace(section(source), section(old(app + 'GalaxySSIServices.swift')));
}
function retainedCaptureEnvelope(helper) {
  if (!helper.includes('plannerProfile: "legacy-capture-dispatch"')) return helper;
  const begin = helper.indexOf('    let plan: AgentPlan\n'), end = helper.indexOf('    guard let node =', begin);
  assert(begin >= 0 && end > begin);
  assert.equal(helper.split('    let plan: AgentPlan\n').length, 2);
  return helper.slice(0, begin) + '    let plan = task.activePlan ?? AgentPlanFactory.singleAction(\n      request: AgentPlanRequest(goal: task.goal, screen: screen), action: original)\n' + helper.slice(end);
}
module.exports = {retainedApprovedCaptureServices, retainedCaptureEnvelope};
if (require.main === module) {
  const services = read(app + 'GalaxySSIServices.swift'), capture = section(services);
  const retained = retainedApprovedCaptureServices(services);
  assert.equal(pairing ? pairing.retainedPairingServices(retained) : retained, old(app + 'GalaxySSIServices.swift'), 'Only approved capture dispatch and exact approved pairing changes');
  for (const token of ['wait.acceptsCallback(in: task, outgoing: outgoing)', 'PhoneExecutionAuthority.isCancelled',
    'UIApplication.shared.applicationState == .active', 'AgentIOSCaptureSystemPermission.state(for: wait.kind) == .granted',
    '!store.agentSafetySettings.executionPaused', 'store.agentSafetySettings.taskExecutionMode != .planOnly',
    'wait.permissionMode == store.agentSafetySettings.permissionMode', 'rejectReadOnlyAnalysisAction',
    'AgentApprovedCaptureDispatch.prepare', 'store.commitOwnedAgentTaskState(expected: task, updated: prepared.task)',
    'task = prepared.task', 'let journal = localPlanNodeJournal',
    'galaxyssi.agent.capture_permission.checkpoint_unsaved',
    'AgentSequentialPlanNodeDispatch.execute(prepared.node, journal: journal)',
    'dispatched.action(in: current, outgoing: outgoing) == action', 'self.captureDispatches[wait.taskId] == wait.token']) assert(capture.includes(token), token);
  assert(capture.indexOf('store.commitOwnedAgentTaskState') < capture.indexOf('captureDispatches[task.taskId] = wait.token'));
  assert(capture.indexOf('store.commitOwnedAgentTaskState') < capture.indexOf('Task { @MainActor'));
  assert(capture.indexOf('AgentSequentialPlanNodeDispatch.execute') < capture.indexOf('executor.execute(action: executionAction'));
  assert(!capture.includes('store.upsertAgentTask(task)'), 'Capture cannot ignore a task-state commit failure');
  const helper = read(app + 'AgentApprovedCaptureDispatch.swift');
  for (const token of ['wait.acceptsCallback(in: task, outgoing: outgoing)', 'wait.action(in: task, outgoing: outgoing)',
    'task.activePlan?.executionMode != .planOnly', 'executionAction.id == original.id', 'executionAction.kind == original.kind',
    'executionAction.target == original.target', 'executionAction.parameters["input_json"] == original.parameters["input_json"]',
    'if let active = task.activePlan { plan = active }', 'AgentSequentialPlanNodeDispatch.prepare(plan: plan',
    'updated.activePlan = node.plan', 'AgentCapturePermissionContinuation(task: updated',
    'dispatched.token = wait.token', 'dispatched.dispatched = true', 'updated.capturePermission = dispatched']) assert(helper.includes(token), token);
  for (const name of ['task', 'session', 'conversation', 'turn', 'contact']) assert(helper.includes(`executionAction.parameters["_galaxyssi_${name}_id"]`));
  for (const token of ['task.planContext == nil, task.pendingPlanning == nil, !task.blocked',
    'task.taskId == wait.turnId, task.sessionId == wait.conversationId', 'actions.first == original',
    'Set(actions.map(\\.id)).count == actions.count', '[.proposed, .pendingConfirmation].contains($0.status)',
    'scope.owns($0)', 'steps: [], actions: actions', 'plannerProfile: "legacy-capture-dispatch"']) assert(helper.includes(token), token);
  assert(!helper.includes('AgentPlanFactory'), 'Preserve queued actions without aliasing, rewriting or collapsing calls');
  const priorHelper = clean(cp.execFileSync('git', ['show', 'c6bad3465c673dfb2dcecb23b095185c129c7447:' + app + 'AgentApprovedCaptureDispatch.swift'], {cwd: root, encoding: 'utf8'}));
  assert.equal(retainedCaptureEnvelope(helper),
    priorHelper, 'Only legacy capture envelope construction changes; permission identity, final input, checkpoint and dispatched ticket remain exact');
  assert(!/URLSession|UIApplication|AVCapture|\.execute\(|grantedPermissions|grantedConsents/.test(helper), 'Preparation does not execute or grant OS permission');
  for (const file of ['AgentSequentialPlanNodeDispatch', 'AgentPlanNodeJournal', 'AgentIOSVisibleCaptureNativeTools',
    'AgentIOSForegroundVisibleCaptureProvider', 'AgentIOSVisibleCaptureUIKitSurfaces', 'AgentActionEffectExecutor', 'GalaxySSIStore'])
    assert.equal(file === 'GalaxySSIStore' && pairing ? pairing.retainedPairingStore(read(app + file + '.swift')) : read(app + file + '.swift'),
      old(app + file + '.swift'), file + ' unchanged outside the exact approved pairing version');
  const tests = read('apps/ios/GalaxySSITests/AgentApprovedCaptureDispatchTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 12);
  for (const token of ['legacy.activePlan = nil', 'AgentIOSVisibleCaptureKind.allCases', 'kind: .photo',
    'testOwnedTaskAndDispatchIntentAreDurableBeforeSyntheticCaptureStarts', 'testCancelledOrStaleTaskCannotCommitThePreparedCaptureIntent',
    'testInterruptedClaimSurvivesReloadWithoutRepeatingTheCameraOrMicrophone',
    'testSavedObservationReplaysWithoutStartingAnotherCapture', 'testJournalFailureNeverProducesVerifiedCaptureSuccess',
    'observation_commit_failed', 'testLegacyCapturePreservesTheWholeQueueWithoutApprovingLaterActions',
    'testLegacyCaptureQueueIsDurableBeforeTheFirstSyntheticCapture', 'testSecondCaptureUsesTheSamePlanButANewPermissionAndNode',
    'testLegacyQueueCannotInventProofForMissingPlansOrForeignActions', 'XCTAssertNotEqual(second.node.key, first.node.key)',
    'XCTAssertNotEqual(wait.token, fixture.wait.token)', 'AgentRollingPlanPolicy.shouldRequestNextBatch']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentApprovedCaptureDispatch', 'AgentApprovedCaptureDispatchTests']) {
    assert.equal(project.split(name + '.swift in Sources').length - 1, 2);
    assert.equal(project.split('path = ' + name + '.swift;').length - 1, 1);
  }
  assert(!/\p{Script=Han}/u.test(helper + tests));
  const reference = cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/MobileNativeAgentExecution.kt'], {cwd: root, encoding: 'utf8'});
  assert(reference.includes('// Persist the checkpoint, audits and final dispatched input together before any external operation.\n    persistSession()'));
  console.log('Approved capture pre-effect commit, complete legacy queue, independent permission and journal/source contracts passed; twelve native test methods authored, not executed.');
}
