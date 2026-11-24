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
assert.equal(source.replace(insertion, '').replace(predicate, ''), git('show', `${base}:${native}`));
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
  'GalaxySSIServices.swift', 'AgentQualityRouting.swift', 'AgentPlanRunModels.swift',
  'GalaxySSIAgentHomeHeaderPresentation.swift', 'GalaxySSIAndroidParityUI.swift',
  'GalaxySSIAgentModelSelectionView.swift',
]) {
  const target = `apps/ios/GalaxySSI/${file}`;
  assert.equal(read(target), git('show', `${base}:${target}`), file);
}
const files = git('diff', '--name-only', `${android}^1`, android).trim().split('\n');
assert.equal(files.length, 17);
const disposition = file => {
  if (file.endsWith('build.gradle.kts')) return 'Android-only version bump excluded';
  if (file.includes('/androidTest/') || file.includes('/src/test/') || file.startsWith('docs/')) return 'Android evidence inventoried; new native admission regression source added but not executed; no live acceptance claim';
  if (file.endsWith('AgentStableAutoRoute.kt')) return 'Candidate-list admission boundary adapted in native selector; remembered exact conversation target, beginTurn and stale-turn storage remain unported';
  return 'Inspected reference for broader primary identity, fresh fallback ranking, deferred recovery, attachment scope and parallel routing; not implemented or claimed by this admission increment';
};
const inventory = { androidPR: 3119, androidCommit: android, incrementalBase: base,
  scope: 'Decision-candidate admission only; not a full stable Auto routing port',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', `${android}:${file}`)).digest('hex'), disposition: disposition(file) })) };
const report = path.join(root, 'apps/ios/ANDROID_3119_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(report, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(report, 'utf8')), inventory);
console.log('Android #3119: exact decision admission increment; full stable Auto identity/recovery remains incomplete. Source checks only.');
