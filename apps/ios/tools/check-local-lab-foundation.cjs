// Source-only contracts for local lab routing, UI and reminders. These do not execute Swift.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n');
const core = read('apps/ios/GalaxySSI/GalaxySSIHealthAgentLab.swift');
for (const token of ['reading.metric.laboratory, !reading.deleted, reading.isValid, reading.measuredAt <= through',
  'eligible.contains { $0.reportSource != nil }', 'source.filter { $0.measuredAt >= day }',
  'case results, abnormal, note, remind', 'range.position == .notComparable',
  'self.owner == owner, self.policy == policy, self.through == through',
  'uptime >= deadline - 60, uptime <= deadline', 'used = true',
  'try persistLocalLabAudit(archive)', 'guard permitted else { throw Failure.permission }',
  'GalaxySSIHealthAgentLab.Policy(archive) == policy', 'archive.current.first(where: { $0.id == expected.id }) == expected',
  'try write(updated)', 'UIApplication.shared.isProtectedDataAvailable']) assert(core.includes(token), token);
const audit = core.slice(core.indexOf('  struct Audit:'), core.indexOf('  struct Snapshot'));
assert(!/reading|notes|sourceID|recordID|value:/.test(audit), 'Audit must not duplicate measurement content');
assert(!/CloudModelClient|MessageCoordinator|conversationStreamingRequest|queuePrivateHealth/.test(core),
  'The local read foundation must not submit health content to a model');
for (const name of ['GalaxySSIHealthAgentLab', 'GalaxySSIHealthAgentLabTests', 'GalaxySSIHealthAgentLabIntent',
  'GalaxySSIHealthAgentLabView', 'GalaxySSIHealthAgentLabIntentTests']) {
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' registered');
  const source = read(`apps/ios/${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`);
  assert(!/\p{Script=Han}/u.test(source), 'Localized strings belong in resources');
}
assert.equal((read('apps/ios/GalaxySSITests/GalaxySSIHealthAgentLabTests.swift').match(/func test/g) || []).length, 8);
const intent = read('apps/ios/GalaxySSI/GalaxySSIHealthAgentLabIntent.swift');
const ui = read('apps/ios/GalaxySSI/GalaxySSIHealthAgentLabView.swift');
const records = read('apps/ios/GalaxySSI/GalaxySSIHealthRecords.swift');
const submit = read('apps/ios/GalaxySSI/GalaxySSIAgentHomeMessageSubmission.swift');
assert(submit.indexOf('offerLocalLabQuery(') < submit.indexOf('coordinator.send('), 'Local queries precede provider routing');
for (const token of ['message.sourceConversationId.isBlank', 'message.deliveryTrace.first?.stage == stage',
  'message.remoteMessageId == marker + $0.rawValue', 'if session.collaborationRoster != nil',
  'draftDigest: AgentTurnReceiptEvidence.hash(question)', 'privateMode: true', 'readOnlyAnalysis: true',
  'sourceTrace: GalaxySSIHealthAgentLab.stage']) assert(intent.includes(token), token);
const history = intent.slice(intent.indexOf('  func openLocalLab('));
assert(!history.includes('launch.supplement'), 'Private follow-up text must not enter history');
assert(!/coordinator\.send|conversationStreamingRequest|appendOutgoing\(question/.test(intent), 'No provider submission or raw question history');
for (const token of ['store.profile.identityFingerprint == launch.owner', 'store.activeAgentConversationId == launch.conversation',
  'snapshot?.policy.allowed == true', '.disabled(!value.policy.allowed)', 'records.annotateLocalLab(',
  'records.scheduleLocalLabRecheck(', 'records.localLabRecheckIsCurrent(', 'note = ""', 'confirmed: true',
  'GalaxySSIHealthAgentLabSheet', 'localLabMeasurements(through: through, once: once']) assert(ui.includes(token), token);
for (const token of ['archive.current.first(where: { $0.id == expected.id }) == expected',
  'archive.localCareFollowUps?[ref.actionID]?.id == token', 'ref.record.revision > 0',
  'GalaxySSIHealthCare.Record(row) == ref.record', 'row.measuredAt <= ref.through']) assert(core.includes(token), token);
for (const token of ['if reminder.labReview != nil { return localLabRecheckIsCurrent', 'labRecord: lab.record.id',
  'if let record = row.labRecord', 'reminder.labReview?.record.id == record']) assert(records.includes(token), token);
assert(read('apps/ios/GalaxySSI/GalaxySSIHealthCareFollowUpDelivery.swift').includes('if let lab = reminder.labReview'), 'Notification opens the linked lab view');
assert(read('apps/ios/GalaxySSI/GalaxySSIHealthCareFollowUpsView.swift').includes('let lab = reminder.labReview'), 'Health Actions renders linked lab reminders');
const strings = read('apps/ios/GalaxySSI/zh-Hans.lproj/Localizable.strings');
const translated = new Map();
for (const match of strings.matchAll(/^"galaxyssi\.health\.local_lab\.([^"\n]+)" = ("(?:[^"\\]|\\.)*");$/gm)) {
  assert(!translated.has(match[1]), 'Duplicate local lab resource: ' + match[1]);
  translated.set(match[1], JSON.parse(match[2]));
}
for (const match of intent.matchAll(/matches\("([a-z_]+)", #"([^"\n]*)"#/g)) {
  assert(translated.has('pattern_' + match[1]), 'Localized pattern missing: ' + match[1]);
  new RegExp(match[2], 'i');
  new RegExp(translated.get('pattern_' + match[1]), 'i');
}
for (const match of ui.matchAll(/\bt\("([a-z_]+)",/g)) assert(translated.has(match[1]), 'Localized UI missing: ' + match[1]);
assert.equal((read('apps/ios/GalaxySSITests/GalaxySSIHealthAgentLabIntentTests.swift').match(/func test/g) || []).length, 8);
console.log('Local lab routing, privacy, UI and reminder source contracts passed; no Swift compilation or XCTest execution.');
