// Source contracts only; no Swift, model, native effects or callback/concurrency execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '1b7492677dd0544c2eda51433cc44659d9c4554e';
const file = app + 'GalaxySSIServices.swift', clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to = '') { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(b > a, last); return s.slice(a, b);
}
function retainedServices(s) {
  if (s.includes('use: .initialProviderAdmission')) {
    const first = '  private func receivePhoneOwnedProviderReplyInScope(', last = '  private func receiveLocalModelReply(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Exact initial selected-provider ownership only');
    s = once(s, block, section(show(base, file), first, last));
  }
  if (s.includes('  private func planningRecoveryIsCurrent(')) {
    const first = '  private func planningRecoveryIsCurrent(', last = '  func resumePendingAgentDelivery() {';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Exact recovery-attempt input/callback ownership only');
    s = once(s, block, section(show(base, file), '  @discardableResult\n  func recoverInterruptedInitialPlanning()', last));
  }
  if (s.includes('use: .userReplan')) {
    const first = '  @discardableResult\n  @MainActor\n  func replanLocalNativeAction(',
      last = '  @discardableResult\n  func retryFailedLocalNativeAction(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Exact explicit replanning attempt/callback ownership only');
    s = once(s, block, section(show(base, file), first, last));
  }
  if (s.includes('use: .rollingContinuation')) {
    const first = '  private func continueRollingNativePlan(', last = '  @discardableResult\n  private func acceptRollingPlanningOutcome(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Exact rolling continuation attempt/callback ownership only');
    s = once(s, block, section(show(base, file), first, last));
  }
  return s;
}
module.exports = {retainedServices};
if (require.main === module) {
  const services = read(file); let unchanged = retainedServices(services);
  for (const [name, method] of [['check-parallel-native-dispatch-ownership', 'retainedServices'],
    ['check-native-recovery-query-ownership', 'retainedServices'], ['check-native-observation-expiry-scope', 'retainedServices'],
    ['check-observation-job-lifecycle-scope', 'retainedServices'], ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
    ['check-browser-view-ownership', 'retainedBrowserServices'], ['check-pairing-history', 'retainedPairingServices']]) {
    const optional = path.join(__dirname, name + '.cjs');
    if (fs.existsSync(optional)) unchanged = require(optional)[method](unchanged);
  }
  assert.equal(unchanged, show(base, file), 'All other coordinator, provider selection and dispatch policy retained');
  const recovery = section(services, '  private func planningRecoveryIsCurrent(', '  func resumePendingAgentDelivery() {');
  assert.equal((recovery.match(/planningRecoveryIsCurrent\(scope\)/g) || []).length, 8);
  assert.equal((recovery.match(/scope.acceptsInput\(input\)/g) || []).length, 2);
  assert.equal((recovery.match(/recoveryProfile == store.profile.identityFingerprint/g) || []).length, 2);
  const initial = section(recovery, '  func recoverInterruptedInitialPlanning()', '  private func recoverInterruptedReplanning()');
  const replan = recovery.slice(recovery.indexOf('  private func recoverInterruptedReplanning()'));
  assert(initial.includes('$0.phase == .planning && $0.activePlan == nil && $0.pendingPlanning != nil && !$0.blocked'));
  assert(replan.includes('$0.phase == .planning && $0.activePlan != nil && $0.pendingPlanning?.isReplanning == true'));
  for (const block of [initial, replan]) {
    assert(block.indexOf('scope.acceptsInput(input)') < block.indexOf('self.modelPlannedLocalNativeActions('));
    const caught = block.slice(block.indexOf('      } catch {'));
    assert(caught.indexOf('planningRecoveryIsCurrent(scope)') < caught.indexOf('task.phase = .paused'));
    assert(block.includes('guard planningRecoveryIsCurrent(scope), var task = store.agentTask(id: candidate.taskId)'));
  }
  const helperFile = app + 'AgentPlanningRecoveryScope.swift', helper = read(helperFile);
  assert.equal(helper, show(approved, helperFile));
  for (const token of ['task.phase == .planning, !task.blocked', 'reference.sessionId == task.sessionId',
    'reference.turnId == task.taskId', 'task.activePlan?.revision == reference.baseRevision',
    'input.conversation.privateMode == privateMode && input.conversation.trackingPaused == trackingPaused',
    '!cancelled, profile == self.profile, task == expectedPersistedTask', 'conversation.status == .active',
    'expectedPersistedTask = use == .initialProviderAdmission ? nil : task',
    'if task.phase == .planning, use != .initialProviderAdmission',
    'guard task.phase == .planning, !task.blocked || task.pendingPlanning?.isReplanning == true',
    'conversation.trackingPaused == trackingPaused, conversation.mergedIntoConversationId.isBlank',
    'conversation.sessionRequirement == sessionRequirement', 'source.richOutputJson == self.source.richOutputJson',
    'source.voiceTranscript == self.source.voiceTranscript']) assert(helper.includes(token), token);
  assert(!/FileManager|UserDefaults|URLSession|\.execute\(|\.publish\(|\.claim\(|\.remove\(|grantedPermissions/.test(helper));
  const mutations = [recovery.replace('self.planningRecoveryIsCurrent(scope), scope.acceptsInput(input)', 'scope.acceptsInput(input)'),
    recovery.replace('self.planningRecoveryIsCurrent(scope), scope.acceptsInput(input)', 'self.planningRecoveryIsCurrent(scope)'),
    recovery.replace('guard planningRecoveryIsCurrent(scope), var task', 'guard var task'),
    recovery.replace('      } catch {\n        guard planningRecoveryIsCurrent(scope), var task', '      } catch {\n        guard var task'),
    recovery.replace('recoveryProfile == store.profile.identityFingerprint', 'true'),
    recovery.replace('store.canReadAgentTranscript && ', ''),
    recovery.replace('Task.isCancelled || PhoneExecutionAuthority.isCancelled(taskId: scope.task.taskId)', 'false'),
    recovery.replace('source: store.persistedMessage(id: scope.source.id, contactId: scope.source.contactId)', 'source: scope.source')];
  for (const mutation of mutations) {
    assert.notEqual(mutation, recovery); assert.throws(() => retainedServices(services.replace(recovery, mutation)), assert.AssertionError);
  }
  const manual = section(services, '  @discardableResult\n  @MainActor\n  func replanLocalNativeAction(',
    '  @discardableResult\n  func retryFailedLocalNativeAction(');
  assert.equal((manual.match(/planningRecoveryIsCurrent\(/g) || []).length, 6);
  assert.equal((manual.match(/use: \.userReplan/g) || []).length, 2);
  assert(!recovery.includes('use: .userReplan'), 'Automatic recovery never gains explicit-replan scope');
  assert(manual.indexOf('self.planningRecoveryIsCurrent(attemptScope)') < manual.indexOf('committedReference = reference'));
  const noPlan = manual.slice(manual.indexOf('    } else {\n      modelOutcome = await modelPlannedLocalNativeActions('));
  assert(noPlan.indexOf('await modelPlannedLocalNativeActions(') < noPlan.indexOf('planningRecoveryIsCurrent(attemptScope)'));
  assert(noPlan.indexOf('planningRecoveryIsCurrent(attemptScope)') < noPlan.indexOf('if case let .recoveryRequired'));
  const manualMutations = [manual.replace('planningRecoveryIsCurrent(attemptScope) else { return false }', 'true else { return false }'),
    manual.replace('self.planningRecoveryIsCurrent(attemptScope)', 'true'),
    manual.replace('self.planningRecoveryIsCurrent(owned), owned.acceptsInput(input)', 'self.planningRecoveryIsCurrent(owned)'),
    manual.replace('        guard planningRecoveryIsCurrent(callbackScope ?? attemptScope) else { return false }\n', ''),
    manual.replace('let owned = callbackScope, planningRecoveryIsCurrent(owned), let reference', 'let owned = callbackScope, let reference'),
    manual.replace('      )\n      guard planningRecoveryIsCurrent(attemptScope) else { return false }\n    }\n    if case', '      )\n    }\n    if case')];
  for (const mutation of manualMutations) {
    assert.notEqual(mutation, manual); assert.throws(() => retainedServices(services.replace(manual, mutation)), assert.AssertionError);
  }
  const rolling = section(services, '  private func continueRollingNativePlan(',
    '  @discardableResult\n  private func acceptRollingPlanningOutcome(');
  assert.equal((rolling.match(/planningRecoveryIsCurrent\(/g) || []).length, 5);
  assert.equal((rolling.match(/use: \.rollingContinuation/g) || []).length, 2);
  assert(rolling.includes('!AgentNativeConnectorContinuation.hasWaitingAction(task)'));
  assert(rolling.includes('previousResult.metadata["awaiting_response"] != "true"'));
  assert(rolling.indexOf('self.planningRecoveryIsCurrent(attemptScope)') < rolling.indexOf('committedReference = reference'));
  assert(rolling.indexOf('owned.acceptsInput(planningInput)') < rolling.indexOf('await modelPlannedLocalNativeActions('));
  assert(rolling.indexOf('planningRecoveryIsCurrent(owned), let reference = committedReference') < rolling.indexOf('task.pendingPlanning = nil'));
  const rollingMutations = [rolling.replace('planningRecoveryIsCurrent(attemptScope) else { return }', 'true else { return }'),
    rolling.replace('self.planningRecoveryIsCurrent(attemptScope)', 'true'),
    rolling.replace('self.planningRecoveryIsCurrent(owned), owned.acceptsInput(planningInput)', 'self.planningRecoveryIsCurrent(owned)'),
    rolling.replace('      guard planningRecoveryIsCurrent(callbackScope ?? attemptScope) else { return }\n', ''),
    rolling.replace('let owned = callbackScope, planningRecoveryIsCurrent(owned), let reference', 'let owned = callbackScope, let reference'),
    rolling.replace('!AgentNativeConnectorContinuation.hasWaitingAction(task)', 'true')];
  for (const mutation of rollingMutations) {
    assert.notEqual(mutation, rolling); assert.throws(() => retainedServices(services.replace(rolling, mutation)), assert.AssertionError);
  }
  const provider = section(services, '  private func receivePhoneOwnedProviderReplyInScope(', '  private func receiveLocalModelReply(');
  assert.equal((provider.match(/planningRecoveryIsCurrent\(/g) || []).length, 5);
  assert(provider.indexOf('use: .initialProviderAdmission') < provider.indexOf('localInitialPlanningJournal.begin('));
  assert(provider.indexOf('self.planningRecoveryIsCurrent(attemptScope)') < provider.indexOf('task.pendingPlanning = reference'));
  assert(provider.indexOf('owned.acceptsInput(input)') < provider.indexOf('await modelPlannedLocalNativeActions('));
  assert(provider.indexOf('let owned = callbackScope, planningRecoveryIsCurrent(owned)') < provider.indexOf('task.phase = .executing'));
  assert(provider.indexOf('guard planningRecoveryIsCurrent(callbackScope ?? attemptScope)') < provider.indexOf('task.phase = .failed'));
  const providerMutations = [provider.replace('planningRecoveryIsCurrent(attemptScope), attemptScope.acceptsInput(input)', 'attemptScope.acceptsInput(input)'),
    provider.replace('self.planningRecoveryIsCurrent(attemptScope)', 'true'),
    provider.replace('self.planningRecoveryIsCurrent(owned), owned.acceptsInput(input)', 'self.planningRecoveryIsCurrent(owned)'),
    provider.replace('let owned = callbackScope, planningRecoveryIsCurrent(owned),', 'let owned = callbackScope,'),
    provider.replace('      guard planningRecoveryIsCurrent(callbackScope ?? attemptScope) else { return }\n', '')];
  for (const mutation of providerMutations) {
    assert.notEqual(mutation, provider); assert.throws(() => retainedServices(services.replace(provider, mutation)), assert.AssertionError);
  }
  for (const name of ['AgentInitialPlanningJournal', 'GuardedModelAgentPlanner', 'AgentModelToolLoop', 'AgentPlannerModelSnapshot', 'AgentSessionRequirement'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  const testsFile = 'apps/ios/GalaxySSITests/AgentPlanningRecoveryScopeTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 21);
  assert(!/\p{Script=Han}/u.test(helper + tests));
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => /AgentPlanningRecoveryScope(?:Tests)?\.swift/.test(line));
  assert.equal(registrations(read(projectFile)).length, 8);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  console.log('Startup/manual/rolling/selected-provider ownership, twenty-five negative source mutations and twenty-one authored fixtures checked; no native execution.');
}
