'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const app = 'apps/ios/GalaxySSI/';
const base = 'fd7eebb9165217e0654289d8f522719f9e51cf2b';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', `${base}:${f}`], {
  cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024
}).replace(/\r\n/g, '\n');
const has = (s, tokens) => tokens.forEach(t => assert.ok(s.includes(t), `Missing source wiring: ${t}`));
const model = read(app + 'GalaxySSIHealthAnswerBasis.swift');
has(model, ['struct Grant: Codable, Equatable', 'let binding: GalaxySSIHealthCareEvidence.Binding',
  'let conversation: String', 'let profileScope:', 'let profileEpoch:', 'let related:', 'let researchAuthorization:',
  'approvalLifetime', 'thread.agentConversationID', 'let record, record.revision > 0',
  'concern.assessment.record', 'comparison.kind != .recordCorrection', 'approval.history?.recent.payload',
  'approval.relatedMeasurements[name] != nil', 'approval.relatedPayload["selected"]',
  'context.record == concern.assessment.record', 'payload["saved_profile"]',
  'receipt.binding == grant.binding', 'grant.reviewedAt <= receipt.retrievedAt',
  'receipt.observedAt <= now', 'PublicSource.allCases.contains', 'receipt.contentHash.range', 'receipts.prefix(3)']);
assert.ok(!/URLSession|fetch\(|request\(|retainedAnswer|tool.arguments|modelValue/.test(model));
const names = read(app + 'GalaxySSIHealthAnswerBasisNames.swift');
has(names, ['originals.withRestoreLease', 'originals.reconcileRestores',
  '$0.id == ref.id && $0.revision == ref.revision', '$0.metric == metric && $0.measuredAt == at && !$0.deleted',
  'archive.reportEvidence', '$0.original == file.id && $0.sha256 == file.sha256',
  'archive.reviewOnlyReportOriginals', 'originals.visitOriginal(id: file.id, lease: lease)',
  'original.sha256 == file.sha256', 'row.files.prefix(8)', 'original.name.prefix(180)']);
assert.ok(!names.includes('originals.read('), 'Do not load original file bodies for labels');
const records = read(app + 'GalaxySSIHealthRecords.swift');
has(records, ['answerBasis: GalaxySSIHealthAnswerBasis.capture(approval, concern: concern, thread: thread, archive: archive)',
  'saved.retainedAnswer?.isBlank == false', 'grant.binding.owner == owner', 'grant.binding.thread == thread.id',
  'grant.binding.turn == turn', 'grant.binding.concern == thread.concernID', 'saved.destination == grant.binding.destination',
  'now >= grant.reviewedAt, now < grant.until', 'archive.healthOnlinePermission == grant.binding.onlinePermission',
  'archive.matchesLocalCarePermission(grant.binding.carePermission)', 'concern.revision == grant.binding.revision',
  'localCareProfileIsCurrent(grant.profileScope)', 'GalaxySSIHealthCareRelatedContext.current(grant.related',
  'grant.researchAuthorization.map', 'expanded: false, now: now)?.sources == rows']);
let preserved = records.replace(/  func localCareAnswerBasis\([\s\S]*?(?=  func validateLocalCareDiscussionTurn\()/, '');
preserved = preserved.replace(',\n      answerBasis: GalaxySSIHealthAnswerBasis.capture(approval, concern: concern, thread: thread, archive: archive)', '');
assert.equal(preserved, old(app + 'GalaxySSIHealthRecords.swift'), 'Retain all existing authority, write and transport checks');
const row = read(app + 'GalaxySSIHealthAnswerBasisRow.swift');
has(row, ['mounted && visible && scene == .active', 'UIApplication.shared.isProtectedDataAvailable',
  'records.owner == store.profile.identityFingerprint', 'store.activeAgentConversationId == conversation',
  'GalaxySSIHealthCareAgentScope.concernID($0)', 'refresh(open: !expanded)', 'records.localCareAnswerBasis(',
  'Date() < value.until', 'onDisappear { mounted = false; clear() }', 'recordsChanged', 'profileInputsChanged',
  'GalaxySSIHealthOriginalStore.indexChanged', 'significantTimeChangeNotification',
  'protectedDataWillBecomeUnavailableNotification', 'galaxySSIRuntimePlaintextWillClear',
  '.task(id: display?.until)', 'Task.sleep', 'clear()']);
const transcript = read(app + 'GalaxySSIHealthCareAgentTranscriptView.swift');
const insertion = '            if case .answer = row.reply {\n' +
  '              GalaxySSIHealthAnswerBasisRow(records: records, conversation: conversation, turn: row.id, visible: canRead)\n' +
  '            }\n';
assert.equal(transcript.replace(insertion, ''), old(app + 'GalaxySSIHealthCareAgentTranscriptView.swift'));
for (const f of ['GalaxySSIAgentTranscriptMessagesView.swift', 'GalaxySSIHealthOriginalStore.swift',
  'GalaxySSIHealthCareEvidence.swift', 'GalaxySSIHealthCareNativeToolSession.swift',
  'GalaxySSIHealthCareHistoryTool.swift', 'GalaxySSIHealthCareAgentScope.swift']) {
  assert.equal(read(app + f), old(app + f), `Keep unrelated surface/authority unchanged: ${f}`);
}
const tests = read('apps/ios/GalaxySSITests/GalaxySSIHealthAnswerBasisTests.swift');
assert.equal((tests.match(/  func test\w+\(/g) || []).length, 10);
has(tests, ['testOnlyBoundApprovedTurnsProjectMetadataNotQuestionOrAnswerCitations',
  'testExpiryAndEitherConsentRevocationHideAlreadySavedSources', 'testMissingOrReviewOnlyOriginalDoesNotRevealItsFilename',
  'testStoredBasisIsEncryptedAndContextDoesNotInferFastingDuration']);
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const f of ['GalaxySSIHealthAnswerBasis.swift', 'GalaxySSIHealthAnswerBasisNames.swift',
  'GalaxySSIHealthAnswerBasisRow.swift', 'GalaxySSIHealthAnswerBasisTests.swift']) {
  assert.equal(project.split(`/* ${f} in Sources */`).length - 1, 2);
  assert.equal(project.split(`path = ${f};`).length - 1, 1);
}
const strings = read(app + 'zh-Hans.lproj/Localizable.strings');
for (const k of ['count', 'expanded', 'collapsed', 'scope', 'measurement', 'context', 'profile', 'guideline', 'target', 'retrieved']) {
  assert.equal(strings.split(`"galaxyssi.health.answer_basis.${k}" =`).length - 1, 1);
}
console.log('Health-answer basis source wiring checked: approved encrypted turn metadata, exact local file identity, consent/expiry clearing and unchanged authority. Ten authored Swift methods are not native acceptance.');
