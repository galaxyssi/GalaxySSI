// Source-only integration checks. No Swift build, XCTest, simulator or UI acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const cp = require('node:child_process'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '8b4049723a707c692b8fefdc56fa617fcd45163c';
const android = '27339973ae8f598b6ad4d64794a1c73dcf525d9f';
const androidBase = '9229e18652978c14e3bb4fe3454b32d77ff3f0a7';
const clean = s => s.replace(/\r\n/g, '\n');
const git = (...args) => clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function once(s, from, to) { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, first); assert.equal(s.split(first).length, 2, first);
  return s.slice(a, b);
}
const file = app + 'GalaxySSIAgentModelSelectionView.swift';
const source = read(file), before = git('show', base + ':' + file);
let retained = source;
retained = once(retained, '  private typealias ReadyCloudModel = AgentModelPickerCloudChoice\n\n',
  section(before, '  private struct ReadyCloudModel:', '  @Environment('));
retained = once(retained, '  @Environment(\\.galaxySSIInterfaceLanguage)', '  @Environment(\\.dismiss) private var dismiss\n  @Environment(\\.galaxySSIInterfaceLanguage)');
for (const line of ['  @State private var preparedConversationId = ""\n', '  @State private var preparedIdentityFingerprint = ""\n',
  '  @State private var pickerVisible = false\n', '  @State private var bypassPreparedCache = false\n',
  '  @State private var contentLoadInFlight = false\n', '  @State private var reloadPending = false\n']) retained = once(retained, line, '');
for (const [first, last] of [
  ['  private var agentTargets:', '  private var selectedManualTargetIsVisible:'],
  ['  var body: some View {', '  private var modelSelectionLoadingContent:'],
  ['  private var modelSelectionContentTaskID:', '  private static func modelSelectionContent('],
  ['  private func selectAutomatic(', '  private func reasoningEffortLabel('],
]) retained = once(retained, section(retained, first, last), section(before, first, last));
retained = once(retained, '  private func selectedCloudModel(',
  section(before, '  private func isSelectedLocal(', '  private func selectedCloudModel(') + '  private func selectedCloudModel(');
retained = once(retained, '  private func selectAutomatic(',
  section(before, '  private func isSelectedAgent(', '  private func selectAutomatic(') + '  private func selectAutomatic(');
retained = once(retained, section(retained, '  private var canSelectPreparedContent:', '  private func agentLogoAssetName('),
  section(before, '  private func finishSelection(', '  private func agentLogoAssetName('));
assert.equal(retained, before, 'Complete picker retained outside declared layout/load/selection hooks; persisted settings and other helpers unchanged');
for (const token of ['GalaxySSIAgentModelPickerContent(', 'onAgent: { selectAgent($0, modelId: $1) }',
  '.id(store.activeAgentConversationId)', 'preparedIdentityFingerprint == store.profile.identityFingerprint',
  'pickerVisible && !contentLoading', 'guard !contentLoadInFlight else { reloadPending = true; return }',
  'if reloadPending && pickerVisible', 'let prepared = await Task.detached',
  'current.invocationProfile.reasoningEfforts.contains(reasoningEffort)',
  'current.invocationProfile.models.contains(where: { $0.id == modelId })',
  'LocalModelRuntimeSettings.activeProfiles().contains', 'AgentConnectorAvailability.cloudModelReady(model: currentModel',
  'AgentModelSelectionSettings.defaultSelection() == selection']) assert(source.includes(token), token);
assert(!source.includes('let fastContent = Self.modelSelectionContent('));
assert(!section(source, '    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIAgentRoutingDidUpdate))', '    .onDisappear {').includes('requestCapabilityManifestRefresh'));
assert(!section(source, '  private func finishSelection(', '  private func agentLogoAssetName(').includes('dismiss'));
const policy = read(app + 'AgentModelPickerPolicy.swift'), reference = git('show', android + ':apps/android/app/src/main/java/com/galaxyssi/chat/AgentModelPickerPolicy.kt');
for (const name of ['olderCodexIds', 'olderClaudeIds']) {
  const swift = section(policy, '  private static let ' + name + ':', '\n  ]');
  const kotlin = section(reference, '    private val ' + name + ' =', '\n    )');
  const strings = s => Array.from(s.matchAll(/"([^"]+)"/g), m => m[1]);
  assert.deepEqual(strings(swift), strings(kotlin), name);
}
const content = read(app + 'GalaxySSIAgentModelPickerContent.swift');
for (const token of ['.pickerStyle(.segmented)', 'ios.agent.model-picker.summary', 'ios.agent.model-picker.sources',
  'ios.agent.model-picker.older', 'ios.agent.model-picker.effort', 'AgentModelPickerPolicy.modelGroups',
  'if expandedLegacy', 'Image(asset)', 'onAgent(target, model.id)', 'onCloud(item)', 'onLocal(profile)',
  'AddContactView(autoOpenScanner: true)', 'CloudModelProviderSelectionView()', 'GalaxySSILocalModelLabView()']) assert(content.includes(token), token);
assert(section(content, '  var body: some View {', '  private var summary:').includes('      footer\n'));
assert(!content.includes('Menu {'));
const resources = read(app + 'zh-Hans.lproj/Localizable.strings');
for (const match of (content + source).matchAll(/t\("(agent_model_picker\.[^"]+)"/g))
  assert(resources.includes('"' + match[1] + '" = '), match[1]);
assert(!/[\u3400-\u9fff]/.test(content + policy + source), 'No Chinese prose outside localization resources');
for (const name of ['AgentConnectorModels', 'AgentNetworkRoutingModels', 'AgentNativeToolCore', 'GalaxySSIStore',
  'GalaxySSIStoreSessions', 'GalaxySSIServices', 'GalaxySSINavigationContentPrewarm', 'GalaxySSIAgentHomeHeaderView',
  'GalaxySSIAgentHomeNavigationRoutesView']) assert.equal(read(app + name + '.swift'), git('show', base + ':' + app + name + '.swift'), name);
const tests = read('apps/ios/GalaxySSITests/AgentModelPickerPolicyTests.swift');
for (const name of ['ActiveOlderModelStaysVisibleWithoutOpeningOtherOlderModels', 'OldOnlyCatalogRemainsVisibleAndUnknownNewIdsNeedNoAppUpdate',
  'DifferentComputersKeepTheirOwnTargetsAndSelectedAgentSortsFirst', 'UnavailableAndDuplicateTargetsDoNotBecomeSelectable',
  'LegacyFoldingIsSpecificToAgentFamilyNotCloudOrOtherAgents', 'RetiredModelsStayExcludedEvenIfManuallyAddedToProfile',
  'SourceDefaultsFollowLocalCloudSelectedDesktopAndAvailableFallbacks', 'PresentationLabelsDoNotChangeIdentifiersOrCatalogs'])
  assert(tests.includes('func test' + name + '('), name);
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentModelPickerPolicy', 'GalaxySSIAgentModelPickerContent', 'AgentModelPickerPolicyTests'])
  assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
const files = git('diff', '--name-only', androidBase, android).trim().split('\n');
assert.equal(files.length, 14);
function disposition(file) {
  if (file.endsWith('build.gradle.kts')) return 'Android version excluded; no iOS version bump';
  if (file.includes('/androidTest/') || file.includes('/src/test/')) return 'Reference fixture source inspected; eight iOS policy fixtures authored, not executed; no native device/UI equivalence claim';
  if (file.endsWith('AgentModelPickerPolicy.kt')) return 'Native source/group policy: stable selected/Codex ordering, concrete Desktop dedup, family-specific legacy folding, active legacy retention, old-only fallback, future IDs and labels; reuse public normalizedModelId, alias catalog support remains separately tracked by #4559';
  if (file.endsWith('MainActivityAgentModelPicker.kt')) return 'Native current-route summary, segmented Desktop/cloud/local, inline model rows, one expanded provider, legacy disclosure, real logos, pinned supported reasoning, reload/setup controls and stay-open selection. Coalesced off-main source read and current conversation/identity/visible-page/capability rechecks. No native layout or concurrency acceptance';
  if (file.endsWith('MainActivityAgentSessions.kt')) return 'Existing iOS entry reused; removed old menu/configuration rendering from model picker only, unchanged persistence schema and routing';
  if (file.endsWith('MainActivityAgentSettings.kt') || file.endsWith('MainActivityCloudAndImages.kt')) return 'Existing routing/import/pairing notifications reused for open-picker refresh; no manifest request from routing notifications and no MQTT/service changes';
  if (file.endsWith('activity_main.xml')) return 'Native fixed footer outside ScrollView; no Agent home layout change';
  if (file.endsWith('colors.xml')) return 'Reuse existing native adaptive surface/text/accent and brand image assets; no Android colors copied';
  return 'English fallback/Chinese resources for picker controls and model descriptions; future-chat hint shown only when existing default selection actually equals current selection; no default-memory/catalog behavior duplicated';
}
const inventory = {androidPR: 4561, androidCommit: android, androidBase, iosBase: base,
  scope: 'Unified native model picker; existing catalog/default/routing semantics retained. No native build, XCTest, CI, UI/runtime acceptance or IPA',
  files: files.map(file => ({path: file, sha256: crypto.createHash('sha256').update(git('show', android + ':' + file)).digest('hex'), disposition: disposition(file)}))};
const report = path.join(root, 'apps/ios/ANDROID_4561_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(report, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(report, 'utf8')), inventory);
console.log('Android #4561: 14 pinned source dispositions and native picker source contracts passed; no Swift/UI/runtime acceptance');
