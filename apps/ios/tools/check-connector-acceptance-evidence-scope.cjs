// Source contracts only, not executed Swift, transport or timeout acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const acceptance = '    // Authenticated remote status proves acceptance; later progress must not restart that clock.\n' +
  '    if result.metadata["transport_accepted_at"] == nil {\n' +
  '      result.metadata["transport_accepted_at"] = String(observation.lastResponseAt)\n    }\n';
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function retained(file, source) {
  if (file.endsWith('AgentIOSConnectorDispatch.swift')) return source.replace(
    '        "execution_generation": "1",\n', '        "execution_generation": "1", "remote_task_status": "queued",\n');
  if (file.endsWith('AgentConnectorTaskStatusRecorder.swift')) return source.replace(acceptance, '');
  const fixtures = [
    ['AgentControlPlaneActionExecutorTests.swift', 'testQueuedConnectorPreparationDoesNotFabricateRemoteAcceptance',
      'testOwnedConnectorRunIdentitySeparatesRetriesAndPreservesFirstManualIdentity'],
    ['AgentNativeConnectorStatusObservationTests.swift', 'testFirstAuthenticatedStatusAnchorsAcceptanceWithoutResettingLaterProgress',
      'testOwnedProgressPersistsStatusWithoutChangingExecutionResultOrIdentity']
  ];
  for (const [name, start, end] of fixtures) if (file.endsWith(name) && source.includes('  func ' + start))
    return source.replace(section(source, '  func ' + start, '  func ' + end), '');
  if (file.endsWith('check-desktop-probe-owner-scope.cjs')) return source
    .replace("const read = file => require('./check-connector-acceptance-evidence-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-connector-acceptance-evidence-scope.cjs').retained(file, source);\n", '');
  return source;
}
function validate() {
  for (const file of [app + 'AgentIOSConnectorDispatch.swift', app + 'AgentConnectorTaskStatusRecorder.swift',
    'apps/ios/GalaxySSITests/AgentControlPlaneActionExecutorTests.swift',
    'apps/ios/GalaxySSITests/AgentNativeConnectorStatusObservationTests.swift',
    'apps/ios/tools/check-desktop-probe-owner-scope.cjs']) assert.equal(retained(file, read(file)), old(file), file);
  const prepare = section(read(app + 'AgentIOSConnectorDispatch.swift'), '  static func prepare(', '  func matchesWaitingAction(');
  assert(!prepare.includes('"remote_task_status"'));
  for (const token of ['message: "Queued"', '"awaiting_response": "true"', '"completion_verified": "false"',
    '"resource_started_at"', '"execution_generation": "1"']) assert(prepare.includes(token), token);
  const status = read(app + 'AgentConnectorTaskStatusRecorder.swift');
  assert.equal(status.split(acceptance).length, 2);
  for (const token of ['binding.isValid', 'owner.ownerRunId == managed.ownerRunId',
    'observation.generation == managed.executionGeneration', 'observation.sequence > previousSequence',
    'observation.lastResponseAt >= previousTime', 'AgentConnectorTaskStatusRecorder.record('])
    assert(status.indexOf(token) >= 0 && status.indexOf(token) < status.indexOf(acceptance), token);
  const controlTests = read('apps/ios/GalaxySSITests/AgentControlPlaneActionExecutorTests.swift');
  const added = section(controlTests, '  func testQueuedConnectorPreparationDoesNotFabricateRemoteAcceptance',
    '  func testOwnedConnectorRunIdentitySeparatesRetriesAndPreservesFirstManualIdentity');
  assert.equal((added.match(/  func test/g) || []).length, 2);
  for (const token of ['AgentIOSConnectorDispatch.prepare(action)', 'start + 14_999', 'start + 15_000',
    'sourceMessageId: source + 1', 'contactId: "foreign"', 'nowMillis: 95_000', 'JSONDecoder()']) assert(added.includes(token), token);
  const tests = section(read('apps/ios/GalaxySSITests/AgentNativeConnectorStatusObservationTests.swift'),
    '  func testFirstAuthenticatedStatusAnchorsAcceptanceWithoutResettingLaterProgress',
    '  func testOwnedProgressPersistsStatusWithoutChangingExecutionResultOrIdentity');
  assert.equal((tests.match(/  func test/g) || []).length, 2);
  for (const token of ['["queued", "running"]', 'observation.sequence += 1', 'observation.lastResponseAt = 5_000',
    '.notRunning : .readOnlyStale', 'pending.metadata["transport_accepted_at"] = "1500"']) assert(tests.includes(token), token);
  for (const name of ['GalaxySSIServices', 'AgentAutomationModels', 'AgentConnectorTimeoutResolver',
    'AgentConnectorTransportReceiptRecorder', 'AgentConnectorResponseResolver', 'AgentDesktopReplyRecovery',
    'AgentControlPlaneActionExecutorModels', 'MqttBusinessTransportRuntime', 'AgentManagedResponseModels'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  console.log('Local queue vs remote acceptance, first authenticated status anchor, retained identity/timeout kernels and four authored fixtures source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
