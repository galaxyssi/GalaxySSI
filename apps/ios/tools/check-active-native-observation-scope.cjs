// Source contracts only; no Swift timers, transport, recovery or native fixtures executed.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const {snapshot, normalizePending} = require('./observation-scope-baseline.cjs');
const project = (file, source) => require('./check-mqtt-path-diagnostics-scope.cjs').retained(file, normalizePending(file, source));
const read = file => project(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const expected = file => project(file, snapshot(file));
function assertReviewedSource(file, source) { assert.equal(project(file, source), expected(file), file + ' outside reviewed wake scope'); }
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
const properties = '  private var nativeConnectorObservationJobs: [String: (token: UUID, clock: String, task: Task<Void, Never>)] = [:]\n' +
  '  private var nativeConnectorObservationLastWake: [String: Int64] = [:]\n';
const commit = `    if store.commitOwnedAgentTaskState(expected: task, updated: updated) {
      scheduleNativeConnectorObservation(action: retained, pending: observed)
    }`;
const resume = `            let record = try? managedDesktopReplyLedger.recoveryRecord(owner: run) else { continue }
      if record.state == .pending {
        scheduleNativeConnectorObservation(action: action, pending: pending)
        continue
      }
      guard let settled = AgentNativeConnectorContinuation.settle(pending, record: record) else { continue }`;
function retained(file, source) {
  source = require('./check-mqtt-path-diagnostics-scope.cjs').retained(file, source);
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  private func nativeConnectorObservationContext(')) return source
    .replace(properties, '')
    .replace('    nativeConnectorObservationJobs.values.forEach { $0.task.cancel() }\n', '')
    .replace(section(source, '  private func nativeConnectorObservationContext(', '  private func recordNativeConnectorObservation('), '')
    .replace(commit, '    _ = store.commitOwnedAgentTaskState(expected: task, updated: updated)')
    .replace('    scheduleNativeConnectorObservation(action: waiting, pending: pendingResult)\n', '')
    .replace(resume, '            let record = try? managedDesktopReplyLedger.recoveryRecord(owner: run),\n' +
      '            let settled = AgentNativeConnectorContinuation.settle(pending, record: record) else { continue }');
  if (file.endsWith('AgentAutomationModels.swift') && source.includes('enum AgentNativeConnectorObservationWakePolicy {'))
    return source.replace(section(source, 'enum AgentNativeConnectorObservationWakePolicy {', 'enum AgentProactiveTaskError:'), '');
  if (file.endsWith('AgentConnectorTimeoutResolverTests.swift') && source.includes('  func testActiveObservationWakeUsesUnacceptedAndAcceptedStageClocks'))
    return source.replace(section(source, '  func testActiveObservationWakeUsesUnacceptedAndAcceptedStageClocks',
      '  func testObservationDeadlineUsesStageSpecificAnchors'), '');
  if (file.endsWith('check-native-delivery-acceptance-scope.cjs')) return source
    .replace("const read = file => require('./check-active-native-observation-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-active-native-observation-scope.cjs').retained(file, source);\n", '');
  return source;
}
function validate() {
  for (const file of [app + 'GalaxySSIServices.swift', app + 'AgentAutomationModels.swift',
    'apps/ios/GalaxySSITests/AgentConnectorTimeoutResolverTests.swift', 'apps/ios/tools/check-native-delivery-acceptance-scope.cjs']) {
    assertReviewedSource(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
    assert.equal(retained(file, read(file)), retained(file, expected(file)), file);
  }
  const service = read(app + 'GalaxySSIServices.swift');
  const wake = section(service, '  private func nativeConnectorObservationContext(', '  private func recordNativeConnectorObservation(');
  for (const token of ['UIApplication.shared.isProtectedDataAvailable', 'UIApplication.shared.applicationState == .active',
    '!store.agentSafetySettings.executionPaused', 'store.agentSafetySettings.taskExecutionMode != .planOnly',
    '!PhoneExecutionAuthority.isCancelled', 'queuedNativeConnectorContext(dispatch, requireExecution: false)',
    'current.task.phase == .waitingResponse', 'current.task.lastNativeActionResult?.metadata["control_plane_run_id"]',
    'AgentIOSConnectorDispatch.permissionKey', 'privateMode == false', 'AgentDesktopReplyDiscoveryPolicy.isDesktopEndpoint(contact)',
    'record.executionGeneration == Int64', 'prepared.parameters.removeValue(forKey: AgentNativeConnectorContinuation.receiptKey)',
    'prepared.parameters.removeValue(forKey: AgentNativeConnectorContinuation.sourceKey)', 'let scoped = prepared',
    'nativeConnectorObservationJobs[key]?.token == token', 'nativeConnectorObservationJobs.count < 200',
    'Task.sleep(nanoseconds:', 'if wake.delayMillis > 0', 'taskIdentityStore.identity(',
    'AgentDesktopReplyBinding.managed(', 'currentManagedDesktopReply(binding) != nil',
    'desktopReplyRecoveryOwner == store.profile.identityFingerprint', 'desktopReplyRecovery.track(binding,',
    'desktopReplyRecovery.record(for: binding) != nil', 'await sweepDesktopReplyRecovery()']) assert(wake.includes(token), token);
  for (const token of ['handleConnectorTimeout(', 'connectorFallbackAction(', 'connectorResponseBus.publish(',
    'startQueuedConnector(', 'enqueueLinkPayload(', '.release(', 'mqttClient.publish', 'runtime.poll(']) assert(!wake.includes(token), token);
  assert(service.includes(commit) && service.includes(resume));
  assert(service.includes('    scheduleNativeConnectorObservation(action: waiting, pending: pendingResult)\n'));
  assert(service.includes('    nativeConnectorObservationJobs.values.forEach { $0.task.cancel() }\n'));
  const policy = section(read(app + 'AgentAutomationModels.swift'), 'enum AgentNativeConnectorObservationWakePolicy {', 'enum AgentProactiveTaskError:');
  for (const token of ['var clock = metadata', 'AgentConnectorTimingPolicy.deadlineStartMillis(',
    'AgentConnectorTimingPolicy.deadlines(', 'AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(',
    'AgentDesktopReplyRecoveryRecord.probeInterval', 'delayMillis: max(remaining, throttle)', 'nowMillis >= start']) assert(policy.includes(token), token);
  for (const token of ['UserDefaults', 'FileManager', 'URLSession', 'result.success', 'shouldFailOver', 'remaining_fallback_ids']) assert(!policy.includes(token), token);
  const tests = section(read('apps/ios/GalaxySSITests/AgentConnectorTimeoutResolverTests.swift'),
    '  func testActiveObservationWakeUsesUnacceptedAndAcceptedStageClocks', '  func testObservationDeadlineUsesStageSpecificAnchors');
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  for (const name of ['AgentIOSConnectorDispatch', 'AgentDesktopReplyRecovery', 'MqttBusinessTransportRuntime',
    'MqttDesktopConnectorProjection', 'AgentConnectorTaskStatusRecorder', 'AgentConnectorTimeoutResolver',
    'AgentConnectorTransportReceiptRecorder', 'AgentPhoneNativeToolCatalog', 'AgentPhoneNativeToolCatalogDefaults'])
    assert.equal(read(app + name + '.swift'), expected(app + name + '.swift'), name);
  console.log('Owned active observation wake, stage/probe clocks, lifecycle/source guards and eight authored fixtures source contracts passed; no native acceptance.');
}
module.exports = {retained, validate, assertReviewedSource};
if (require.main === module) validate();
