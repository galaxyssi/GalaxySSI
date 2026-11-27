// Source wiring and retention checks only, not Swift execution or device evidence.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const app = 'apps/ios/GalaxySSI/';
const base = '27f2e834720486e4e09a75734eb4f53ce0209961';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function has(name, tokens) {
  const source = read(app + name + '.swift');
  for (const token of tokens) assert(source.includes(token), name + ': ' + token);
  return source;
}
const draft = has('VoiceMessageDraft', ['@MainActor', 'now() < draft.expires', 'expires: now() + 180',
  'text.utf16.count <= 10_000', 'people.count <= 64', 'value.revision == revision',
  'text: value.text', 'value.people[spokenOption - 1].id == id', 'speaker.turn != value.speaker.turn',
  'phase: .dispatching', 'value.text = ""; value.people = []', '"dispatch_uncertain"',
  'existing.speaker.turn == speaker.turn', '"delivery_verified": .bool(false)', '"recall_supported": .bool(false)']);
for (const token of ['UserDefaults', 'Keychain', 'Task {', 'URLSession']) assert(!draft.includes(token), token);
const tools = has('VoiceMessageNativeTools', ['voiceAppContexts.spoken(anchor)', 'read(key)?.voiceInput == true',
  'voiceAppContexts.hasObservedContact(contactID, anchor: anchor)', 'caseInsensitiveCompare(name) == .orderedSame',
  'candidates.count <= 64', 'spokenOption: speech.choice', 'confirmed: speech.confirmed',
  'voiceMessageRecipientBinding(contact, store: store) == claim.recipient.route',
  'enqueueConfirmedVoiceRecipient(claim.text', 'draft.finish(claim, result:', 'try invocation.checkpoint()']);
assert(tools.indexOf('draft.claim(') < tools.indexOf('enqueueConfirmedVoiceRecipient('));
assert(!tools.includes('input["confirmed"]'));
assert(!tools.includes('input["spoken_option"]'));
const native = has('VoiceAppNativeTools', ['case voiceMessage = "voice_message"',
  '[.sendMessage, .voiceMessage].contains(operation) ? .high',
  'idempotency: operation.changesApp ? .idempotencyKeyRequired',
  'AgentNativeConsentRequirement(id: sendConsent', 'AgentNativeConsentRequirement(id: contactsConsent',
  'session.status == .active, !session.privateMode, !session.trackingPaused',
  'voiceAppContexts.isForegroundOwner(anchor)', 'legacy: true']);
assert(!native.includes('return enqueueVoicePeerText('), 'Legacy voice tool must prepare, not send');
has('VoiceAppContext', ['speechEvidence.removeAll()', 'messageDraft.clear()', 'draftWindow != navigationOwner',
  'anchor.draftSession == draftSession', 'if let anchor, anchor.owner != activeOwner { return }',
  'if !preserveDraft { clearMessageDraft() }']);
has('GalaxySSIAgentHomeVoiceActions', ['if let spoken = submission.spokenText', 'captureSpoken(spoken',
  'invalidateVoiceAppAnchor(preserveDraft: true)']);
has('GalaxySSIVoiceTabView', ['spokenText: submission.spokenText', 'if let spokenText',
  'onCancel: { invalidateVoiceAppContext() }', 'invalidateVoiceAppContext(preserveDraft: true)']);
has('GalaxySSIAgentHoldToTalkController', ['spokenText: correctionReview?.diff.fastText ?? cleanText']);
has('GalaxySSIVoiceWakeController', ['onWakeCommand: @escaping (GalaxySSIVoiceTranscriptSubmission) -> Void',
  'spokenText: review?.diff.fastText ?? commandText']);
has('VoiceTranscriptCorrectionModels', ['spokenText: String? = nil', 'self.spokenText = spokenText']);
has('AgentTurnReceipt', ['var voiceInput: Bool?']);
has('AgentTurnReceiptStore', ['if $0.voiceInput == nil { $0.voiceInput = voice }']);
const services = has('GalaxySSIServices', ['recordInputOrigin(key, voice: voiceAppAnchor != nil || !voiceSessionId.isEmpty)',
  'if isPhoneContact(contact) { return enqueueVoicePeerText(',
  'runtime.enqueueDirectPeerText(messageId: source, contactId: contactID)',
  'let wire = try linkWirePayload(payload, link: link)', 'deliveryStore.enqueueConfirmedVoiceText(',
  'GalaxySSISignalEngine.isAvailable else']);
function section(s, start, end) { return s.slice(s.indexOf(start), s.indexOf(end, s.indexOf(start))); }
assert.equal(section(services, '  func enqueueVoicePeerText(', '  func enqueueConfirmedVoiceRecipient('),
  section(old(app + 'GalaxySSIServices.swift'), '  func enqueueVoicePeerText(', '  private func voicePeerTextReceipt('),
  'Existing encrypted phone transport preserved exactly');
for (const name of ['AgentNativeToolExecutionModels', 'AgentNativeToolCore', 'GalaxySSILinkReliability',
  'GalaxySSIEncryptedUserDefaultsStore', 'MqttBusinessTransportRuntime', 'GalaxySSISignalEngine']) {
  assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name + ' retained');
}
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['VoiceMessageDraft', 'VoiceMessageNativeTools', 'VoiceMessageSpeechEvidence', 'VoiceMessageDraftTests']) {
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' sources');
}
const strings = read(app + 'zh-Hans.lproj/Localizable.strings');
for (const key of ['confirmation_phrases', 'choice_ordinals', 'choice_prefixes', 'choice_suffixes']) {
  const line = strings.split('\n').find(line => line.startsWith('"galaxyssi.voice_message.' + key + '"'));
  assert(line, key);
  const value = JSON.parse(line.slice(line.indexOf(' = ') + 3).replace(/;$/, ''));
  assert(Array.isArray(JSON.parse(value)), key + ' valid resource JSON');
}
for (const f of cp.execFileSync('git', ['diff', '--name-only', base], {cwd: root, encoding: 'utf8'}).trim().split('\n').filter(Boolean)) {
  if (!f.startsWith(app) || f.includes('.lproj/')) continue;
  const additions = cp.execFileSync('git', ['diff', '--unified=0', base, '--', f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024})
    .split('\n').filter(l => l.startsWith('+') && !l.startsWith('+++')).join('\n');
  assert(!/\p{Script=Han}/u.test(additions), f + ': CJK belongs in localization resources');
}
console.log('iOS voice message draft source contracts passed (no native execution).');
