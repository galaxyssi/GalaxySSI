// Source contracts only, not native routing, provider calls or privacy acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = 'f1b21803638c354cd6056883cf2c8cb88ee76f08';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'), cache = new Map();
function old(file) {
  if (!cache.has(file)) cache.set(file, cp.execFileSync('git', ['show', `${base}:${file}`],
    {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  return cache.get(file);
}
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
const initialOld = `    return AgentConnectorRouteSelector.select(targets: targets, decision: nil,
      preferredTargetId: preferredTargetId, goal: goal, preserveHealthyPrimary: true,
      hasPairedDesktop: store.serverLinks.contains { $0.paired },
      routingHealth: automaticRoutingHealth(targets: targets), routingUsage: automaticRoutingUsage())`;
const initialNew = `    return scoredAutomaticConnectorRoute(goal: goal, preferredTargetId: preferredTargetId,
      preserveHealthyPrimary: true).selection`;
const refreshOld = `    let targets = automaticRoutingTargets(goal: goal)
    let selection = AgentConnectorRouteSelector.select(targets: targets, decision: nil,
      preferredTargetId: action.parameters["connector_id"] ?? "", goal: goal, preserveHealthyPrimary: true,
      hasPairedDesktop: store.serverLinks.contains { $0.paired },
      routingHealth: automaticRoutingHealth(targets: targets), routingUsage: automaticRoutingUsage())`;
const refreshNew = `    let selection = scoredAutomaticConnectorRoute(goal: goal, preferredTargetId: action.parameters["connector_id"] ?? "",
      preserveHealthyPrimary: true).selection`;
const fallbackOld = `    let targets = automaticRoutingTargets(goal: goal)
    let currentRoute = AgentConnectorRouteSelector.select(
      targets: targets,
      decision: nil,
      goal: goal,
      hasPairedDesktop: store.serverLinks.contains { $0.paired },
      routingHealth: automaticRoutingHealth(targets: targets), routingUsage: automaticRoutingUsage()
    )`;
const fallbackNew = `    let current = scoredAutomaticConnectorRoute(goal: goal)
    let targets = current.targets
    let currentRoute = current.selection`;
function retained(file, source) {
  if (file.endsWith('check-verified-timer-start-scope.cjs')) return source
    .replace("const read = file => require('./check-scored-route-context-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')), cache = new Map();",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'), cache = new Map();")
    .replace("  source = require('./check-scored-route-context-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(line =>
    !['AgentAutomaticRoutingContext.swift', 'AgentAutomaticRoutingContextTests.swift'].some(name => line.includes(name))).join('\n');
  if (file.endsWith('AgentNetworkRoutingModels.swift') && source.includes('decision?.primary?.reasons.contains("stable_auto_primary")'))
    return source.replace(section(source, '    if preserveHealthyPrimary, let preferredTarget,', '    var routingDecision = decision'),
      section(old(file), '    if preserveHealthyPrimary, decision == nil,', '    var routingDecision = decision'));
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  private func scoredAutomaticConnectorRoute(')) {
    source = source.replace(section(source, '  private func scoredAutomaticConnectorRoute(', '  private func automaticRouteSelection('), '');
    for (const [start, end, transform] of [
      ['  private func automaticRouteSelection(', '  private func selectedLocalModel(', value => value
        .replace('    let targets = automaticRoutingTargets(goal: goal)\n', '').replace(initialOld, initialNew)],
      ['  private func refreshAutomaticConnectorAction(', '  private func scopedLocalNativeExecutionAction(', value => value.replace(refreshOld, refreshNew)],
      ['  private func connectorFallbackAction(', '  private func markLocalNativeActionBlocked(', value => value.replace(fallbackOld, fallbackNew)]]) {
      const original = section(old(file), start, end), expected = transform(original);
      assert.notEqual(expected, original, start);
      assert.equal(section(source, start, end), expected, start);
      source = source.replace(expected, original);
    }
  }
  return source;
}
function validate() {
  for (const file of [app + 'GalaxySSIServices.swift', app + 'AgentNetworkRoutingModels.swift',
    'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', 'apps/ios/tools/check-verified-timer-start-scope.cjs'])
    assert.equal(retained(file, read(file)), old(file), file);
  const model = read(app + 'AgentAutomaticRoutingContext.swift');
  for (const token of ['AgentAutomaticRouteAdmission.targets(', 'connectorCallsAllowed: connectorCallsAllowed',
    'health?.allows(targetId: target.id)', 'AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)',
    'environment: environment, catalog: catalog, taskBudget: budget', 'scored([preferred], primary: preferred.id)',
    'stable_auto_primary', 'scored(permitted, primary: "")', 'primary: selected',
    '$0.agentId == target.id', 'resource.location = registration.location', 'resource.trust = registration.trust',
    'AgentProviderResourceRanking.candidate(']) assert(model.includes(token), token);
  for (const token of ['UserDefaults', 'URLSession', '.observe(', '.adjustedDecision(', '.prefix(6)', 'reserve(', 'register(']) assert(!model.includes(token), token);
  const service = read(app + 'GalaxySSIServices.swift');
  const capture = section(service, '  private func scoredAutomaticConnectorRoute(', '  private func automaticRouteSelection(');
  for (const token of ['callableAgentRegistrations(targets: targets)', 'automaticRoutingHealth(targets: targets)',
    'automaticRoutingUsage()', 'budget: store.agentTaskBudget', 'probe.validated',
    'store.agentSafetySettings.connectorCallsAllowed', 'decision: context.decision']) assert(capture.includes(token), token);
  assert(!capture.includes('decision: nil'));
  const selector = read(app + 'AgentNetworkRoutingModels.swift');
  const fast = section(selector, '    if preserveHealthyPrimary, let preferredTarget,', '    var routingDecision = decision');
  for (const token of ['decision?.primary?.resource.targetId == preferredTarget.id', '"stable_auto_primary"', 'decision?.fallbacks.isEmpty == true',
    'let primaryDecision = decision ??']) assert(fast.includes(token), token);
  for (const name of ['AgentTaskBudgetModels', 'AgentProviderResourceRanking', 'AgentQualityRouting', 'AgentRoutingHealthSnapshot',
    'AgentRoutingUsageStore', 'GalaxySSIStoreSessions', 'AgentDataDisclosureLedger', 'AgentModelPlanParser', 'MqttBusinessTransportRuntime'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const pins = [
    ['e7c6af6ef3eed21c7fb697b4458d1cf742833dc4', 'AgentResourceRouter.kt', 'd95d5d072eb0637ee20e0a883559918979bf0be48daf4dfb9021fbbcfb37663f'],
    [base, 'AgentTaskBudget.kt', '5023ca131e6bdbbda490436a33af22014769ddb3cefe0ed15655cde441d81766']];
  for (const [revision, name, sha] of pins) assert.equal(crypto.createHash('sha256').update(cp.execFileSync('git',
    ['show', `${revision}:apps/android/app/src/main/java/com/galaxyssi/chat/${name}`], {cwd: root})).digest('hex'), sha);
  assert.equal((read('apps/ios/GalaxySSITests/AgentAutomaticRoutingContextTests.swift').match(/  func test/g) || []).length, 8);
  for (const name of ['AgentAutomaticRoutingContext.swift', 'AgentAutomaticRoutingContextTests.swift'])
    assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n').filter(line => line.includes(name)).length, 4);
  console.log('Live scored route context, stable admitted primary, complete pre-calibration candidates and retained policy/transport source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
