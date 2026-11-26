// Source contracts only, not native execution or quality acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), base = '387929097036560b483482e3590451190e7640db';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const git = (...args) => cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024});
const old = file => git('show', `${base}:${file}`).replace(/\r\n/g, '\n');
function section(source, first, last, offset = 0) {
  const a = source.indexOf(first, offset), b = source.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); return source.slice(a, b);
}
function once(source, from, to = '') { assert.equal(source.split(from).length, 2, from); return source.replace(from, to); }
function select(source) {
  return section(source, '  static func select(', '  private static func hasReasoningCapability(',
    source.indexOf('enum AgentConnectorRouteSelector {'));
}
function retained(file, source) {
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('AgentPreShadowRoutingTests.swift')).join('\n');
  if (file.endsWith('AgentNetworkRoutingModels.swift') && source.includes('AgentProviderResourceRanking.prepareForQuality(')) {
    return once(source, select(source), select(old(file)));
  }
  if (file.endsWith('AgentProviderResourceRanking.swift') && source.includes('  static func prepareForQuality(')) {
    return once(source, section(source, '  static func prepareForQuality(', '  // Persisted provider telemetry'));
  }
  if (file.endsWith('AgentQualityRouting.swift') && source.includes('(Double(candidate.score) + 1_000)')) {
    return once(source, '(Double(candidate.score) + 1_000)', 'Double(candidate.score + 1_000)');
  }
  return source;
}
function validate() {
  const app = 'apps/ios/GalaxySSI/';
  for (const name of ['AgentNetworkRoutingModels.swift', 'AgentProviderResourceRanking.swift', 'AgentQualityRouting.swift']) {
    const file = app + name; assert.equal(retained(file, read(file)), old(file), name);
  }
  const file = app + 'AgentNetworkRoutingModels.swift';
  const current = select(read(file)), prior = select(old(file));
  assert.equal(current.slice(0, current.indexOf('    var routingDecision = decision')),
    prior.slice(0, prior.indexOf('    var routingDecision = decision')), 'same eligibility/health/capability and healthy-primary fast path');
  assert(current.indexOf('prepareForQuality(') < current.indexOf('adjustedDecision('));
  assert.equal((current.match(/UserDefaultsAgentSelfModelStore.shared.snapshot\(\)/g) || []).length, 1);
  assert(current.includes('AgentSelfModelReducer.calibration(model: selfModel'));
  assert(current.includes('eligibleTargetIds: Set(eligibleById.keys)'));
  assert(current.includes('guard prepared.primary != nil else { return nil }'));
  assert(current.includes('let calibratedCandidates = routedCandidates'));
  assert(!current.includes('.sorted') && !current.includes('calibrationAdjustment('));
  assert(!current.includes('routingDecision.catalog.first') && !current.includes('score: 0'));
  assert(current.includes('guard var selectedCandidate = calibratedCandidates.first(where:'));
  assert(current.includes('selectedTarget.status == .disconnected'));
  assert(current.includes('selectedCandidate.reasons.append("recoverable_connector_status")'));
  assert(current.includes('connectorDecision.fallbacks = Array(calibratedCandidates.filter'));
  assert(current.includes('.prefix(6)'));
  const policy = section(read(app + 'AgentProviderResourceRanking.swift'),
    '  static func prepareForQuality(', '  // Persisted provider telemetry');
  for (const token of ['eligibleTargetIds.contains($0.resource.targetId)', 'seen.insert($0.resource.targetId).inserted',
    'let adjustment = calibration(candidate.resource.targetId)', 'addingReportingOverflow(adjustment)',
    'adjustment < 0 ? Int.min : Int.max', 'left.index < right.index', 'preferredTargetId',
    'var prepared = decision', 'fallbackCandidates(primary: $0.resource, candidates: ranked)']) assert(policy.includes(token), token);
  for (const token of ['.catalog', 'UserDefaults', 'Task {', 'URLSession', 'acquire(', 'recordSuccess(']) assert(!policy.includes(token), token);
  const android = git('show', 'e7c6af6ef3eed21c7fb697b4458d1cf742833dc4:apps/android/app/src/main/java/com/galaxyssi/chat/AgentResourceRouter.kt');
  assert(android.indexOf('val selfModel = selfModelStore.snapshot()') < android.indexOf('val fallbackLimit = 6'));
  assert(android.indexOf('val fallbackLimit = 6') < android.indexOf('AgentQualityRoutingService.observe(appContext, goal, decision)'));
  assert(android.includes('.take(fallbackLimit)'));
  for (const name of ['GalaxySSIServices.swift', 'AgentProviderHealth.swift', 'AgentTaskBudgetModels.swift',
    'AgentConnectorTimeoutResolver.swift', 'AgentControlPlaneActionExecutorModels.swift', 'AgentRemoteTaskStatusPolicy.swift',
    'AgentSelfModel.swift']) {
    const target = app + name; assert.equal(read(target), old(target), name);
  }
  const checker = 'tools/dev/check-ios-project.js';
  assert.equal(once(read(checker), '  [models, "AgentProviderResourceRanking.prepareForQuality"],',
    '  [models, "eligible_reasoning_fallback"],'), old(checker));
  const tests = read('apps/ios/GalaxySSITests/AgentPreShadowRoutingTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 9);
  for (const token of ['XCTAssertEqual(seen, candidates.map', 'recommendedResourceId: "shared-6"',
    'XCTAssertEqual(safe.primary?.score, Int.max)', 'XCTAssertEqual(safe.fallbacks.first?.score, Int.min)',
    'shadow.scores.map(\\.score), [1, 0]', 'preferredTargetId: "node-9"', 'recoverable_connector_status']) assert(tests.includes(token), token);
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal(read(project).split('\n').filter(line => line.includes('AgentPreShadowRoutingTests.swift')).length, 4);
  assert.equal(retained(project, read(project)), old(project));
  console.log('Pre-shadow calibration, bounded domain candidate exposure and post-promotion order source contracts passed; no native acceptance.');
}
if (require.main === module) validate();
module.exports = {retained, validate};
