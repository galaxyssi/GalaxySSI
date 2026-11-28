// Synthetic source mutations only; no Swift, task store, signal or native fixtures execute.
const assert = require('node:assert/strict'), test = require('node:test'), fs = require('node:fs'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const {validate, assertReviewedSource} = require('./check-native-status-observation-scope.cjs');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const service = app + 'GalaxySSIServices.swift', recorder = app + 'AgentConnectorTaskStatusRecorder.swift';
const mutations = [
  ['profile owner', service, 'desktopReplyRecoveryOwner == store.profile.identityFingerprint', 'true'],
  ['durably accepted observation', service, 'desktopReplyRecovery.record(for: observation.binding) == observation', 'true'],
  ['task conversation owner', service, 'task.sessionId == record.conversationId', 'true'],
  ['private session gate', service, '!session.privateMode', 'true'],
  ['tracking pause gate', service, '!session.trackingPaused', 'true'],
  ['exact current action', service, 'task.lastNativeActionResult?.actionId == pending.actionId', 'true'],
  ['checked task commit', service, 'store.commitOwnedAgentTaskState(expected: task, updated: updated)', 'true'],
  ['reply source owner', recorder, 'owner.sourceMessageId == managed.sourceMessageId', 'true'],
  ['current generation', recorder, 'observation.generation == managed.executionGeneration', 'true'],
  ['strict status sequence', recorder, 'observation.sequence > previousSequence', 'true'],
  ['nondecreasing observation clock', recorder, 'observation.lastResponseAt >= previousTime', 'true'],
  ['preserve pending effect status', recorder, 'return result\n', 'result.metadata["awaiting_response"] = "false"\n    return result\n'],
  ['original fixture retained', 'apps/ios/GalaxySSITests/AgentNativeConnectorStatusObservationTests.swift',
    'func testObservedStatusRoundTripsInTheOriginalWaitingReceipt()', 'func removedOriginalWaitFixture()'],
  ['owned Xcode registrations retained', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj',
    'AgentNativeConnectorStatusObservationTests.swift in Sources', 'RemovedObservationFixture.swift in Sources'],
  ['localized observation message retained', app + 'zh-Hans.lproj/Localizable.strings',
    '"galaxyssi.agent.connector.waiting_original_result"', '"removed.observation.message"']
];
test('current reviewed/composed source satisfies the full observation contract', () => validate());
for (const [name, file, from, to] of mutations) test('reject changed ' + name, () => {
  const source = read(file), start = file === service ? source.indexOf('  private func recordNativeConnectorObservation(') : 0;
  assert(start >= 0);
  const at = source.indexOf(from, start); assert(at >= start, from);
  const changed = source.slice(0, at) + to + source.slice(at + from.length);
  assert.throws(() => assertReviewedSource(file, changed), assert.AssertionError);
});
test('unrelated resource and project additions do not erase or change owned entries', () => {
  for (const [file, suffix] of [['apps/ios/GalaxySSI.xcodeproj/project.pbxproj', '\n// Another reviewed tool registration\n'],
    [app + 'zh-Hans.lproj/Localizable.strings', '\n"other.synthetic.feature" = "Fixture";\n']]) {
    assertReviewedSource(file, read(file) + suffix);
  }
});
