'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const clean = text => text.replace(/\r\n/g, '\n');
const prefix = 'apps/ios/GalaxySSI/';
const read = name => clean(fs.readFileSync(path.join(root, prefix + name), 'utf8'));

function retainedHealthComposerGuard(input) {
  const hook = `    if contact.id == "hermes", let session = store.agentSession(id: store.activeAgentConversationId),
       GalaxySSIHealthCareAgentScope.requiresScopedSubmission(session) {
      lastError = GalaxySSILocalization.string("galaxyssi.health.discussion.preview",
        fallback: "Review data before sending", language: store.languagePolicy.interfaceLanguage)
      return false
    }
`;
  const source = clean(input);
  assert.equal(source.split(hook).length - 1, 1, 'Unique early Health generic-send guard');
  return source.replace(hook, '');
}
module.exports = { retainedHealthComposerGuard };

if (require.main === module) {
  const services = read('GalaxySSIServices.swift');
  const baseline = clean(cp.execFileSync('git', ['show', '6cdd293c9491f724302bee1601390cf4eb730089:' + prefix + 'GalaxySSIServices.swift'],
    { cwd: root, encoding: 'utf8' }));
  assert.equal(retainedHealthComposerGuard(services), baseline, 'Ordinary send flow unchanged outside the fail-closed guard');
  const sendFlow = services.slice(services.indexOf('  func send(\n'));
  assert(sendFlow.indexOf('requiresScopedSubmission(session)') < sendFlow.indexOf('let callableTargets ='), 'Guard before target selection');
  const send = read('GalaxySSIAgentHomeMessageSubmission.swift');
  const guardIndex = send.indexOf('GalaxySSIHealthCareAgentScope.requiresScopedSubmission(session)');
  for (const boundary of ['coordinator.updateAgentScreenContext(', 'AgentDoorAccessConfiguration.enabled(', 'coordinator.send(']) {
    assert(guardIndex >= 0 && guardIndex < send.indexOf(boundary), 'Review before ' + boundary);
  }
  assert.match(send, /outgoingAttachments\.isEmpty/);
  assert.match(send, /healthCareSubmission = try \.init/);
  assert.match(send, /conversation: session, question: cleanDraft/);
  assert.match(send, /catch \{[\s\S]*?health\.discussion\.unavailable[\s\S]*?return\n    \}/);
  const scope = read('GalaxySSIHealthCareAgentScope.swift');
  assert.match(scope, /func requiresScopedSubmission[\s\S]*?conversation\.globalTopicKey\.hasPrefix\(prefix\)/);
  assert.match(scope, /thread\.agentConversationID == conversation\.id/);
  assert.match(scope, /question\.utf8\.count <= 2_048/);
  assert.match(scope, /archive\.localCareDiscussions\?\[concern\.uuidString\]\?\.id == thread/);
  assert.match(scope, /\.permission\(in: archive\) == permission/);
  assert.match(scope, /initialQuestion: launch\.question/);
  assert.match(scope, /onChange\(of: scene\)[^\n]*submission = nil/);
  assert.match(scope, /onChange\(of: store\.activeAgentConversationId\)[^\n]*submission = nil/);
  assert.match(scope, /onChange\(of: store\.profile\.identityFingerprint\)[^\n]*submission = nil/);
  assert.match(scope, /protectedDataWillBecomeUnavailableNotification/);
  assert.doesNotMatch(scope, /UserDefaults|SceneStorage|URLSession|responseBytes|beginLocalCareDiscussionTurn|providerPayload/);
  const view = read('GalaxySSIHealthCareDiscussionView.swift');
  assert.match(view, /_question = State\(initialValue: initialQuestion\)/);
  assert.match(read('GalaxySSIAndroidParityUI.swift'), /GalaxySSIHealthCareComposerSheet\(submission: \$healthCareSubmission\)/);
  console.log('Health composer source scope passed (not native execution or typechecking).');
}
