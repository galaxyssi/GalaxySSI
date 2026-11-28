// Synthetic source contracts only; no Swift, completion consumption, Signal or storage runs.
const assert = require('node:assert/strict'), test = require('node:test'), fs = require('node:fs'), path = require('node:path');
const {validate, assertReviewedSource} = require('./check-native-delivery-acceptance-scope.cjs');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const service = app + 'GalaxySSIServices.swift', commit = '  private func recordNativeConnectorTransportAccepted(';
const recorder = app + 'AgentConnectorTransportReceiptRecorder.swift', policy = 'enum AgentNativeConnectorTransportAcceptance';
const mutations = [
  ['protected data gate', service, commit, 'UIApplication.shared.isProtectedDataAvailable', 'true'],
  ['authenticated event identity', service, commit, 'event.identity == (try MqttBusinessIdentity(target.peer.binding))', 'true'],
  ['current route identity', service, commit, 'target.routeId == identity.clientRouteId', 'true'],
  ['root cancellation', service, commit, '!PhoneExecutionAuthority.isCancelled', 'PhoneExecutionAuthority.isCancelled'],
  ['private session gate', service, commit, '!session.privateMode', 'true'],
  ['unique pending action', service, commit, 'matches.count == 1', 'matches.count >= 1'],
  ['durable write before success', service, commit,
    'guard store.commitOwnedAgentTaskState(expected: task, updated: saved)', 'guard true'],
  ['managed run owner', recorder, policy, 'managed.ownerRunId == dispatch.owner', 'true'],
  ['original source owner', recorder, policy, 'managed.sourceMessageId == dispatch.sourceMessageId', 'true'],
  ['execution generation', recorder, policy, 'managed.executionGeneration == Int64', 'managed.executionGeneration != Int64'],
  ['expected receipt topic', recorder, policy, 'event.topic == expectedTopic', 'true'],
  ['original journal message identity', recorder, policy, 'event.messageID == messageID', 'true'],
  ['unconsumed completion gate', recorder, policy, 'event.isPending', 'true'],
  ['attachment completion exclusion', recorder, policy, 'event.attachmentTransferID.isEmpty', 'true'],
  ['acceptance replay clock', recorder, policy, 'guard pending.metadata["transport_accepted_at"] == nil', 'guard true'],
  ['application write before completion consumption', app + 'MqttBusinessReceipts.swift', '',
    'try await apply(current)', '_ = current'],
  ['replay fixture retained', 'apps/ios/GalaxySSITests/AgentConnectorTransportReceiptRecorderTests.swift', '',
    'func testNativeJournalDeliveryReplayDoesNotRefreshAcceptance()', 'func removedReplayClockFixture()'],
  ['numeric completion requires a registered writer', app + 'MqttDesktopConnectorProjection.swift', '',
    'let recordManagedTransportAccepted else { throw MqttDeliveryDispatch.Failure.unavailable }',
    'let recordManagedTransportAccepted else { return }'],
  ['parent compatibility export retained', 'apps/ios/tools/check-connector-acceptance-evidence-scope.cjs', '\nfunction retained(file, source) {',
    "if (file.endsWith('AgentConnectorTaskStatusRecorder.swift'))", 'if (false)']
];
test('actual reviewed/composed source satisfies the complete native delivery contract', () => validate());
for (const [name, file, anchor, from, to] of mutations) test('reject changed ' + name, () => {
  const source = read(file), start = anchor ? source.indexOf(anchor) : 0;
  assert(start >= 0, anchor);
  const at = source.indexOf(from, start); assert(at >= start, from);
  const changed = source.slice(0, at) + to + source.slice(at + from.length);
  assert.throws(() => assertReviewedSource(file, changed), assert.AssertionError);
});
