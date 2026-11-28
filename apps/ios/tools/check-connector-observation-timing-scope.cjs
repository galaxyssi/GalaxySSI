const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '../../..');
const android = 'e7c6af6ef3eed21c7fb697b4458d1cf742833dc4';
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
const {snapshot, normalizePending} = require('./observation-scope-baseline.cjs');
const project = (file, source) => require('./check-routing-health-scope.cjs').retained(file,
  require('./check-routing-usage-scope.cjs').retained(file, normalizePending(file, source)));
const read = file => project(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const before = file => project(file, snapshot(file));
const expiryFile = 'apps/ios/GalaxySSI/AgentNativeConnectorObservationExpiry.swift';
function assertReviewedSource(file, source) {
  if (file === expiryFile) {
    // The separately owned #4687 helper moves this live call out of the coordinator.
    const approved = git('show', `d83f2c41d709f3f2a667871a1530021d00b50760:${file}`).replace(/\r\n/g, '\n');
    assert.equal(source, approved, 'Exact owned expiry helper retains the current timing projection');
    return;
  }
  assert.equal(project(file, source), before(file), file + ' outside reviewed timing scope');
}
const hook = '    observed.metadata.merge(AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: pending.metadata,\n' +
  '      nowMillis: AgentControlPlaneClock.nowMillis())) { _, latest in latest }\n';
function retained(file, source) {
  return file.endsWith('GalaxySSIServices.swift') ? source.replace(hook, '') : source;
}
function validate() {
if (fs.existsSync(path.join(root, expiryFile))) {
  const expiry = fs.readFileSync(path.join(root, expiryFile), 'utf8').replace(/\r\n/g, '\n');
  assertReviewedSource(expiryFile, expiry);
  assert(expiry.includes('AgentConnectorTimingPolicy.overdueObservationMetadata(metadata: pending.metadata,'));
}
const androidRouter = git('show', `${android}:apps/android/app/src/main/java/com/galaxyssi/chat/AgentResourceRouter.kt`);
for (const token of ['acceptedMs = 15_000L', 'runningMs = 45_000L', 'liveStaleMs = 60_000L',
  'acceptedMs = 60_000L', 'runningMs = 90_000L', 'liveStaleMs = 180_000L',
  'fun deadlineStartMillis(', 'metadata["transport_accepted_at"]?.toLongOrNull()',
  'metadata["remote_task_status_updated_at"]?.toLongOrNull()']) assert(androidRouter.includes(token), token);

const modelsFile = 'apps/ios/GalaxySSI/AgentAutomationModels.swift';
const models = read(modelsFile);
assert.equal(models, before(modelsFile), 'Complete reviewed timing model retained before inversion');
const start = models.indexOf('  static func deadlineStartMillis(');
const end = models.indexOf('  private static let interactive', start);
assert(start > 0 && end > start);
const policy = models.slice(start, end);
for (const token of ['case .notAccepted: return Int64(metadata["resource_started_at"]',
  'case .notRunning: return Int64(metadata["transport_accepted_at"]',
  'Int64(metadata["remote_task_status_updated_at"]',
  'guard metadata["awaiting_response"] == "true", nowMillis > 0',
  'guard status.isEmpty', 'guard metadata["routing_requires_live_data"] == "true"',
  '["", "accepted", "queued", "starting"].contains(status)',
  'guard started > 0, nowMillis >= started',
  'AgentRemoteTaskStatusPolicy.remainingDeadlineMillis(', 'subtractingReportingOverflow(started)',
  'guard !elapsed.overflow']) assert(policy.includes(token), token);
const emittedKeys = [...policy.matchAll(/"(native_connector_observation_[a-z_]+)":/g)].map(match => match[1]);
assert.deepEqual(emittedKeys, ['native_connector_observation_timeout_stage',
  'native_connector_observation_started_at', 'native_connector_observation_elapsed_ms',
  'native_connector_observation_deadline_ms']);
for (const forbidden of ['handleConnectorTimeout', 'AgentConnectorTimeoutResolver', 'publish(',
  'remaining_fallback_ids', 'non_retriable', 'Task {']) assert(!policy.includes(forbidden), forbidden);
assert(!/metadata\["awaiting_response"\]\s*=(?!=)/.test(policy));
const normalizedModels = (models.slice(0, start) + models.slice(end)).replace(
  'acceptedMs: 15_000,\n    runningMs: 45_000,\n    liveStaleMs: 60_000',
  'acceptedMs: 5_000,\n    runningMs: 8_000,\n    liveStaleMs: 15_000');
const reviewedModels = before(modelsFile);
const reviewedStart = reviewedModels.indexOf('  static func deadlineStartMillis(');
const reviewedEnd = reviewedModels.indexOf('  private static let interactive', reviewedStart);
assert(reviewedStart > 0 && reviewedEnd > reviewedStart);
assert.equal(normalizedModels, (reviewedModels.slice(0, reviewedStart) + reviewedModels.slice(reviewedEnd)).replace(
  'acceptedMs: 15_000,\n    runningMs: 45_000,\n    liveStaleMs: 60_000',
  'acceptedMs: 5_000,\n    runningMs: 8_000,\n    liveStaleMs: 15_000'), 'only timing policy may change');

const servicesFile = 'apps/ios/GalaxySSI/GalaxySSIServices.swift';
const services = require('./check-provider-resource-ranking-scope.cjs').retained(servicesFile, read(servicesFile));
assert.equal(services.split(hook).length, 2);
assert(services.includes('observed.metadata["native_connector_observation_overdue"] = "true"\n' + hook));
const reviewedServices = require('./check-provider-resource-ranking-scope.cjs').retained(servicesFile, before(servicesFile));
assert.equal(services, reviewedServices, 'Complete reviewed coordinator retained before hook inversion');
assert.equal(services.replace(hook, ''), reviewedServices.replace(hook, ''), 'ownership, probing and retirement paths remain unchanged');

const fixtureFile = 'apps/ios/GalaxySSITests/AgentConnectorTimeoutResolverTests.swift';
const fixtures = read(fixtureFile);
const fixtureStart = fixtures.indexOf('  func testObservationDeadlineUsesStageSpecificAnchors()');
const fixtureEnd = fixtures.indexOf('  func testResolverFailsAcceptedStatusOnNotRunningWhenFallbackExists()');
assert(fixtureStart > 0 && fixtureEnd > fixtureStart);
assert.equal(fixtures, before(fixtureFile), 'Complete reviewed timing fixture source retained');
assert.equal(fixtures.slice(0, fixtureStart) + fixtures.slice(fixtureEnd), before(fixtureFile).slice(0, fixtureStart) + before(fixtureFile).slice(fixtureEnd));
assert.equal((fixtures.slice(fixtureStart, fixtureEnd).match(/  func testObservation/g) || []).length, 6);
for (const token of ['15_999', '16_000', '94_999', '95_000', '149_999', '150_000',
  '60_999', '90_999', '180_999', '9223372036854775807', 'waiting_approval',
  'observed.keys.allSatisfy', 'XCTAssertNil(observed["timeout_stage"])']) assert(fixtures.includes(token), token);
const runTests = 'apps/ios/GalaxySSITests/AgentRunPolicyTests.swift';
const previousWindows = source => source.replace('regular.acceptedMs, 15_000', 'regular.acceptedMs, 5_000')
  .replace('regular.runningMs, 45_000', 'regular.runningMs, 8_000')
  .replace('regular.liveStaleMs, 60_000', 'regular.liveStaleMs, 15_000');
assert.equal(read(runTests), before(runTests), 'Complete reviewed timeout window fixtures retained');
assert.equal(previousWindows(read(runTests)), previousWindows(before(runTests)));
for (const file of ['AgentConnectorTimeoutResolver.swift', 'AgentConnectorTransportReceiptRecorder.swift',
  'AgentRemoteTaskStatusPolicy.swift', 'AgentControlPlaneActionExecutorModels.swift',
  'AgentConnectorResponseResolver.swift', 'AgentNetworkRoutingModels.swift']) {
  const target = `apps/ios/GalaxySSI/${file}`;
  assert.equal(require('./check-provider-resource-ranking-scope.cjs').retained(target, read(target)),
    require('./check-provider-resource-ranking-scope.cjs').retained(target, before(target)), file);
}
console.log('Connector observation timing source scope passed; no Swift fixtures or native runtime executed.');
}
if (require.main === module) validate();
module.exports = { retained, validate, assertReviewedSource };
