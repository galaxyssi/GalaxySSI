// Synthetic source contracts only; timers, Swift, storage, effects and networks never run.
const assert = require('node:assert/strict'), test = require('node:test'), fs = require('node:fs'), path = require('node:path');
const {assertReviewedSource, validate} = require('./check-active-native-observation-scope.cjs');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const service = app + 'GalaxySSIServices.swift', policy = app + 'AgentAutomationModels.swift';
const context = '  private func nativeConnectorObservationContext(', wake = 'enum AgentNativeConnectorObservationWakePolicy {';
const mutations = [
  ['protected data gate', service, context, 'UIApplication.shared.isProtectedDataAvailable', 'true'],
  ['foreground gate', service, context, 'UIApplication.shared.applicationState == .active', 'true'],
  ['execution pause gate', service, context, '!store.agentSafetySettings.executionPaused', 'true'],
  ['plan-only exclusion', service, context, 'store.agentSafetySettings.taskExecutionMode != .planOnly', 'true'],
  ['root cancellation', service, context, '!PhoneExecutionAuthority.isCancelled(taskId: dispatch.turnId)', 'true'],
  ['current waiting phase', service, context, 'current.task.phase == .waitingResponse', 'true'],
  ['saved permission identity', service, context,
    'current.waiting.parameters[AgentIOSConnectorDispatch.permissionKey] == store.agentSafetySettings.permissionMode.rawValue', 'true'],
  ['pending source identity', service, context, 'record.sourceMessageId == dispatch.sourceMessageId', 'true'],
  ['execution generation', service, context, 'record.executionGeneration == Int64', 'record.executionGeneration != Int64'],
  ['wake job bound', service, context, 'nativeConnectorObservationJobs.count < 200', 'true'],
  ['stale callback token', service, context, 'self.nativeConnectorObservationJobs[key]?.token == token', 'true'],
  ['original registered task', service, context, 'identity.taskId == dispatch.taskId', 'true'],
  ['managed binding retained', service, context, 'currentManagedDesktopReply(binding) != nil', 'true'],
  ['future clock exclusion', policy, wake, 'nowMillis >= start', 'true'],
  ['bounded probe throttle', policy, wake, 'delayMillis: max(remaining, throttle)', 'delayMillis: 0'],
  ['live-only running observation', policy, wake, 'clock["routing_requires_live_data"] == "true"', 'true'],
  ['original clock fixture retained', 'apps/ios/GalaxySSITests/AgentConnectorTimeoutResolverTests.swift', '',
    'func testActiveObservationWakeUsesUnacceptedAndAcceptedStageClocks()', 'func removedStageClockFixture()']
];
test('actual reviewed/composed source satisfies the complete active observation contract', () => validate());
for (const [name, file, anchor, from, to] of mutations) test('reject changed ' + name, () => {
  const source = read(file), start = anchor ? source.indexOf(anchor) : 0;
  assert(start >= 0, anchor);
  const at = source.indexOf(from, start); assert(at >= start, from);
  const changed = source.slice(0, at) + to + source.slice(at + from.length);
  assert.throws(() => assertReviewedSource(file, changed), assert.AssertionError);
});
test('a second delivery compatibility export cannot shadow the owned declaration', () => {
  const file = 'apps/ios/tools/check-native-delivery-acceptance-scope.cjs';
  assert.throws(() => assertReviewedSource(file, read(file) + '\nfunction retained(file, source) { return source; }\n'), assert.AssertionError);
});
