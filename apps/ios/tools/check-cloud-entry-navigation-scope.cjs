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
const center = read('GalaxySSIControlCenterView.swift');
const hub = center.slice(center.indexOf('private struct GalaxySSIAndroidModelHubView:'),
  center.indexOf('private struct GalaxySSIAndroidAdvancedHubView:'));
assert(hub.indexOf('section(t("my_agent_add"') < hub.indexOf('section(t("my_agent_installed"'));
assert(hub.includes('ForEach(installedTargets)'));
assert(hub.includes('ContactDetailView(contactId: contact.id)'));
assert(hub.includes('activeLocalProfiles: []'));
assert(hub.includes('.filter { $0.kind == .agent || $0.kind == .model }'));
assert(hub.includes('!contact.deleted'));
assert(hub.includes('assetImageName: installedAssetName(contact)'));
assert(hub.includes('contact.deliveryMode == .cloudAPI'));
assert(!hub.includes('GalaxySSIRoutingPolicyView'));
assert(!hub.includes('GalaxySSIAgentsModelsNodesView()'));
assert(hub.includes('GalaxySSILocalModelLabView()'));
const overview = center.slice(center.indexOf('private var overviewCard:'), center.indexOf('private var commonSection:'));
assert(overview.includes('VStack(alignment: .center, spacing: 5)'));
assert(overview.includes('.multilineTextAlignment(.center)'));
assert(overview.includes('Text("GalaxySSI")'));
assert(overview.includes('GalaxySSIProfileIdentityView()'));
assert(overview.includes('showingQRCode = true'));
const menu = read('GalaxySSIAndroidMenuComponents.swift');
assert(menu.includes('.renderingMode(.original)'));
assert(menu.includes('.foregroundColor(tint)'));
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
  'GalaxySSIAndroidMenuComponents.swift', 'AgentIdentityPresentation.swift',
  'AgentNetworkRoutingModels.swift',
]) {
  const target = `apps/ios/GalaxySSI/${file}`;
  // Some storage operations live in the monolithic Store on older revisions.
  if (fs.existsSync(path.join(root, target))) {
    let source = fs.readFileSync(path.join(root, target), 'utf8');
    if (file === 'GalaxySSIStore.swift') {
      source = source.replace('    commitOwnedAgentTaskState(expected: expected, updated: updated)\n  }\n\n  func commitOwnedAgentTaskState(expected: AgentTaskRecord?, updated: AgentTaskRecord) -> Bool {\n', '');
    }
    if (file === 'AgentNetworkRoutingModels.swift' && source.includes('    let admittedTargetIds = decision.map { Set($0.orderedTargetIds) }\n')) {
      // #3119 adds only this admission boundary; its own scope check verifies it.
      assert(fs.existsSync(path.join(__dirname, 'check-stable-auto-admission-scope.cjs')));
      const refreshStart = source.indexOf('enum AgentAutomaticRouteAdmission {') >= 0
        ? source.indexOf('enum AgentAutomaticRouteAdmission {')
        : source.indexOf('enum AgentAutomaticConnectorRoutePolicy {');
      const refreshEnd = source.indexOf('enum AgentConnectorFallbackAction {');
      if (refreshStart >= 0) {
        assert(refreshEnd > refreshStart);
        source = source.slice(0, refreshStart) + source.slice(refreshEnd);
      }
      const start = source.indexOf('  static func mergingRoutingMetadata(');
      const end = source.indexOf('  static func resultMetadata(', start);
      if (start >= 0) {
        assert(end > start);
        source = source.slice(0, start) + source.slice(end);
        source = source.replace('      "auto_reroute_on_failure": String(action.parameters["auto_reroute_on_failure"] == "true" &&\n        action.parameters["manual_target_locked"] != "true"),\n', '');
      }
      source = source.replace('    let admittedTargetIds = decision.map { Set($0.orderedTargetIds) }\n', '')
        .replace('      (admittedTargetIds?.contains($0.id) ?? true) &&\n', '')
        .replace('    goal: String = "",\n    preserveHealthyPrimary: Bool = false', '    goal: String = ""')
        .replace(`    if preserveHealthyPrimary, decision == nil,
       let preferredTarget, preferredTarget.status == .available {
      let primaryDecision = routingGoal.isBlank ? nil : AgentQualityRoutingService.baselineDecision(
        goal: routingGoal, targets: [preferredTarget], primaryTargetId: preferredTarget.id,
        requirements: requirements)
      return AgentConnectorRouteSelection(target: preferredTarget, decision: primaryDecision)
    }
`, '');
    }
    assert.equal(source, git('show', `${base}:${target}`));
  }
}
const files = git('diff', '--name-only', `${android}^1`, android).trim().split('\n')
  .filter(file => file.startsWith('apps/android/'));
assert.equal(files.length, 11);
const inventory = {
  androidPR: 3169, androidCommit: android, incrementalBase: base,
  scope: 'model hub installed targets, cloud entry ordering, contact-first navigation, centered profile and home icon tones; no native visual acceptance',
  files: files.map(file => ({
    path: file,
    sha256: crypto.createHash('sha256').update(git('show', `${android}:${file}`)).digest('hex'),
    disposition: file.endsWith('build.gradle.kts') ? 'Android version excluded'
      : file.includes('/androidTest/') ? 'Android native fixtures inspected; not executed or claimed on iOS'
      : /MyAgentPages|RuntimePolicy|HistoryAndContacts/.test(file)
        ? 'Installed targets, cloud entry ordering/navigation and provider brand precedence adapted; unrelated code retained'
        : /ControlCenterUi|MainActivityControlCenter/.test(file)
          ? 'Centered profile brand/subtitle and retained profile/QR actions; native menu renderer already preserves supplied tones and original image colors'
          : 'Home semantic icon tones aligned; native shared renderers retain explicit colors; full legacy-subpage icon inventory remains unverified',
  })),
};
const report = path.join(root, 'apps/ios/ANDROID_3169_CLOUD_ENTRY_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(report, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(report, 'utf8')), inventory);
console.log('Android #3169: 11 pinned source dispositions; native cloud entry source contracts only. No UI/runtime acceptance.');
