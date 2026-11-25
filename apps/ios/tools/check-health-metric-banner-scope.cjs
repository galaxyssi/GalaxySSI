// Source contracts only, not native SwiftUI rendering or privacy/concurrency execution.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'ee17e7cac043350e3f65c10ba025ecf55cde10c7', android = '67e7293fa8988e305ecd0b036887d6e49ab812e5';
const normalize = text => text.replace(/\r\n/g, '\n');
const read = file => normalize(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => normalize(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));
const section = (text, start, end) => {
  const first = text.indexOf(start), last = text.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, start);
  return text.slice(first, last);
};
const viewFile = app + 'GalaxySSIHealthCareView.swift', view = read(viewFile), before = show(base, viewFile);
const entryStart = '@MainActor\nstruct GalaxySSIHealthCareEntry:', detailStart = '@MainActor\nstruct GalaxySSIHealthCareDetail:';
assert.equal(view.slice(0, view.indexOf(entryStart)), before.slice(0, before.indexOf(entryStart)), 'Health center/priority routes unchanged');
assert.equal(view.slice(view.indexOf(detailStart)), before.slice(before.indexOf(detailStart)), 'Complete detail/review routes unchanged');
const entry = section(view, entryStart, detailStart), oldEntry = section(before, entryStart, detailStart);
assert.equal(section(entry, '  private var canRead:', '  private func clear()'), section(oldEntry, '  private var canRead:', '  private func openDiscussion'), 'Exact active owner/private-session gate retained');
assert.equal(section(entry, '    .onChange(of: scene)', '      concerns = [current]'), section(oldEntry, '    .onChange(of: scene)', '      concerns = [current]'), 'Protected data/session/record-change guards retained');
assert.equal(section(entry, '    .task(id: revision)', '        try Task.checkCancellation()'), section(oldEntry, '    .task(id: revision)', '        let current = [concern]'), 'Reconcile, revision/cancellation and exact persisted binding retained');
assert(entry.includes('displayedConversationID == conversationID'));
assert(entry.includes('GalaxySSIHealthCareAgentPanel(metric: concern.metric, assessment: concern.assessment)'));
for (const token of ['NavigationLink', 'Button', '.sheet(', 'expanded', 'setPriority', 'nextStep', 'concern.comparison']) assert(!entry.includes(token), token);
const panel = read(app + 'GalaxySSIHealthCareAgentPanel.swift');
for (const token of ['assessment.record != nil', 'assessment.result.trimmingCharacters', 'assessment.reference.trimmingCharacters',
  'kind != .qualitative', 'metric.title(language: language)', 'Text(value).font(.footnote.weight(.semibold)) + reference',
  'health_agent_report_reference', '.fixedSize(horizontal: false, vertical: true)', 'agent-health-care-value']) assert(panel.includes(token), token);
for (const token of ['Button', 'ScrollView', 'GeometryReader', '.lineLimit(', '.clipped()', 'chevron', 'comparison', 'assessment.signals', 'stage(']) assert(!panel.includes(token), token);
const homeFile = app + 'GalaxySSIAndroidParityUI.swift';
assert.equal(read(homeFile).replace('conversationID: session.id)', 'conversationID: session.id, availableHeight: viewport.size.height)'), show(base, homeFile), 'Only obsolete height argument removed; composer/transcript unchanged');
for (const name of ['GalaxySSIHealthCareAgentScope', 'GalaxySSIHealthCare', 'GalaxySSIHealthRecords',
  'GalaxySSIHealthCareDiscussion', 'GalaxySSIHealthCarePlan', 'GalaxySSIHealthCareFollowUp', 'GalaxySSIHealthCareTarget']) {
  assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
}
assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'), show(base, 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'));
for (const locale of ['en', 'zh-Hans']) {
  const strings = read(app + locale + '.lproj/HealthAssessmentPanel.strings');
  assert.equal((strings.match(/"health_agent_report_reference" = /g) || []).length, 1);
  assert(strings.includes(' %@";'));
}
const testFile = 'apps/ios/GalaxySSITests/GalaxySSIHealthOverviewCareTests.swift', tests = read(testFile), oldTests = show(base, testFile);
const retainedTests = '  func testIndependentAgentScopeRequiresExactPrivateActiveTopic';
assert.equal(tests.slice(tests.indexOf(retainedTests)), oldTests.slice(oldTests.indexOf(retainedTests)), 'Other scope/overview/care fixtures unchanged');
assert.equal((tests.match(/  func testHealthMetricBanner/g) || []).length, 3);
assert(!tests.includes('GalaxySSIHealthCareAgentPanelLayout'));
const java = 'apps/android/app/src/main/java/com/galaxyssi/chat/';
const panelRef = show(android, java + 'HealthCareAgentPanel.kt'), surfaceRef = show(android, java + 'HealthCareAgentSurface.kt');
for (const token of ['assessment.record != null', 'assessment.reportReference.trim()', 'health_agent_report_reference', 'HealthResultKind.QUALITATIVE']) assert(panelRef.includes(token), token);
assert(!panelRef.includes('chevron') && !panelRef.includes('ScrollView'));
for (const token of ['store.discussion(conversation.id) == concernId', 'modelReviewVisibility(conversation.id.takeIf', 'HealthCareAgentPanel(activity, concern.metric, concern.assessment)']) assert(surfaceRef.includes(token), token);
const changed = cp.execFileSync('git', ['diff-tree', '--no-commit-id', '--name-only', '-r', android], {cwd: root, encoding: 'utf8'}).trim().split(/\r?\n/);
assert.equal(changed.length, 11);
assert.equal(changed.filter(file => file.includes('/androidTest/')).length, 6);
for (const file of changed) assert(show(android, file).length > 0, 'Inspect pinned Android source: ' + file);
console.log('Health metric banner source scope passed: same-assessment value/reference, read-only wrapping layout, exact private binding/lifecycle and Health center routes retained. No native UI/privacy/device acceptance.');
