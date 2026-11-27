// Source contracts only, not native navigation, encryption, gestures or model acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '4c876a62035990a70a69a453edf2503408d96911';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function has(name, tokens) { const s = read(app + name + '.swift'); for (const t of tokens) assert(s.includes(t), name + ': ' + t); return s; }
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function validate() {
  const discussion = has('GalaxySSIHealthAtlasDiscussion', ['maximumQuestionUTF16 = 500', 'return "body-atlas:" + itemID',
    'session.globalTopicKey == topic', 'session.createdByAgent', 'session.status == .active', '!session.privateMode',
    '!session.trackingPaused', 'session.mergedIntoConversationId.isBlank', 'result.utf16.count <= 9_000',
    'result.utf8.count <= 32_000', 'saved.owner == owner', 'saved.topics.count <= 2_048',
    'GalaxySSIEncryptedUserDefaultsStore.load(', 'GalaxySSIEncryptedUserDefaultsStore.write(',
    'store.agentConversationDatabase.read(id)', 'store.createAgentConversation(title: title, globalTopicKey: topic)',
    'store.deleteAgentSession(id: saved.id)', 'GalaxySSIHealthAtlasLandmarks.list(plate, atlas: atlas)',
    'step == 0', 'landmarks[step - 1].title']);
  assert(!discussion.includes('readAll(')); assert(!discussion.includes('.title =='));
  const handoff = has('GalaxySSIHealthAtlasAgentHandoff', ['let topic: String', '.sheet(isPresented: isPreviewPresented, onDismiss: presentDiscussion)',
    'TextField(t("question_hint"), text: $userQuestion)', 'GalaxySSIHealthAtlasDiscussion.limitQuestion(value)',
    'previewGeneration == store.runtimePlaintextGeneration', 'question: userQuestion, language: language',
    'itemID: entry?.id ?? "whole"', 'topic: session.globalTopicKey', 'ready.owner == store.profile.identityFingerprint',
    'ready.generation == store.runtimePlaintextGeneration', 'GalaxySSIHealthAtlasDiscussion.reusable(fresh, topic:',
    'store.runtimePlaintextGeneration == discussionGeneration', 'store.profile.identityFingerprint == discussionOwner',
    'store.activeAgentConversationId == discussionConversation', 'onDiscussionReturn?()',
    'GalaxySSIHealthAtlasDiscussion.reusable(session, topic: request.topic)', 'attachments: []',
    'requiredAgentConversationID: request.conversation']);
  assert(!handoff.includes('asyncAfter')); assert(!handoff.includes('requestAuthorization'));
  assert(handoff.indexOf('onPreviewStateChange?(true)') < handoff.indexOf('let question = GalaxySSIHealthAtlasQuestion.build'));
  const a = 'enum GalaxySSIHealthAtlasQuestion {\n', b = '\n@MainActor\nstruct GalaxySSIHealthAtlasAsk';
  const previous = section(old(app + 'GalaxySSIHealthAtlasAgentHandoff.swift'), a, b);
  const current = section(handoff, a, b);
  const baseBody = current.slice(current.indexOf('  private static func base(')).replace('  private static func base(', '  static func build(');
  assert.equal(a + baseBody, previous, 'Existing educational/Values exclusion and model context remain exact');
  const state = has('GalaxySSIHealthAtlasState', ['var snapshot = functionSnapshot(entry, depth: depth)',
    'snapshot.artworkView = binding(entry).wrappedValue.artworkView', 'func questionStructurePosition(',
    'GalaxySSIHealthAtlasAsk(atlas: atlas, entry: nil, selection: .init()']);
  assert(state.includes('structureSteps.position(owner: entry?.id ?? ""'));
  for (const name of ['Detail', 'Research', 'StandaloneModels']) {
    has('GalaxySSIHealthAtlas' + name, ['agentReturnOffset = scrollMemory.offset; state.playback.pause()',
      'onDiscussionReturn: { scrollMemory.restore(agentReturnOffset) }']);
  }
  const parity = read(app + 'GalaxySSIAndroidParityUI.swift');
  assert.equal(parity.replace('.navigationBarHidden(atlasHandoffToken == nil)', '.navigationBarHidden(true)'), old(app + 'GalaxySSIAndroidParityUI.swift'));
  const store = read(app + 'GalaxySSIStore.swift');
  assert.equal(store.replace('AgentContinuousEvalStore.defaultKey,\n      GalaxySSIHealthAtlasDiscussion.storageKey', 'AgentContinuousEvalStore.defaultKey'), old(app + 'GalaxySSIStore.swift'));
  const values = '@MainActor\nstruct GalaxySSIHealthAtlasValues';
  const detail = read(app + 'GalaxySSIHealthAtlasDetail.swift'), oldDetail = old(app + 'GalaxySSIHealthAtlasDetail.swift');
  assert(detail.includes(values) && oldDetail.includes(values));
  assert.equal(detail.slice(detail.indexOf(values)), oldDetail.slice(oldDetail.indexOf(values)), 'Personal Values UI unchanged');
  for (const name of ['GalaxySSIHealthAtlasAgentContext', 'GalaxySSIHealthAtlasFunctionPlayer', 'GalaxySSIHealthAtlasChapterClock',
    'GalaxySSIHealthCareDiscussion', 'GalaxySSIViews', 'GalaxySSIEncryptedUserDefaultsStore']) {
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name + ' unchanged');
  }
  for (const locale of ['en', 'zh-Hans']) for (const table of ['BodyAtlas', 'AtlasFunction']) {
    const s = read(app + locale + '.lproj/' + table + '.strings');
    for (const key of ['health_atlas_ask_ready', 'health_atlas_question_hint', 'health_atlas_user_question']) {
      assert.equal(s.split('"' + key + '" =').length, 2);
    }
    assert(s.includes('%@')); assert(!s.includes('Open this question in a new conversation?'));
  }
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['GalaxySSIHealthAtlasDiscussion', 'GalaxySSIHealthAtlasDiscussionTests']) {
    assert.equal((project.match(new RegExp(name + '\\.swift in Sources \\*\\/', 'g')) || []).length, 2);
    assert.equal((project.match(new RegExp('path = ' + name + '\\.swift;', 'g')) || []).length, 1);
  }
  assert.equal((read('apps/ios/GalaxySSITests/GalaxySSIHealthAtlasDiscussionTests.swift').match(/func test/g) || []).length, 10);
  console.log('Atlas object-owned encrypted reuse, reviewed questions, structure/function snapshot wiring, one-use dispatch and Back/scroll source contracts passed; ten authored Swift fixtures not executed.');
}
module.exports = {validate};
if (require.main === module) validate();
