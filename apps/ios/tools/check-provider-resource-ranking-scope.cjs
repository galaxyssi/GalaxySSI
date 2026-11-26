// Source contracts only. Does not execute Swift or prove routed delivery.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const base = 'cb3f7c6aadf6884b7fd9fb76d8bdf0a151f507cb';
const android = 'e7c6af6ef3eed21c7fb697b4458d1cf742833dc4';
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
const clean = source => source.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(git('show', `${base}:${file}`));
function once(source, from, to) {
  assert.equal(source.split(from).length, 2, from);
  return source.replace(from, to);
}
const probe = '    let environment = environment ?? {\n' +
  '      let probe = AgentMediaNetworkDetector.shared.currentProbe\n' +
  '      return AgentRuntimeEnvironment(networkAvailable: probe.networkPresent && probe.internetCapable,\n' +
  '        networkValidated: probe.validated, networkMetered: probe.metered)\n' +
  '    }()\n';
const projection = '      AgentProviderResourceRanking.candidate(resource: resource, requirements: requirements, environment: environment)\n';
function retained(file, source) {
  if (!file.endsWith('AgentQualityRouting.swift') || !source.includes(projection)) return source;
  source = once(source, '    requirements: AgentTaskRequirements? = nil,\n    environment: AgentRuntimeEnvironment? = nil',
    '    requirements: AgentTaskRequirements? = nil');
  source = once(source, probe, '');
  source = once(source, projection, '      AgentResourceCandidate(\n' +
    '        resource: resource,\n' +
    '        score: AgentCapabilityRoutingPolicy.fitScore(requirements, available: resource.capabilities),\n' +
    '        reasons: ["available_reasoning_resource"] +\n' +
    '          AgentCapabilityRoutingPolicy.evidence(requirements, available: resource.capabilities)\n' +
    '      )\n');
  return once(source, '      environment: environment,\n      catalog: catalog', '      catalog: catalog');
}
function section(source, start, end) {
  const first = source.indexOf(start), last = source.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, start);
  return source.slice(first, last);
}
function validate() {
  const qualityFile = 'apps/ios/GalaxySSI/AgentQualityRouting.swift';
  const quality = read(qualityFile);
  assert(quality.includes(projection));
  assert.equal(retained(qualityFile, quality), old(qualityFile));
  const policyFile = 'apps/ios/GalaxySSI/AgentProviderResourceRanking.swift';
  const policy = read(policyFile);
  const reference = git('show', `${android}:apps/android/app/src/main/java/com/galaxyssi/chat/AgentResourceRouter.kt`);
  for (const token of ['55 else 22', '75 else 25', '80 else 20', 'PHONE_SYSTEM -> 220', 'CLOUD_CONFIGURED -> -160',
    'score += 140 else score -= 120', 'score -= 300', 'failureRate * 220.0', 'coerceAtMost(180)',
    'score -= 70', 'score -= 180', 'score += 160']) assert(reference.includes(token), token);
  for (const token of ['AgentCapabilityRoutingPolicy.fitScore(', '? 55 : 22', '? 75 : 25', '? 80 : 20',
    'performance.attempts > 0', 'penalty(performance.failureRate * 220, maximum: 220)',
    'maximum: 180', 'case .phoneSystem: score += 220', 'case .cloudConfigured: score -= 160',
    'resource.supportsBackground ? 140 : -120', 'resource.contextWindowTokens > 0',
    'environment.networkMetered, resource.location == .cloud', 'score -= 70', 'score -= 180',
    'min(requirements.estimatedInputTokens / 100, 120)', 'requirements.mode == .quality, resource.quality == .frontier',
    'guard !value.isNaN, value > 0', 'value >= Double(maximum) ? maximum : Int(value)']) assert(policy.includes(token), token);
  for (const token of ['UserDefaults', 'Task {', 'publish(', 'acquire(', 'circuitOpen', 'health:90',
    'averageTotalTokens', 'remaining_fallback_ids', 'authorized']) assert(!policy.includes(token), token);
  for (const file of ['AgentNetworkRoutingModels.swift', 'AgentTaskBudgetModels.swift',
    'AgentConnectorTimeoutResolver.swift', 'AgentControlPlaneActionExecutorModels.swift',
    'AgentProviderProfileCatalog.swift', 'AgentSelfModel.swift']) {
    const target = 'apps/ios/GalaxySSI/' + file;
    assert.equal(read(target), old(target), file);
  }
  const servicesFile = 'apps/ios/GalaxySSI/GalaxySSIServices.swift';
  const first = '  private func automaticRoutingTargets(', last = '  private func selectedLocalModel(';
  assert.equal(section(read(servicesFile), first, last), section(old(servicesFile), first, last));
  const selector = section(read('apps/ios/GalaxySSI/AgentNetworkRoutingModels.swift'),
    'enum AgentConnectorRouteSelector {', 'enum AgentResourceCatalog {');
  assert(selector.includes('preserveHealthyPrimary, decision == nil'));
  assert(selector.indexOf('targets: [preferredTarget]') < selector.indexOf('var routingDecision = decision'));
  assert(selector.includes('routingDecision = AgentQualityRoutingService.baselineDecision('));
  assert(selector.includes('let leftScore = lhs.score + leftAdjustment'));
  const fixtureFile = 'apps/ios/GalaxySSITests/AgentRoutingCapabilityTests.swift';
  const fixtures = read(fixtureFile);
  const additions = section(fixtures, '  func testProviderRankingAppliesAndroidQualityLatencyAndEconomyWeights()',
    '  func testGlobalCapabilityObservationExtractorAuthorizationAndSafetyUseLocalOnlyProjection()');
  assert.equal((additions.match(/  func testProviderRanking/g) || []).length, 6);
  for (const token of ['.nan', '.infinity', '519', '800', '475', '589', '319', '639', '279', '380', '260',
    'score - metered.score, 70', 'score - unvalidated.score, 180', 'capabilitySource: .declared',
    'AgentConnectorRouteSelector.select(', 'preserveHealthyPrimary: true']) assert(additions.includes(token), token);
  assert.equal(once(fixtures, additions, ''), old(fixtureFile));
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const project = read(projectFile);
  const lines = project.split('\n').filter(line => line.includes('AgentProviderResourceRanking.swift'));
  assert.equal(lines.length, 4);
  assert.equal(project.split('\n').filter(line => !line.includes('AgentProviderResourceRanking.swift')).join('\n'), old(projectFile));
  console.log('Provider resource attribute ranking and retained routing source contracts passed; no native acceptance.');
}
if (require.main === module) validate();
module.exports = { retained, validate };
