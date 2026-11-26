// Source contracts only; not execution of Swift, preferences, SQLite, UI or routing.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'ee17e7cac043350e3f65c10ba025ecf55cde10c7', android = 'ceb1e269929767ca5ac5921f8d85fc52e9e103a3';
const norm = value => value.replace(/\r\n/g, '\n');
const read = file => norm(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => norm(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
function once(text, before, after) {
  assert.equal(text.split(before).length, 2, 'One declared creation hook: ' + before);
  return text.replace(before, after);
}
function section(text, start, end) {
  const first = text.indexOf(start), last = text.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, start);
  return text.slice(first, last);
}
const settingsFile = app + 'GalaxySSIAgentModelSelectionView.swift';
const settings = read(settingsFile), previous = show(base, settingsFile);
for (const token of ['loadSelection(key: defaultSelectionKey, defaults: defaults)', 'selection.mode == .manual',
  '!selection.targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty',
  'guard !hasStoredSelection(for: conversationId, defaults: defaults) else { return }',
  'useRememberedSelection ? defaultSelection(defaults: defaults) : AgentModelSelection()']) assert(settings.includes(token), token);
let retained = settings;
for (const [start, end] of [['  static func defaultSelection(', '  static func selectManual('],
  ['  static func inheritDefault(', '  static func configurationForTarget(']]) {
  retained = retained.replace(section(retained, start, end), section(previous, start, end));
}
retained = once(retained, '"galaxyssi.agent.model_selection.new_session_default", "Default for new conversations"',
  '"galaxyssi.agent.model_selection.current_session", "Saved for this Agent and future sessions"');
assert.equal(retained, previous, 'All other model selection, target configuration, Auto/manual persistence and picker controls retained');
const storeFile = app + 'GalaxySSIStoreSessions.swift';
let store = read(storeFile);
assert(store.includes('useRememberedSelection && !createdByAgent && collaborationRoster == nil'));
for (const [before, after] of [
  ['func createAgentSession(title: String = "", privateMode: Bool = false, globalTopicKey: String = "",\n                          useRememberedSelection: Bool = false)', 'func createAgentSession(title: String = "", privateMode: Bool = false, globalTopicKey: String = "")'],
  ['      privateMode: privateMode,\n      useRememberedSelection: useRememberedSelection', '      privateMode: privateMode'],
  ['    collaborationRoster: AgentCollaborationRoster? = nil,\n    useRememberedSelection: Bool = false', '    collaborationRoster: AgentCollaborationRoster? = nil'],
  ['    AgentModelSelectionSettings.initializeConversation(for: conversationId,\n      useRememberedSelection: useRememberedSelection && !createdByAgent && collaborationRoster == nil, defaults: defaults)',
    '    AgentModelSelectionSettings.inheritDefault(for: conversationId, defaults: defaults)']
]) store = once(store, before, after);
assert.equal(store, show(base, storeFile), 'All Store draft/database, collaboration, programmatic, switch/retry/delete paths otherwise unchanged');
for (const name of ['GalaxySSIAgentHomeSessionLifecycle', 'GalaxySSIAgentHomeScanAttachments', 'GalaxySSIAgentSessionsView',
  'GalaxySSIConversationHubView', 'GalaxySSIViews', 'GalaxySSIMainTabView']) {
  const file = app + name + '.swift';
  assert.equal(once(read(file), ', useRememberedSelection: true', ''), show(base, file), 'Only user creation opt-in: ' + name);
}
for (const name of ['GalaxySSIAgentRecentTasksView', 'GalaxySSIHealthAtlasAgentHandoff', 'GalaxySSIScannedAgentConversation',
  'GalaxySSIHealthCareAgentScope', 'GalaxySSIServices', 'AgentConnectorModels']) {
  assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), 'Independent routing/transport unchanged: ' + name);
}
const chinese = read(app + 'zh-Hans.lproj/Localizable.strings');
assert.equal((chinese.match(/"galaxyssi.agent.model_selection.new_session_default" = /g) || []).length, 1);
const runtimeTests = read('apps/ios/GalaxySSITests/AgentConversationRuntimeTests.swift');
for (const name of ['testNewUserSessionSnapshotsModelEffortAndProgrammaticSessionsDoNotInherit',
  'testExplicitAutoIsRememberedButExistingManualSessionIsUnchanged', 'testMalformedRememberedSelectionFailsClosedWithoutChangingStoredConversation']) assert(runtimeTests.includes('func ' + name + '('), name);
const firstRetained = '  func testMessageSubmissionScopeRejectsOtherConversationOwnerAndBlankIdentity';
const oldTests = show(base, 'apps/ios/GalaxySSITests/AgentConversationRuntimeTests.swift');
assert.equal(runtimeTests.slice(runtimeTests.indexOf(firstRetained)), oldTests.slice(oldTests.indexOf(firstRetained)), 'Existing runtime fixtures retained');
const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', project = read(projectFile);
assert.equal(project, show(base, projectFile));
assert(project.includes('AgentConversationRuntimeTests.swift in Sources'));
const java = 'apps/android/app/src/main/java/com/galaxyssi/chat/';
const ref = show(android, java + 'AgentModelSelectionSettings.kt');
for (const token of ['return readSelection(preferences, ::defaultKey)', 'useRememberedSelection: Boolean',
  'if (useRememberedSelection) defaultSelection(context) else AgentModelSelection()']) assert(ref.includes(token), token);
const creation = show(android, java + 'AgentTranscriptStore.kt');
assert(creation.includes('useRememberedSelection = true') && creation.includes('useRememberedSelection = false'));
const fixture = show(android, 'apps/android/app/src/androidTest/java/com/galaxyssi/chat/ScreenAssistantHomeRoutingDeviceTest.kt');
assert(fixture.includes('newUserConversationSnapshotsTheRememberedTargetModelAndEffort'));
assert(fixture.includes('changingTheRememberedSelectionDoesNotOverwriteExistingChats'));
const changed = cp.execFileSync('git', ['diff-tree', '--no-commit-id', '--name-only', '-r', android], {cwd: root, encoding: 'utf8'}).trim().split(/\r?\n/);
assert.equal(changed.length, 8);
for (const file of changed) assert(show(android, file).length > 0, file);
console.log('New-user model snapshot/source scope passed: full selection read, explicit creation opt-in, no existing/programmatic overwrite, retained transport and fixture wiring. No native preferences/SQLite/UI acceptance.');
