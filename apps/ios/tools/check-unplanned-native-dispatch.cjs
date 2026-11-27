// Source contracts only; no Swift/native execution or persistence acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
function retainedUnplannedDispatchServices(source) {
  if (!source.includes('AgentUnplannedNativeDispatch.plan(')) return source;
  const changes = [
    ['    if priorDispatch == nil {\n      guard let prepared = checkpointSequentialPlanNodeDispatch',
      '    if priorDispatch == nil, task.activePlan != nil || executionAction.kind == .callConnector {\n      guard let prepared = checkpointSequentialPlanNodeDispatch'],
    ['    } else {\n      return true\n    }\n    if !result.success,\n       action.kind == .callConnector,',
      '    } else {\n      result = runtime.actionExecutor.execute(action: executionAction, screen: screen)\n    }\n    if !result.success,\n       action.kind == .callConnector,'],
    ['    if !store.agentSafetySettings.executionPaused, store.agentSafetySettings.taskExecutionMode != .planOnly,\n      !PhoneExecutionAuthority.isCancelled(taskId: task.taskId),\n      let plan = AgentUnplannedNativeDispatch.plan(task: task, action: action, outgoing: outgoing, screen: screen),\n      let prepared = AgentSequentialPlanNodeDispatch.prepare(plan: plan, action: action,',
      '    if let plan = task.activePlan, let prepared = AgentSequentialPlanNodeDispatch.prepare(plan: plan, action: action,']
  ];
  for (const [from, to] of changes) { assert.equal(source.split(from).length, 2, from); source = source.replace(from, to); }
  return source;
}
module.exports = {retainedUnplannedDispatchServices};
if (require.main === module) {
  const services = read(app + 'GalaxySSIServices.swift');
  const browserFile = path.join(__dirname, 'check-browser-view-ownership.cjs');
  const browser = fs.existsSync(browserFile) ? require(browserFile) : null;
  const retainedServices = retainedUnplannedDispatchServices(services);
  assert.equal(browser ? browser.retainedBrowserServices(retainedServices) : retainedServices, old(app + 'GalaxySSIServices.swift'),
    'Only mandatory sequential checkpoint/claim and unplanned envelope admission change');
  const begin = services.indexOf('  private func executeLocalNativeAction(\n'), end = services.indexOf('  private func refreshAutomaticConnectorAction(', begin);
  const execute = services.slice(begin, end);
  assert(begin >= 0 && end > begin);
  assert.equal((execute.match(/runtime\.actionExecutor\.execute\(/g) || []).length, 2, 'Both primary and fallback operations are journal wrapped');
  assert(execute.includes('if priorDispatch == nil {\n      guard let prepared = checkpointSequentialPlanNodeDispatch'));
  assert(execute.indexOf('AgentSequentialPlanNodeDispatch.replay(') < execute.indexOf('refreshAutomaticConnectorAction('));
  assert(execute.indexOf('checkpointSequentialPlanNodeDispatch(executionAction') < execute.indexOf('AgentSequentialPlanNodeDispatch.execute(dispatch'));
  const save = services.slice(services.indexOf('  private func checkpointSequentialPlanNodeDispatch('), services.indexOf('  private func retainWaitingNativeConnector('));
  for (const token of ['!store.agentSafetySettings.executionPaused', 'taskExecutionMode != .planOnly',
    '!PhoneExecutionAuthority.isCancelled(taskId: task.taskId)', 'AgentUnplannedNativeDispatch.plan(',
    'task.activePlan = prepared.plan', 'task.planContext = AgentTaskPlanContext(plan: prepared.plan)',
    'store.commitOwnedAgentTaskState(expected: previous, updated: task)', 'return nil']) assert(save.includes(token), token);
  const helper = read(app + 'AgentUnplannedNativeDispatch.swift');
  for (const token of ['plan.executionMode == .planOnly ? nil : plan', 'task.planContext == nil, task.pendingPlanning == nil',
    'task.taskId == turn', 'task.sessionId == outgoing.conversationId', 'let actions = [action] + remaining',
    '!remaining.contains(where: { $0.id == action.id })', 'Set(actions.map(\\.id)).count == actions.count',
    '[.proposed, .pendingConfirmation].contains($0.status)', 'scope.owns($0)', 'actions: actions',
    'plannerProfile: "legacy-native-dispatch"']) assert(helper.includes(token), token);
  for (const name of ['task', 'session', 'conversation', 'turn', 'contact']) assert(helper.includes(`action.parameters["_galaxyssi_${name}_id"]`));
  assert(!/AgentPlanFactory|\.execute\(|URLSession|grantedPermissions|grantedConsents|UUID\(/.test(helper), 'Envelope does not rewrite actions, execute, route or grant');
  for (const name of ['AgentPlanNodeJournal', 'AgentSequentialPlanNodeDispatch', 'AgentPlanRunModels', 'AgentActionEffectExecutor',
    'AgentApprovedCaptureDispatch', 'AgentIOSNativeActionExecutor', 'AgentModelToolLoop', 'GalaxySSIStore',
    'AgentExecutionContinuity', 'AgentPlanLifecyclePolicy']) {
    const source = read(app + name + '.swift');
    const captureEnvelope = require('./check-approved-capture-dispatch.cjs').retainedCaptureEnvelope;
    let retained = name === 'AgentApprovedCaptureDispatch' && captureEnvelope ? captureEnvelope(source) : source;
    if (name === 'AgentPlanRunModels' && browser) retained = browser.retainedBrowserTaskModels(retained);
    assert.equal(retained, old(app + name + '.swift'), name);
  }
  const tests = read('apps/ios/GalaxySSITests/AgentUnplannedNativeDispatchTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 8);
  for (const token of ['testNextActionRetainsTheOriginalEnvelopeAndIndependentNodeIdentity',
    'testCancelledStoreStateRejectsThePreparedEnvelopeBeforeDispatch', 'testPendingOriginalClaimCannotBeRedispatchedAfterRestore',
    'XCTAssertEqual(calls, 1)', 'XCTAssertEqual(calls, 0)', '"plan_node_outcome_unknown"', '.planOnly']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentUnplannedNativeDispatch', 'AgentUnplannedNativeDispatchTests']) {
    assert.equal(project.split(name + '.swift in Sources').length - 1, 2);
    assert.equal(project.split('path = ' + name + '.swift;').length - 1, 1);
  }
  const reference = cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/MobileNativeAgentExecution.kt'], {cwd: root, encoding: 'utf8'});
  assert(reference.includes('// Persist the checkpoint, audits and final dispatched input together before any external operation.\n    persistSession()'));
  assert(!/\p{Script=Han}/u.test(helper + tests));
  console.log('Unplanned native task commit, mandatory journal dispatch and replay source contracts passed; eight XCTest methods authored, not executed.');
}
