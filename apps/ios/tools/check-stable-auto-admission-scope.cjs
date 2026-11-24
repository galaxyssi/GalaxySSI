const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '../../..');
const base = 'ddcb2a69acd02ea12d20fb469e779d4d87b85a4f';
const android = 'e7c6af6ef3eed21c7fb697b4458d1cf742833dc4';
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const native = 'apps/ios/GalaxySSI/AgentNetworkRoutingModels.swift';
const source = read(native);
const insertion = '    let admittedTargetIds = decision.map { Set($0.orderedTargetIds) }\n';
const predicate = '      (admittedTargetIds?.contains($0.id) ?? true) &&\n';
assert.equal(source.split(insertion).length, 2);
assert.equal(source.split(predicate).length, 2);
assert(source.indexOf(insertion) < source.indexOf('let reasoningTargets = targets.filter'));
assert(source.indexOf(predicate) < source.indexOf('var eligible = reasoningTargets.filter'));
const shortCircuit = `    if preserveHealthyPrimary, decision == nil,
       let preferredTarget, preferredTarget.status == .available {
      let primaryDecision = routingGoal.isBlank ? nil : AgentQualityRoutingService.baselineDecision(
        goal: routingGoal, targets: [preferredTarget], primaryTargetId: preferredTarget.id,
        requirements: requirements)
      return AgentConnectorRouteSelection(target: preferredTarget, decision: primaryDecision)
    }
`;
assert(source.includes(shortCircuit));
assert.equal(source.replace(insertion, '').replace(predicate, '').replace(shortCircuit, '')
  .replace('    goal: String = "",\n    preserveHealthyPrimary: Bool = false', '    goal: String = ""'), git('show', `${base}:${native}`));
assert(source.includes('let preferredTarget = preferredTargetId.isEmpty ? nil : eligibleById[preferredTargetId]'));
assert(source.includes('let routedTarget = calibratedCandidates.compactMap { eligibleById[$0.resource.targetId] }.first'));
const tests = read('apps/ios/GalaxySSITests/AgentRoutingCapabilityTests.swift');
for (const name of [
  'testConnectorPreferenceCannotResurrectCatalogOnlyTarget',
  'testUnavailableAdmittedTargetDoesNotFallBackToExcludedHealthyTarget',
  'testAdmittedRecoveringTargetIsNotHiddenByExcludedAvailableTarget',
  'testToolOnlyDecisionDoesNotFabricateReasoningCandidateFromCatalog',
  'testAgentConnectorRouteSelectorHonorsExplicitConnectorPreference',
  'testAgentConnectorRouteSelectorSelectsCodexWhenPhoneToolIsTopScoredResource',
  'testAgentConnectorRouteSelectorRecoversReasoningTargetDuringHeartbeat',
]) assert(tests.includes(`func ${name}(`), name);
for (const file of [
  'AgentQualityRouting.swift', 'AgentPlanRunModels.swift',
  'GalaxySSIAgentModelSelectionView.swift',
]) {
  const target = `apps/ios/GalaxySSI/${file}`;
  assert.equal(read(target), git('show', `${base}:${target}`), file);
}
const services = read('apps/ios/GalaxySSI/GalaxySSIServices.swift');
assert(services.includes('store.beginAgentAutoRouteTurn(for: message'));
assert(services.includes('preserveHealthyPrimary: true'));
assert.equal((services.match(/automaticTargetId: automaticTargetId/g) || []).length, 3);
assert.equal((services.match(/try recordAutomaticDispatch\(targetId:/g) || []).length, 3);
assert(services.includes('code: "auto_route_turn_not_committed"'));
assert(services.includes('code: "auto_route_dispatch_not_committed"'));
assert(services.includes('rememberedId: session.stableAutoRoute?.targetId ?? ""'));
const sessions = read('apps/ios/GalaxySSI/GalaxySSIStoreSessions.swift');
const persistence = sessions.slice(sessions.indexOf('  private func persistAgentAutoRoute('), sessions.indexOf('  func updateAgentSessionSummary('));
assert(persistence.indexOf('guard persisted else { return false }') < persistence.indexOf('cacheAgentConversation(session)'));
assert(persistence.includes('agentConversationDatabase.saveDraft(session)'));
assert(persistence.includes('agentConversationDatabase.upsert(session)'));
assert(sessions.includes('startedAt > current.turnStartedAt'));
assert(sessions.includes('defaults: defaults).mode == .automatic'));
assert(sessions.includes('AgentStableAutoRoutePolicy.acceptsUpdate(state: session.stableAutoRoute, turnId: turnId)'));
const models = read('apps/ios/GalaxySSI/AgentConversationModels.swift');
assert(models.includes('case stableAutoRoute = "stable_auto_route"'));
assert(models.includes('try container.decodeIfPresent(AgentStableAutoRouteState.self, forKey: .stableAutoRoute)'));
const header = read('apps/ios/GalaxySSI/GalaxySSIAgentHomeHeaderPresentation.swift');
assert(header.includes('return automaticTarget?.title.ifBlank(automaticLabel) ?? automaticLabel'));
assert(!header.includes('? "Codex"'));
assert(!header.includes('return liveExecutionTargetLabel'));
assert(read('apps/ios/GalaxySSI/GalaxySSIAndroidParityUI.swift').includes(
  'automaticTarget: coordinator.displayedAutoRouteTarget(conversationId: store.activeAgentConversationId)'));
const runtimeTests = read('apps/ios/GalaxySSITests/AgentConversationRuntimeTests.swift');
assert(runtimeTests.includes('func testStableAutoRoutePersistsExactConversationAndRejectsOldTurnsAndManualUpdates'));
assert(runtimeTests.includes('func testAutoHeaderUsesExactTargetNotOldSessionOrLiveDisplayLabels'));
const files = git('diff', '--name-only', `${android}^1`, android).trim().split('\n');
assert.equal(files.length, 17);
const disposition = file => {
  if (file.endsWith('build.gradle.kts')) return 'Android-only version bump excluded';
  if (file.includes('/androidTest/') || file.includes('/src/test/') || file.startsWith('docs/')) return 'Android evidence inventoried; new native admission regression source added but not executed; no live acceptance claim';
  if (file.endsWith('AgentStableAutoRoute.kt')) return 'Candidate admission, exact target ID, begin-turn and stale update guards adapted using encrypted native session payload, not a new plaintext preference store';
  if (file.endsWith('MainActivityAgentExecution.kt')) return 'Native header uses the same exact target identity as dispatch, not stale display labels or a fabricated Codex fallback';
  if (file.endsWith('AgentResourceRouter.kt')) return 'Healthy eligible displayed primary short-circuits quality/alternative ranking in native selector; existing capability admission retained, no new full capacity/privacy/budget router claimed';
  if (file.endsWith('MobileNativeAgentExecution.kt')) return 'Main native local/cloud/Agent branch chain shares one captured automatic target and persists admitted dispatch; Android parallel/recovery loop specifics still incomplete';
  return 'Inspected reference for broader primary identity, fresh fallback ranking, deferred recovery, attachment scope and parallel routing; not implemented or claimed by this admission increment';
};
const inventory = { androidPR: 3119, androidCommit: android, incrementalBase: base,
  scope: 'Decision admission, encrypted per-conversation target/turn, primary header/dispatch identity and healthy-primary short circuit; remaining recovery/parallel scope incomplete',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', `${android}:${file}`)).digest('hex'), disposition: disposition(file) })) };
const report = path.join(root, 'apps/ios/ANDROID_3119_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(report, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(report, 'utf8')), inventory);
console.log('Android #3119: admission plus encrypted scoped Auto identity and primary dispatch; remaining recovery/parallel parity incomplete. Source checks only.');
