// Source contracts only; no Swift, model, native effects or callback/concurrency execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '85908f850e5d0cc2954080a8247bb20b69995188';
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
  if (s.includes('use: .localPlanningAdmission')) {
    const first = '  private func receiveLocalModelReply(', last = '  private func deterministicLocalNativePlan(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Exact journaled local initial planning ownership only');
    s = once(s, block, section(show(base, file), first, last));
  }
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
module.exports = {retainedServices, retainedLoop, retainedAdapter};
function retainedLoop(s) {
  const cancellation = path.join(__dirname, 'check-model-loop-task-cancellation.cjs');
  if (fs.existsSync(cancellation)) s = require(cancellation).retainedLoop(s);
  if (!s.includes('  private let validateOwner: (() async throws -> Void)?')) return s;
  assert.equal(s, show(approved, app + 'AgentModelToolLoop.swift'));
  s = once(s, '  private let validateOwner: (() async throws -> Void)?\n');
  s = once(s, '    browserHandoff: AgentManagedBrowserToolExecution? = nil,\n    validateOwner: (() async throws -> Void)? = nil',
    '    browserHandoff: AgentManagedBrowserToolExecution? = nil');
  s = once(s, '    self.validateOwner = validateOwner\n');
  s = once(s, '    do { try await validateOwner?() }\n    catch { return recoveryFailed(request: request, error: error) }\n');
  s = once(s, '  private func ownershipFailure(_ state: LoopState) async -> AgentModelToolLoopOutcome? {\n' +
    '    do { try await validateOwner?(); return nil }\n    catch { return recoveryFailed(state, error: error) }\n  }\n\n');
  s = s.split('\n').filter(line => !line.includes('if let failure = await ownershipFailure(state)') &&
    !line.includes('try await validateOwner?()')).join('\n');
  s = once(s, 'func flushParallelCalls() async -> ProcessResult', 'func flushParallelCalls() -> ProcessResult');
  return s.replaceAll('await flushParallelCalls()', 'flushParallelCalls()');
}
function retainedAdapter(s) {
  const cancellation = path.join(__dirname, 'check-local-inference-cancellation.cjs');
  if (fs.existsSync(cancellation)) s = require(cancellation).retained(app + 'AgentIOSLocalModelWebToolAdapter.swift', s);
  assert.equal(s, show(approved, app + 'AgentIOSLocalModelWebToolAdapter.swift'));
  s = once(s, '  private let validateOwner: (() async throws -> Void)?\n');
  s = once(s, '    self.validateOwner = validateOwner\n');
  s = once(s, '    beforeDesktopEvidenceRecall: ((AgentMcpJSONObject) async -> Void)? = nil,\n' +
    '    validateOwner: (() async throws -> Void)? = nil', '    beforeDesktopEvidenceRecall: ((AgentMcpJSONObject) async -> Void)? = nil');
  s = once(s, '    offerTeamReview: Bool = false,\n    validateOwner: (() async throws -> Void)? = nil', '    offerTeamReview: Bool = false');
  s = once(s, '      },\n      validateOwner: validateOwner\n', '      }\n');
  s = once(s, '      browserHandoff: managedBrowser,\n      validateOwner: validateOwner', '      browserHandoff: managedBrowser');
  s = s.split('\n').filter(line => !line.includes('try await validateOwner?()')).join('\n');
  s = once(s, '    try beforeInference?()\n    if beforeInference != nil', '    if beforeInference != nil');
  return once(s, '      try beforeInference?()\n      guard result.profileId', '      guard result.profileId');
}
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
  const local = section(services, '  private func receiveLocalModelReply(', '  private func deterministicLocalNativePlan(');
  assert.equal((local.match(/planningRecoveryIsCurrent\(/g) || []).length, 8);
  assert(local.indexOf('use: .localPlanningAdmission') < local.indexOf('localInitialPlanningJournal.begin('));
  assert(local.indexOf('self.planningRecoveryIsCurrent(attemptScope)') < local.indexOf('task.pendingPlanning = reference'));
  assert(local.indexOf('owned.acceptsInput(planningInput)') < local.indexOf('await modelPlannedLocalNativeActions('));
  assert(local.indexOf('planningErrorScope = owned') < local.indexOf('await modelPlannedLocalNativeActions('));
  const accepted = local.slice(local.indexOf('let owned = callbackScope, planningRecoveryIsCurrent(owned)'));
  assert(accepted.indexOf('planningErrorScope = nil') > accepted.indexOf('store.upsertAgentTask(task)'));
  assert(accepted.indexOf('planningErrorScope = nil') < accepted.indexOf('AgentIOSLocalModelWebToolRunner.run('));
  const localMutations = [local.replace('planningRecoveryIsCurrent(attemptScope),', 'true,'),
    local.replace('self.planningRecoveryIsCurrent(attemptScope)', 'true'),
    local.replace('self.planningRecoveryIsCurrent(owned), owned.acceptsInput(planningInput)', 'self.planningRecoveryIsCurrent(owned)'),
    local.replace('let owned = callbackScope, planningRecoveryIsCurrent(owned),', 'let owned = callbackScope,'),
    local.replace('      if let planningErrorScope, !planningRecoveryIsCurrent(planningErrorScope) { return }\n', ''),
    local.replace('        planningErrorScope = owned\n', '')];
  for (const mutation of localMutations) {
    assert.notEqual(mutation, local); assert.throws(() => retainedServices(services.replace(local, mutation)), assert.AssertionError);
  }
  const fallback = local.slice(local.indexOf('      guard let fallbackScope ='));
  assert(fallback.indexOf('planningErrorScope = fallbackScope') < fallback.indexOf('AgentIOSLocalModelWebToolRunner.run('));
  assert(fallback.indexOf('guard planningRecoveryIsCurrent(fallbackScope)') < fallback.indexOf('store.persistLocalResearchDisclosure'));
  const loop = read(app + 'AgentModelToolLoop.swift'), adapter = read(app + 'AgentIOSLocalModelWebToolAdapter.swift');
  assert.equal(retainedLoop(loop), show(base, app + 'AgentModelToolLoop.swift'), 'Loop changes limited to optional ownership boundaries');
  assert.equal(retainedAdapter(adapter), show(base, app + 'AgentIOSLocalModelWebToolAdapter.swift'), 'Adapter retains model selection, decoding, tool catalog and existing owner policies');
  const fallbackMutations = [local.replace('planningRecoveryIsCurrent(fallbackScope) else { return }', 'true else { return }'),
    local.replace('self.planningRecoveryIsCurrent(fallbackScope)', 'true'),
    local.replace('      planningErrorScope = fallbackScope\n', ''),
    local.replace('      guard planningRecoveryIsCurrent(fallbackScope) else { return }\n', '')];
  for (const mutation of fallbackMutations) {
    assert.notEqual(mutation, local); assert.throws(() => retainedServices(services.replace(local, mutation)), assert.AssertionError);
  }
  const ownerLines = [...loop.matchAll(/^.*(?:if let failure = await ownershipFailure\(state\)|^\s*try await validateOwner\?\(\)$).*\n/gm)];
  assert.equal(ownerLines.length, 7);
  for (const line of ownerLines) assert.throws(() => retainedLoop(loop.slice(0, line.index) + loop.slice(line.index + line[0].length)), assert.AssertionError);
  for (const token of ['    try await validateOwner?()\n', '      try await validateOwner?()\n',
    '      try beforeInference?()\n      guard result.profileId', '      validateOwner: validateOwner\n']) {
    const mutation = adapter.replace(token, ''); assert.notEqual(mutation, adapter);
    assert.throws(() => retainedAdapter(mutation), assert.AssertionError);
  }
  let loopTests = read('apps/ios/GalaxySSITests/AgentModelToolLoopTests.swift');
  const cancellation = path.join(__dirname, 'check-model-loop-task-cancellation.cjs');
  if (fs.existsSync(cancellation)) loopTests = require(cancellation).retainedTests(loopTests);
  assert.equal(loopTests, show(approved, 'apps/ios/GalaxySSITests/AgentModelToolLoopTests.swift'));
  assert.equal((loopTests.match(/  func testOwnedLoop/g) || []).length, 6);
  for (const name of ['AgentInitialPlanningJournal', 'GuardedModelAgentPlanner', 'AgentPlannerModelSnapshot', 'AgentSessionRequirement'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  const testsFile = 'apps/ios/GalaxySSITests/AgentPlanningRecoveryScopeTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 24);
  assert(!/\p{Script=Han}/u.test(helper + tests));
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => /AgentPlanningRecoveryScope(?:Tests)?\.swift/.test(line));
  assert.equal(registrations(read(projectFile)).length, 8);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  console.log('Planning and local fallback ownership, forty-six negative source mutations and thirty authored fixtures checked; no native execution.');
}
