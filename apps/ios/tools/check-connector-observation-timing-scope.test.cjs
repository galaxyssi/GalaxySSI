// Synthetic source mutations only; no Swift clocks, recovery, timers or fixtures execute.
const assert = require('node:assert/strict'), test = require('node:test'), fs = require('node:fs'), path = require('node:path');
const {validate, assertReviewedSource} = require('./check-connector-observation-timing-scope.cjs');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const models = app + 'AgentAutomationModels.swift', timing = 'enum AgentConnectorTimingPolicy {';
const expiry = app + 'AgentNativeConnectorObservationExpiry.swift', hasExpiry = fs.existsSync(path.join(root, expiry));
const mutations = [
  ['unaccepted dispatch anchor', models, timing,
    'case .notAccepted: return Int64(metadata["resource_started_at"]', 'case .notAccepted: return Int64(metadata["transport_accepted_at"]'],
  ['running acceptance anchor', models, timing,
    'case .notRunning: return Int64(metadata["transport_accepted_at"]', 'case .notRunning: return Int64(metadata["resource_started_at"]'],
  ['last remote progress anchor', models, timing,
    'Int64(metadata["remote_task_status_updated_at"]', 'Int64(metadata["resource_started_at"]'],
  ['backward and future clock gate', models, timing, 'nowMillis >= started', 'true'],
  ['elapsed clock overflow gate', models, timing, 'guard !elapsed.overflow', 'guard true'],
  ['pending original reply gate', models, timing, 'metadata["awaiting_response"] == "true"', 'true'],
  ['unaccepted status restriction', models, timing, 'guard status.isEmpty', 'guard true'],
  ['live-only running restriction', models, timing, 'metadata["routing_requires_live_data"] == "true"', 'true'],
  ['interactive acceptance window', models, timing, 'acceptedMs: 15_000', 'acceptedMs: 5_000'],
  ['interactive running window', models, timing, 'runningMs: 45_000', 'runningMs: 8_000'],
  ['interactive live-data window', models, timing, 'liveStaleMs: 60_000', 'liveStaleMs: 15_000'],
  ['attachment running window', models, timing, 'runningMs: 90_000', 'runningMs: 30_000'],
  ['informational stage key', models, timing,
    '"native_connector_observation_timeout_stage": stage.rawValue', '"timeout_stage": stage.rawValue'],
  ['no synthetic failure output', models, timing,
    'return [\n      "native_connector_observation_timeout_stage"', 'return ["error_code": "timed_out",\n      "native_connector_observation_timeout_stage"'],
  ['owned expiry projection hook', hasExpiry ? expiry : app + 'GalaxySSIServices.swift', hasExpiry ? '' : '  private func preserveNativeConnectorObservation(',
    'AgentConnectorTimingPolicy.overdueObservationMetadata', 'AgentConnectorTimingPolicy.deadlineStartMillis'],
  ['stage boundary fixtures retained', 'apps/ios/GalaxySSITests/AgentConnectorTimeoutResolverTests.swift', '',
    'func testObservationDeadlineUsesStageSpecificAnchors()', 'func removedStageAnchorFixture()'],
  ['separate timeout resolver retained', app + 'AgentConnectorTimeoutResolver.swift', '',
    'metadata["awaiting_response"] = "false"', 'metadata["awaiting_response"] = "true"']
];
test('actual reviewed/composed timing source satisfies the complete reference contract', () => validate());
for (const [name, file, anchor, from, to] of mutations) test('reject changed ' + name, () => {
  const source = read(file), start = anchor ? source.indexOf(anchor) : 0;
  assert(start >= 0, anchor);
  const at = source.indexOf(from, start); assert(at >= start, from);
  const changed = source.slice(0, at) + to + source.slice(at + from.length);
  assert.throws(() => assertReviewedSource(file, changed), assert.AssertionError);
});
