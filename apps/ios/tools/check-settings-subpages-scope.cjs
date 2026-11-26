'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const prefix = 'apps/ios/GalaxySSI/';
const base = 'ee17e7cac043350e3f65c10ba025ecf55cde10c7';
const clean = text => text.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, prefix + file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + prefix + file],
  { cwd: root, encoding: 'utf8', maxBuffer: 20_000_000 }));
const after = (text, marker) => { assert(text.includes(marker), marker); return text.slice(text.indexOf(marker)); };
const between = (text, start, end) => {
  const tail = after(text, start);
  assert(tail.includes(end), end);
  return tail.slice(0, tail.indexOf(end));
};

for (const file of ['GalaxySSIStore.swift', 'GalaxySSIStoreAgentSettings.swift', 'GalaxySSIServices.swift',
  'AgentSafetySettings.swift', 'AgentPermissionsBudgetModels.swift', 'AgentIOSObsidianProjection.swift',
  'AgentIOSObsidianModels.swift', 'GalaxySSIObsidianCandidatesView.swift', 'GalaxySSILocalModelLabView.swift',
  'GalaxySSIVoiceProviderPagesView.swift', 'VoiceWhisperModelManager.swift', 'VoiceWhisperModelDownloadService.swift',
  'GalaxySSIOnDeviceRuntimeView.swift', 'AgentRuntimePackInstaller.swift', 'GalaxySSILocalModelArtifactView.swift']) {
  assert.equal(read(file), old(file), file + ': backing behavior and existing resource controls unchanged');
}
const memoryFile = 'GalaxySSIMemoryControlCenterView.swift';
const memory = read(memoryFile);
assert.equal(after(memory, '  private var lifecycleSection:'), after(old(memoryFile), '  private var lifecycleSection:'));
assert.equal(between(memory, '  private var categoriesSection:', '  private var controlsSection:'),
  between(old(memoryFile), '  private var categoriesSection:', '  private var controlsSection:'));
assert.equal(between(memory, '      GalaxySSIMemoryCaptureRow(', '\n      )') + '\n      )',
  between(old(memoryFile), '      GalaxySSIMemoryCaptureRow(', '\n      )') + '\n      )');
for (const destination of ['GalaxySSIAgentMemoryView()', 'GalaxySSIAgentKnowledgeView()', 'GalaxySSIMemoryInboxView()',
  'GalaxySSIGlobalAgentControlView(page: .obsidian)']) assert(memory.includes(destination), destination);
const memoryBody = between(memory, '  var body:', '  private var snapshot:');
assert.doesNotMatch(memoryBody, /GalaxySSISecurityHeroView|GalaxySSIMemoryMetricStrip/);
assert.match(memoryBody, /controlsSection[\s\S]*DisclosureGroup[\s\S]*categoriesSection[\s\S]*lifecycleSection[\s\S]*evolutionSection/);
assert.match(memory, /@SceneStorage\("ios\.memory-settings\.more"\) private var moreExpanded = false/);

const executionFile = 'GalaxySSIExecutionPolicyView.swift';
const execution = read(executionFile);
assert.equal(after(execution, '  private var permissionModeSection:'), after(old(executionFile), '  private var permissionModeSection:'));
assert.match(execution, /permissionModeSection\s+taskControlSection\s+DisclosureGroup/);
for (const key of ['confirmation', 'privacy']) assert(execution.includes('@SceneStorage("ios.execution-policy.' + key + '")'));

const generalFile = 'GalaxySSIGeneralControlCenterView.swift';
const general = read(generalFile);
assert.equal(after(general, '  private var textScaleSummary:'), after(old(generalFile), '  private var textScaleSummary:'));
assert.equal(between(general, '  private var generalSection:', '  private var aboutSection:'),
  between(old(generalFile), '  private var generalSection:', '  private var aboutSection:'));
assert.match(general, /notificationStatusLabel\) \{ notificationSettingsPage \}/);
assert.match(general, /private var notificationSettingsPage:[\s\S]*GalaxySSIBackButton\(\)[\s\S]*notificationsSection/);
assert.match(general, /onChange\(of: scene\) \{ if \$0 == \.active \{ refreshNotifications\(\) \} \}/);
assert.match(general, /DisclosureGroup[^\n]*\{\s+advancedSection\s+resetSection/);

const globalFile = 'GalaxySSIGlobalAgentControlView.swift';
const global = read(globalFile);
assert.equal(after(global, '  private var worldSection:'), after(old(globalFile), '  private var worldSection:'));
assert.equal(between(global, '  private var heroSection:', '  private var autonomySection:'),
  between(old(globalFile), '  private var heroSection:', '  private var autonomySection:'));
assert.equal(between(global, '    .onAppear(perform: refreshRuntime)', '  private var proactiveHub:'),
  between(old(globalFile), '    .onAppear(perform: refreshRuntime)', '  private var heroSection:'));
const oldControls = between(old(globalFile), '  private var autonomySection:', '  private var worldSection:');
const currentControls = between(global, '  private var autonomySection:', '  private var worldSection:');
const paths = text => [...text.matchAll(/keyPath: \\.(\w+)/g)].map(match => match[1]);
assert.equal(paths(oldControls).length, 12, 'Nonempty authoritative switch comparison');
assert.deepEqual(paths(currentControls), paths(oldControls), 'Every existing advanced switch remains');
assert.match(global, /keyPath: \\.autonomousToolExecutionEnabled,\s+enabled: store\.globalAgentSettings\.enabled && store\.globalAgentSettings\.autonomousPreparationEnabled/);
assert.match(global, /keyPath: \\.dynamicAutonomousReplanningEnabled,\s+enabled: store\.globalAgentSettings\.enabled && store\.globalAgentSettings\.autonomousPreparationEnabled/);
assert.match(global, /keyPath: \\.proactiveDiscoveryEnabled,\s+enabled: store\.globalAgentSettings\.enabled && store\.globalAgentSettings\.modelUnderstandingEnabled/);
assert.match(global, /var page: GalaxySSIGlobalAgentSettingsPage = \.proactive/);
assert.match(global, /if page == \.obsidian \{ obsidianSection \}/);
assert.match(global, /else if page == \.proactive \{ proactiveHub \}/);
assert.match(global, /globalBinding\(\\.enabled\)/);
assert.match(global, /globalBinding\(\\.proactiveInsightsEnabled\)\)\s+\.disabled\(!store\.globalAgentSettings\.enabled\)/);
for (const kind of ['longHorizon', 'research', 'insights', 'runs', 'continuity']) assert(global.includes('compactDestination(.' + kind + ','));
assert.match(global, /if kind == \.insights \{ GalaxySSIGlobalAgentInsightInboxView\(\) \}/);
assert.match(global, /else if kind == \.runs \{ GalaxySSIGlobalAgentRunsView\(\) \}/);
assert.match(global, /else \{ GalaxySSIGlobalAgentDetailView\(kind: kind, snapshot: snapshot\) \}/);
assert.match(global, /if keyPath != \\.enabled && !store\.globalAgentSettings\.enabled \{ return \}/);
assert.match(global, /store\.updateGlobalAgentSettings \{ \$0\[keyPath: keyPath\] = value \}/);
assert.match(global, /coordinator\.refreshAgentHomeState\(\)/);
assert.equal((global.match(/@SceneStorage\("ios\.proactive-settings\.[^"]+"\) private var \w+ = false/g) || []).length, 5);

const homeFile = 'GalaxySSIControlCenterView.swift';
const home = read(homeFile), homeBase = old(homeFile);
const marker = 'private struct GalaxySSIAndroidAdvancedHubView:';
const oldAdvanced = after(homeBase, marker);
assert.equal((oldAdvanced.match(/GalaxySSIGlobalAgentControlView\(\)/g) || []).length, 1);
assert.equal(home, homeBase.slice(0, homeBase.indexOf(marker)) + oldAdvanced.replace('GalaxySSIGlobalAgentControlView()',
  'GalaxySSIGlobalAgentControlView(page: .advanced)'), 'Only the explicit Advanced destination changes');

const chineseFile = 'zh-Hans.lproj/Localizable.strings';
const chinese = read(chineseFile);
const labels = { my_agent_records: '我的资料', my_agent_memory_items: '我的记忆', my_agent_review: '待确认',
  my_agent_record_scope: '记录范围', my_agent_goals: '目标与研究', my_agent_current: '当前进展',
  my_agent_advanced_controls: '高级控制', my_agent_cognition: '后台认知', my_agent_obsidian: 'Obsidian', my_agent_more: '更多' };
assert.equal(chinese, old(chineseFile) + Object.entries(labels).map(([key, value]) => `"${key}" = "${value}";\n`).join(''));
const inventory = JSON.parse(fs.readFileSync(path.join(root, 'apps/ios/ANDROID_3165_SOURCE_INVENTORY.json'), 'utf8'));
assert.equal(inventory.files.length, 19);
for (const name of ['MainActivityMyAgentPages.kt', 'MainActivityEvolutionMemory.kt', 'MainActivityGlobalAgent.kt', 'MainActivityGeneralPolicy.kt']) {
  const entry = inventory.files.find(file => file.path.endsWith('/' + name));
  assert(entry, name);
  const bytes = cp.execFileSync('git', ['show', inventory.androidCommit + ':' + entry.path], { cwd: root });
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), entry.sha256, name + ': pinned Android source');
}
console.log('Settings subpage source scope passed; no native compilation, UI/device acceptance or test execution.');
