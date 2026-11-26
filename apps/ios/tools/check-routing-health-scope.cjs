// Source contracts, not Swift execution or native routing acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const base = '5f63d903558458025c872851369dbfd557c75cf1';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function once(source, from, to = '') { assert.equal(source.split(from).length, 2, from); return source.replace(from, to); }
function section(source, first, last) {
  const a = source.indexOf(first), b = source.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); return source.slice(a, b);
}
const ledgerHook = '    guard let current = values[scope],\n' +
  '          let observed = AgentProviderAvailabilityPolicy.observingReadiness(current,\n' +
  '            registration: registration, nowMillis: nowMillis) else { return }\n';
const ledgerBefore = '    guard var current = values[scope], current.circuitState(nowMillis: nowMillis) == .open,\n' +
  '          current.probeLeaseUntilMillis <= nowMillis,\n' +
  '          registration.lastHeartbeatMillis > current.lastFailureAtMillis,\n' +
  '          registration.lastHeartbeatMillis <= nowMillis || registration.lastHeartbeatMillis - nowMillis <= 60_000,\n' +
  '          current.lastFailureKind == .transportCrash || current.lastFailureKind == .unavailable ||\n' +
  '            (current.lastFailureKind == .execution && current.lastOperation == "start_run") else { return }\n';
const replayHook = '    let replayTargets = automaticRoutingTargets(goal: source.content)\n' +
  '    let alternatives = AgentCodexSilenceRecoveryPolicy.rankedAlternatives(\n' +
  '      targets: replayTargets, eligibleIds: eligibleIds, goal: source.content,\n' +
  '      hasPairedDesktop: store.serverLinks.contains { $0.paired },\n' +
  '      routingHealth: automaticRoutingHealth(targets: replayTargets))\n';
function retained(file, source) {
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('AgentRoutingHealthSnapshot.swift') && !line.includes('AgentRoutingHealthSnapshotTests.swift')).join('\n');
  if (file.endsWith('AgentProviderHealth.swift') && source.includes(ledgerHook)) {
    return once(once(source, ledgerHook, ledgerBefore), '    values[scope] = observed\n',
      '    current.circuitOpenUntilMillis = nowMillis\n    values[scope] = current\n');
  }
  if (file.endsWith('AgentProviderResourceRanking.swift') && source.includes('health: AgentRoutingResourceHealth? = nil')) {
    source = once(source, ',\n    health: AgentRoutingResourceHealth? = nil');
    source = once(source, '      let latencyPenalty = (health?.targetLatencyMillis ?? 0) > 0 ? 0 :\n' +
      '        penalty(performance.ewmaLatencyMs / (requirements.mode == .fast ? 40 : 120), maximum: 180)\n',
      '      let latencyPenalty = penalty(performance.ewmaLatencyMs / (requirements.mode == .fast ? 40 : 120), maximum: 180)\n');
    return once(source, section(source, '    if let reliability = AgentRoutingResourceHealth.reliability(health?.target)',
      '    if requirements.dataSensitivity == .confidential'));
  }
  if (file.endsWith('AgentQualityRouting.swift') && source.includes('routingHealth: AgentRoutingHealthSnapshot? = nil')) {
    source = once(source, ',\n    routingHealth: AgentRoutingHealthSnapshot? = nil');
    source = once(source, '      (routingHealth?.allows(targetId: $0.targetId) ?? true) &&\n' +
      '        AgentCapabilityRoutingPolicy.missingRequired', '      AgentCapabilityRoutingPolicy.missingRequired');
    return once(source, ', health: routingHealth?.resources[resource.targetId]');
  }
  if (file.endsWith('AgentNetworkRoutingModels.swift') && source.includes('routingHealth: AgentRoutingHealthSnapshot? = nil')) {
    source = once(source, ',\n    routingHealth: AgentRoutingHealthSnapshot? = nil');
    source = once(source, '      (routingHealth?.allows(targetId: $0.id) ?? true) &&\n');
    return source.replaceAll(', routingHealth: routingHealth', '');
  }
  if (file.endsWith('AgentRemoteTaskStatusPolicy.swift') && source.includes('routingHealth: AgentRoutingHealthSnapshot? = nil')) {
    source = once(source, '  static func rankedAlternatives(targets: [AgentCallableTarget], eligibleIds: Set<String>, goal: String,\n' +
      '                                 hasPairedDesktop: Bool = false,\n' +
      '                                 routingHealth: AgentRoutingHealthSnapshot? = nil) -> [String] {',
      '  static func rankedAlternatives(targets: [AgentCallableTarget], eligibleIds: Set<String>, goal: String) -> [String] {');
    return once(source, '    guard let selected = AgentConnectorRouteSelector.select(targets: current, decision: nil, goal: goal,\n' +
      '      hasPairedDesktop: hasPairedDesktop, routingHealth: routingHealth) else { return [] }',
      '    guard let selected = AgentConnectorRouteSelector.select(targets: current, decision: nil, goal: goal) else { return [] }');
  }
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  private let routingHealthLedger:')) {
    source = once(source, '  private let routingHealthLedger: AgentProviderHealthLedger\n');
    source = once(source, '      healthLedger: routingHealthLedger,\n');
    source = once(source, ',\n    routingHealthLedger: AgentProviderHealthLedger = UserDefaultsAgentProviderHealthLedger()');
    source = once(source, '    self.routingHealthLedger = routingHealthLedger\n');
    source = once(source, replayHook, '    let alternatives = AgentCodexSilenceRecoveryPolicy.rankedAlternatives(\n' +
      '      targets: automaticRoutingTargets(goal: source.content),\n      eligibleIds: eligibleIds, goal: source.content)\n');
    source = once(source, '    let routingHealth = automaticRoutingHealth(targets: targets)\n');
    source = once(source, '      .filter { routingHealth.allows(targetId: $0.id) }\n');
    source = once(source, section(source, '  private func automaticRoutingHealth(', '  private func automaticRouteSelection('));
    return source.replaceAll(',\n      routingHealth: automaticRoutingHealth(targets: targets)', '');
  }
  return source;
}
function validate() {
  const app = 'apps/ios/GalaxySSI/';
  for (const file of ['AgentProviderHealth.swift', 'AgentProviderResourceRanking.swift', 'AgentQualityRouting.swift',
    'AgentNetworkRoutingModels.swift', 'AgentRemoteTaskStatusPolicy.swift', 'GalaxySSIServices.swift']) {
    const target = app + file; assert.equal(retained(target, read(target)), old(target), file);
  }
  const snapshot = read(app + 'AgentRoutingHealthSnapshot.swift');
  for (const token of ['ledger.snapshots()', 'resources[registration.agentId] == nil',
    'records[registration.runtimeHealthScope()]', 'records[registration.targetHealthScopeId]',
    'registration.cloudProviderHealthScopeId', 'CloudProviderHealthRecoveryPolicy.shouldRecoverProviderCircuit(',
    '.halfOpen || $0.probeLeaseUntilMillis <= nowMillis', 'resources[targetId]?.selectable ?? true',
    'snapshot.successes > 0 || snapshot.failures > 0', 'Double(snapshot.successes) + Double(snapshot.failures)',
    'guard nowMillis > 0']) assert(snapshot.includes(token), token);
  for (const token of ['ledger.acquire(', 'recordSuccess(', 'recordFailure(', 'markAvailable(', '.save(',
    'URLSession', 'health:90', 'AgentProviderHealthSnapshot(scopeId:', 'canonicalPreferenceId']) assert(!snapshot.includes(token), token);
  for (const condition of ['current.circuitState(nowMillis: nowMillis) == .open', 'current.probeLeaseUntilMillis <= nowMillis',
    'registration.lastHeartbeatMillis > current.lastFailureAtMillis',
    'registration.lastHeartbeatMillis <= nowMillis || registration.lastHeartbeatMillis - nowMillis <= 60_000',
    'current.lastFailureKind == .transportCrash || current.lastFailureKind == .unavailable',
    '(current.lastFailureKind == .execution && current.lastOperation == "start_run")']) {
    assert(snapshot.includes(condition), condition); assert(ledgerBefore.includes(condition), condition);
  }
  const services = read(app + 'GalaxySSIServices.swift');
  assert.equal((services.match(/routingHealth: automaticRoutingHealth\(targets: targets\)/g) || []).length, 3);
  assert(services.includes(replayHook));
  const admission = section(services, '  private func automaticRoutingTargets(', '  private func automaticRouteSelection(');
  assert(admission.includes('.filter { routingHealth.allows(targetId: $0.id) }'));
  assert(admission.includes('ledger: routingHealthLedger, nowMillis: AgentControlPlaneClock.nowMillis()'));
  const selector = read(app + 'AgentNetworkRoutingModels.swift');
  assert(selector.indexOf('(routingHealth?.allows(targetId: $0.id) ?? true)') < selector.indexOf('if preserveHealthyPrimary'));
  assert.equal((selector.match(/routingHealth: routingHealth/g) || []).length, 2);
  const rank = read(app + 'AgentProviderResourceRanking.swift');
  for (const token of ['(health?.targetLatencyMillis ?? 0) > 0 ? 0', 'score += reliability', 'score += reliability / 2',
    'health?.domainLatencyMillis', 'latency / (requirements.mode == .fast ? 40 : 120)', 'latency / 180, 120']) assert(rank.includes(token), token);
  for (const file of ['AgentControlPlaneActionExecutorModels.swift', 'AgentConnectorTimeoutResolver.swift',
    'AgentConnectorResponseResolver.swift', 'AgentTaskBudgetModels.swift', 'AgentPlanRunModels.swift']) {
    const target = app + file; assert.equal(read(target), old(target), file);
  }
  const tests = read('apps/ios/GalaxySSITests/AgentRoutingHealthSnapshotTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  for (const token of ['XCTAssertEqual(ledger.snapshots(), before)', 'lastHeartbeatMillis = 64_000',
    'nowMillis: 33_000', 'Int.max', 'ranked.score - baseline.score, 190', 'another-desktop:hermes',
    'preserveHealthyPrimary: true, routingHealth: health']) assert(tests.includes(token), token);
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal((read(project).match(/AgentRoutingHealthSnapshot(?:Tests)?\.swift.*(?:Sources|PBXFileReference|\*\/)/g) || []).length, 8);
  assert.equal(retained(project, read(project)), old(project));
  console.log('Live adapter-health routing, read-only capture, preserved lease/ownership and replay source contracts passed; no native acceptance.');
}
if (require.main === module) validate();
module.exports = {retained, validate};
