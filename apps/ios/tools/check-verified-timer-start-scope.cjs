// Source evidence only, not Swift compilation, executed fixtures or device timer acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = 'ac32c1d74a6f22c0a8b450d0484ed4cb8f703cf2';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'), cache = new Map();
function old(file) {
  if (!cache.has(file)) cache.set(file, cp.execFileSync('git', ['show', `${base}:${file}`],
    {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  return cache.get(file);
}
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function retained(file, source) {
  if (file.endsWith('check-supervised-answer-preview-scope.cjs')) return source
    .replace("const read = file => require('./check-verified-timer-start-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-verified-timer-start-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(line =>
    !['AgentVerifiedTimerStart.swift', 'AgentVerifiedTimerStartTests.swift'].some(name => line.includes(name))).join('\n');
  if (file.endsWith('AgentIOSTimerCheckpointStore.swift')) return source
    .replace('      "duration_seconds": String(durationSeconds),\n', '')
    .replace('    evidence["execution_authority"] = "galaxyssi-phone"\n', '');
  if (file.endsWith('AgentDirectNativeToolPlanner.swift') && source.includes('  static func exactTimerStartSeconds('))
    return source.replace(section(source, '  static func exactTimerStartSeconds(', '  static func shortcutPlan('), '');
  if (file.endsWith('AgentModelPlanParser.swift')) return source.replace('    if kind == .callNativeTool, json["completes_goal"] == .bool(true) {\n      resolvedParameters[AgentVerifiedTimerStart.terminalParameter] = "true"\n    }\n', '');
  if (file.endsWith('AgentModelPlanningPrompt.swift')) return source.replace('      append(&prompt, AgentVerifiedTimerStart.argumentsContract + "\\n\\n")\n', '');
  if (file.endsWith('AgentModelPlanParserTests.swift') && source.includes('  func testTimerCompletionDeclarationRequiresLiteralBooleanTrue()'))
    return source.replace(section(source, '  func testTimerCompletionDeclarationRequiresLiteralBooleanTrue()', '  func testCompletionDiagnosticsDistinguishTargetAndMissingObservations()'), '');
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  func reconcileVerifiedTimerStarts()')) {
    source = source.replace('    var recoveredTaskCount = reconcileVerifiedTimerStarts()\n', '    var recoveredTaskCount = 0\n');
    source = source.replace('    _ = reconcileVerifiedTimerStarts()\n    drainNativeConnectorAttachmentFailures()', '    drainNativeConnectorAttachmentFailures()');
    source = source.replace(section(source, '  private func permitsVerifiedTimerStart(', '  private func finishLocalNativeAction('), '');
    source = source.replace(section(source, '    let verifiedTimerStart = task.activePlan.map {', '    let effects = task.effectRecovery ?? []'), '');
    source = source.replace('\n    AgentIOSNativeToolHandoffPresenter.openIfNeeded(result)\n', '\n    AgentIOSNativeToolHandoffPresenter.openIfNeeded(result)\n    let hasRemainingActions = !task.pendingActions.isEmpty\n');
    source = source.replace('let rollingBatchBoundary = !verifiedTimerStart && !unresolvedEffect', 'let rollingBatchBoundary = !unresolvedEffect');
  }
  return source;
}
function validate() {
  for (const file of ['GalaxySSIServices', 'AgentIOSTimerCheckpointStore', 'AgentDirectNativeToolPlanner', 'AgentModelPlanParser', 'AgentModelPlanningPrompt'])
    assert.equal(retained(app + file + '.swift', read(app + file + '.swift')), old(app + file + '.swift'), file);
  for (const file of ['apps/ios/GalaxySSI.xcodeproj/project.pbxproj', 'apps/ios/GalaxySSITests/AgentModelPlanParserTests.swift',
    'apps/ios/tools/check-supervised-answer-preview-scope.cjs']) assert.equal(retained(file, read(file)), old(file), file);
  const model = read(app + 'AgentVerifiedTimerStart.swift');
  for (const token of ['result.actionId == action.id', 'result.success', 'metadata.string("completion_verified") == "true"',
    'metadata.string("timer_state") == "running"', 'Int(metadata.string("duration_seconds")) == seconds',
    'result.metadata["native_tool_status"] == "succeeded"', 'matches.count == 1', 'observed.status == .completed',
    'observed.parameters["input_json"] == action.parameters["input_json"]', 'legacyCheckpoint?.id.uuidString',
    'legacyCheckpoint?.sourceTurnId', 'AgentPhoneNativeToolCatalog.actionExecutorId', 'legacyCheckpoint?.durationSeconds == seconds',
    'AgentCompletionEvidencePolicy.observationDiagnostics', 'requested == seconds', 'terminalParameter',
    'AgentPublicationRequirement.none', 'depends_on', 'use_outputs_from']) assert(model.includes(token), token);
  const service = read(app + 'GalaxySSIServices.swift');
  const recovery = section(service, '  func reconcileVerifiedTimerStarts()', '  private func finishLocalNativeAction(');
  for (const token of ['UIApplication.shared.isProtectedDataAvailable', 'store.canReadAgentTranscript', '!store.agentSafetySettings.executionPaused',
    '!PhoneExecutionAuthority.isCancelled', 'session.status == .active', '!session.trackingPaused',
    'AgentSequentialPlanNodeDispatch.replay(', 'AgentVerifiedTimerStart.waitingStart(', 'store.agentTask(id: task.taskId) == task',
    'finishLocalNativeAction(action: replay.action']) assert(recovery.includes(token), token);
  for (const token of ['.execute(', 'enqueueLinkPayload', 'requestPairedPhonePlan', 'makePlanner(', 'schedule(']) assert(!recovery.includes(token), token);
  const live = section(service, '  private func finishLocalNativeAction(', '  private func updateActiveNativePlan(');
  assert(live.includes('let rollingBatchBoundary = !verifiedTimerStart &&'));
  assert(live.includes('task.activePlan?.actions.removeAll { AgentVerifiedTimerStart.isReviewer'));
  assert(live.indexOf('updateActiveNativePlan(') < live.indexOf('let verifiedTimerStart ='));
  const tests = read('apps/ios/GalaxySSITests/AgentVerifiedTimerStartTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  for (const file of ['AgentSequentialPlanNodeDispatch', 'AgentPlanNodeJournal', 'AgentNativeToolCore', 'AgentNativeToolActionExecutor',
    'AgentPlanLifecyclePolicy', 'AgentPermissionsBudgetModels', 'AgentDesktopReplyRecovery', 'MqttBusinessTransportRuntime'])
    assert.equal(read(app + file + '.swift'), old(app + file + '.swift'), file);
  const coverage = JSON.parse(read('apps/ios/ANDROID_4587_PORT_COVERAGE.json'));
  assert.equal(coverage.files.length, 9);
  for (const file of coverage.files) {
    assert(file.disposition);
    assert.equal(crypto.createHash('sha256').update(cp.execFileSync('git', ['show', `${coverage.androidHead}:${file.path}`], {cwd: root})).digest('hex'), file.sha256, file.path);
  }
  for (const name of ['AgentVerifiedTimerStart.swift', 'AgentVerifiedTimerStartTests.swift'])
    assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n').filter(line => line.includes(name)).length, 4);
  console.log('Verified timer start, journal-only recovery, exact reviewer pruning and retained dispatch/receipt source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
