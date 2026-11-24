const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '../../..');
const base = '2970b645a07d310a246d5e80e27c5a76a88157bc';
const android = 'ee66cb9623c40613aefc07fd54bb71924efb8940';
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' });
const read = name => fs.readFileSync(path.join(root, 'apps/ios/GalaxySSI', name), 'utf8');
const nodes = read('GalaxySSIAgentsModelsNodesView.swift');
const details = read('GalaxySSIContactDetailView.swift');
const routing = read('GalaxySSIResourceRoutingView.swift');
const body = nodes.slice(nodes.indexOf('var body:'), nodes.indexOf('private var addResourcesSection:'));
assert(body.indexOf('addResourcesSection') < body.indexOf('GalaxySSISecurityHeroView'));
assert(body.indexOf('addResourcesSection') < body.indexOf('desktopSection'));
const actions = nodes.slice(nodes.indexOf('private var addResourcesSection:'), nodes.indexOf('private var desktopSection:'));
assert(actions.indexOf('CloudModelProviderSelectionView()') < actions.indexOf('AddContactView(autoOpenScanner: true)'));
assert.equal((nodes.match(/CloudModelProviderSelectionView\(\)/g) || []).length, 1);
const cloud = nodes.slice(nodes.indexOf('private var cloudAPISection:'), nodes.indexOf('private func desktopTitle'));
assert(cloud.includes('assetImage: cloudAssetName(contact)'));
assert(cloud.includes('ContactDetailView(contactId: contact.id)'));
assert(!cloud.includes('CloudModelProviderDetailView'));
assert(details.includes('GalaxySSIContactMessagingDestination(contactId: contact.id)'));
assert(details.includes('t("galaxyssi.cloud.config_title", "Configure Model")'));
assert(details.includes('CloudModelProviderDetailView(contactId: contact.id)'));
assert(!routing.includes('CloudModelProviderDetailView(contactId: contact.id)'));
for (const file of [
  'GalaxySSIStore.swift', 'GalaxySSIStoreCloudModelOperations.swift',
  'GalaxySSIContactAvatarView.swift', 'GalaxySSICloudModelOnboardingView.swift',
]) {
  const target = `apps/ios/GalaxySSI/${file}`;
  // Some storage operations live in the monolithic Store on older revisions.
  if (fs.existsSync(path.join(root, target))) {
    assert.equal(fs.readFileSync(path.join(root, target), 'utf8'), git('show', `${base}:${target}`));
  }
}
const files = git('diff', '--name-only', `${android}^1`, android).trim().split('\n')
  .filter(file => file.startsWith('apps/android/'));
assert.equal(files.length, 11);
const inventory = {
  androidPR: 3169, androidCommit: android, incrementalBase: base,
  scope: 'cloud entry ordering and contact-first navigation only; not full settings visual parity',
  files: files.map(file => ({
    path: file,
    sha256: crypto.createHash('sha256').update(git('show', `${android}:${file}`)).digest('hex'),
    disposition: file.endsWith('build.gradle.kts') ? 'Android version excluded'
      : file.includes('/androidTest/') ? 'Android native fixtures inspected; not executed or claimed on iOS'
      : /MyAgentPages|RuntimePolicy|HistoryAndContacts/.test(file)
        ? 'Cloud entry ordering/navigation adapted; unrelated code retained'
        : 'Settings hero, icon palette and legacy subpage visual parity deferred; not claimed',
  })),
};
const report = path.join(root, 'apps/ios/ANDROID_3169_CLOUD_ENTRY_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(report, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(report, 'utf8')), inventory);
console.log('Android #3169: 11 pinned source dispositions; native cloud entry source contracts only. No UI/runtime acceptance.');
