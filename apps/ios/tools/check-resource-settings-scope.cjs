const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '../../..');
const base = '6af00b2194dcf14691b33ff3d5f79b1b77f350ce';
const android = 'dab287aef9f951ded0b1ebf4cbb01c9da0ae52ee';
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
const prefix = 'apps/ios/GalaxySSI/';
const read = file => fs.readFileSync(path.join(root, prefix, file), 'utf8');
const old = file => git('show', `${base}:${prefix}${file}`);
const after = (text, marker) => { assert(text.includes(marker), marker); return text.slice(text.indexOf(marker)); };
const before = (text, marker) => { assert(text.includes(marker), marker); return text.slice(0, text.indexOf(marker)); };

const localFile = 'GalaxySSILocalModelLabView.swift';
const local = read(localFile);
let oldLocalControls = after(old(localFile), '  private var manageSection:');
for (const [key, fallback] of [
  ['preflight_section', 'Runtime Preflight'], ['acceleration_section', 'Acceleration Backends'],
  ['section_permissions', 'Device Permissions'], ['section_privacy_storage', 'Privacy & Storage'],
]) {
  oldLocalControls = oldLocalControls.replace(`      GalaxySSILocalModelLabSectionTitle(title: t("galaxyssi.local_model.${key}", "${fallback}"))\n`, '');
  assert(local.includes(`DisclosureGroup(t("galaxyssi.local_model.${key}"`));
}
assert.equal(after(local, '  private var manageSection:'), oldLocalControls);
assert.equal((local.match(/@SceneStorage\("ios.local-model\.[^"]+"\) private var \w+ = false/g) || []).length, 4);
assert(local.indexOf('          manageSection') < local.indexOf('          DisclosureGroup'));

const voiceFile = 'GalaxySSIVoiceProviderPagesView.swift';
const voice = read(voiceFile);
let oldVoiceControls = after(old(voiceFile), '  private var recognitionSection:');
for (const [key, fallback] of [
  ['voice_asr_online_privacy_section', 'Online audio privacy'],
  ['voice_asr_remote_section', 'My Desktop accuracy node'],
  ['voice_provider_device_capabilities', 'Device capabilities'],
  ['voice_asr_runtime_mode_section', 'Runtime policy'],
]) {
  oldVoiceControls = oldVoiceControls.replace(`      GalaxySSISecuritySectionTitle(title: t("${key}", "${fallback}"))\n`, '');
  assert(voice.includes(`DisclosureGroup(t("${key}"`));
}
assert.equal(after(voice, '  private var recognitionSection:'), oldVoiceControls);
assert.equal((voice.match(/@SceneStorage\("ios.asr\.[^"]+"\) private var \w+ = false/g) || []).length, 4);
assert(voice.indexOf('          modelSection') < voice.indexOf('          if onlineRealtimeASREnabled'));
const oldConsent = old(voiceFile).slice(old(voiceFile).indexOf('    .alert('), old(voiceFile).indexOf('  private var recognitionSection:'));
assert(voice.includes(oldConsent));

const runtimeFile = 'GalaxySSIOnDeviceRuntimeView.swift';
const runtime = read(runtimeFile);
assert.equal(before(runtime, 'struct GalaxySSIRuntimeSoftwareCenterView:'),
  before(old(runtimeFile), 'struct GalaxySSIRuntimeSoftwareCenterView:'));
assert.equal(after(before(runtime, 'private struct GalaxySSIRuntimePackDetailSheet:'), '  private func loadCachedCatalog()'),
  after(before(old(runtimeFile), 'private struct GalaxySSIRuntimePackDetailSheet:'), '  private func loadCachedCatalog()'));
assert.equal(after(after(runtime, 'private struct GalaxySSIRuntimePackDetailSheet:'), '          GalaxySSISecurityPrimaryButton('),
  after(after(old(runtimeFile), 'private struct GalaxySSIRuntimePackDetailSheet:'), '          GalaxySSISecurityPrimaryButton('));
assert(runtime.includes('catalogEntrySubtitle(entry, installed: installed)'));
assert(runtime.includes('installed.installedVersion ?? t("galaxyssi.status.unknown", "Unknown")'));
assert(runtime.includes('let ready = installed.installedVersion == entry.version'));
const model = read('AgentRuntimePackModels.swift');
const property = model.slice(model.indexOf('  var installedVersion: String? {'), model.indexOf('\n  init(', model.indexOf('  var installedVersion: String? {')));
assert(property.includes('state == .ready'));
assert(property.includes('manifest?.version'));
assert(!property.includes('entry') && !property.includes('catalog'));
assert.equal(model.replace('\n' + property, ''), old('AgentRuntimePackModels.swift'));

for (const file of [
  'GalaxySSIStore.swift', 'AgentRuntimePackInstaller.swift', 'AgentIOSRuntimePackCatalogManager.swift',
  'VoiceWhisperModelSettingsView.swift', 'VoiceWhisperModelManager.swift',
  'VoiceWhisperModelDownloadService.swift', 'GalaxySSILocalModelArtifactView.swift',
  'GalaxySSIControlCenterView.swift',
]) {
  assert.equal(file === 'GalaxySSIStore.swift'
    ? require('./check-workspace-index-scope.cjs').retainedWorkspaceDefault(read(file))
    : require('./check-dashboard-refresh-scope.cjs').retainedDashboardView(file, read(file)), old(file), file);
}
const files = git('diff', '--name-only', `${android}^1`, android).trim().split('\n');
assert.equal(files.length, 19);
const disposition = file => {
  if (file.endsWith('build.gradle.kts')) return 'Android version excluded';
  if (file.includes('/androidTest/') || file.includes('/src/test/') || file.startsWith('docs/')) return 'Android acceptance evidence inspected; not an executed iOS test';
  if (file.includes('/res/')) return 'Native existing resource keys reused; no Android resource copy or claim of complete UI parity';
  if (/MyAgentResourceSections|MainActivityVoiceSettings|MainActivityLocalAndDesktop/.test(file)) return 'Native collapsible resource sections adapted; existing model/ASR controls and actions retained exactly';
  if (/MainActivityGeneralPolicy/.test(file)) return 'Installed and downloadable pack versions separated in native software list/detail; other general settings parity remains unverified';
  if (/MainActivityMyAgentPages|MainActivityControlCenter|ControlCenterUi/.test(file)) return 'Existing native home/model hub retained, including #3169 follow-up; broad subpage redesign not newly claimed';
  return 'Existing native lifecycle/settings retained; remaining execution/memory/proactive/general layout differences not claimed complete';
};
const inventory = { androidPR: 3165, androidCommit: android, incrementalBase: base,
  scope: 'Resource section folding and installed/catalog version separation; remaining broad settings parity unverified',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', `${android}:${file}`)).digest('hex'), disposition: disposition(file) })) };
const report = path.join(root, 'apps/ios/ANDROID_3165_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(report, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(report, 'utf8')), inventory);
console.log('Android #3165: 19 source dispositions; preserved resource controls and installation actions; source-only evidence.');
