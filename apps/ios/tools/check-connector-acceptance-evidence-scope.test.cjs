// Deliberately synthetic source mutations only; no Swift, broker or native fixtures run.
const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const {assertReviewedSource, validate} = require('./check-connector-acceptance-evidence-scope.cjs');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const app = 'apps/ios/GalaxySSI/';
const cases = [
  ['queue receipt cannot become remote acceptance', app + 'AgentIOSConnectorDispatch.swift',
    '"execution_generation": "1",', '"execution_generation": "1", "remote_task_status": "queued",'],
  ['queue receipt cannot claim a completed effect', app + 'AgentIOSConnectorDispatch.swift',
    '"completion_verified": "false"', '"completion_verified": "true"'],
  ['current native action identity remains required', app + 'AgentIOSConnectorDispatch.swift',
    'receipt.actionId == action.id', 'true'],
  ['acceptance clock cannot be refreshed by every progress event', app + 'AgentConnectorTaskStatusRecorder.swift',
    'if result.metadata["transport_accepted_at"] == nil {', 'if true {'],
  ['original source identity remains required', app + 'AgentConnectorTaskStatusRecorder.swift',
    'owner.sourceMessageId == managed.sourceMessageId', 'true'],
  ['execution generation remains required', app + 'AgentConnectorTaskStatusRecorder.swift',
    'observation.generation == managed.executionGeneration', 'true'],
  ['strictly advancing sequence remains required', app + 'AgentConnectorTaskStatusRecorder.swift',
    'observation.sequence > previousSequence', 'true'],
  ['observation time cannot move backwards', app + 'AgentConnectorTaskStatusRecorder.swift',
    'observation.lastResponseAt >= previousTime', 'true'],
  ['terminal metadata cannot be silently reactivated', app + 'AgentConnectorTaskStatusRecorder.swift',
    '!AgentRemoteOutcomePolicy.isTerminal(pending.metadata["remote_task_status"] ?? "")', 'true'],
  ['legacy probe ownership cannot become an unconditional grant', 'apps/ios/tools/check-desktop-probe-owner-scope.cjs',
    'guard usesLegacyMqtt else { continue }', 'guard true else { continue }'],
  ['journal capacity and readiness remain intact', 'apps/ios/tools/check-desktop-probe-owner-scope.cjs',
    'guard requests.count < 4, ready(record.binding) else { continue }', 'guard true else { continue }'],
  ['existing native fixture cannot be removed', 'apps/ios/GalaxySSITests/AgentControlPlaneActionExecutorTests.swift',
    'func testPreparedConnectorAcceptanceRequiresTheOriginalSourceAndContact()', 'func removedAcceptanceFixture()']
];

test('the actual reviewed/composed source still satisfies the complete acceptance contract', () => validate());
for (const [name, file, from, to] of cases) test(name, () => {
  const source = read(file);
  assert(source.includes(from), from);
  const changed = source.replace(from, to);
  assert.notEqual(changed, source);
  assert.throws(() => assertReviewedSource(file, changed), assert.AssertionError);
});
