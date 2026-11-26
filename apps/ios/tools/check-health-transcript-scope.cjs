'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const prefix = 'apps/ios/GalaxySSI/';
const baseline = '5d3953ff1aa13a1585b6829fdc49adee09fe464c';
const clean = text => text.replace(/\r\n/g, '\n');
const read = name => clean(fs.readFileSync(path.join(root, prefix + name), 'utf8'));
const old = name => clean(cp.execFileSync('git', ['show', baseline + ':' + prefix + name], { cwd: root, encoding: 'utf8', maxBuffer: 20_000_000 }));
function exactChanges(name, changes) {
  let expected = old(name);
  for (const [before, after] of changes) {
    assert.equal(expected.split(before).length - 1, 1, name + ': unique declared hook');
    expected = expected.replace(before, after);
  }
  const current = name === 'GalaxySSIAgentHomeOutputView.swift'
    ? require('./check-health-legacy-reply-scope.cjs').retainedLegacyHost(read(name)) : read(name);
  assert.equal(current, expected, name + ': unchanged outside declared hooks');
}
exactChanges('GalaxySSIHealthRecords.swift', [[
  '      thread.turns[index].execution?.state = .interrupted\n',
  '      thread.turns[index].execution?.state = .interrupted\n      thread.turns[index].execution?.stoppedAt = now\n'
]]);
exactChanges('GalaxySSIHealthCareTaskRuntime.swift', [[
  '  func cancel(',
  `  func isExecuting(_ approval: GalaxySSIHealthCareDiscussion.Approval) -> Bool {
    guard let handle = handles[identity(approval)] else { return false }
    return !handle.task.isCancelled
  }

  func persistedWorkspaces() -> [String: AgentWorkspace] {
    Dictionary(store.list().map { ($0.workspaceId, $0) }, uniquingKeysWith: { first, _ in first })
  }

  func cancel(`
]]);
exactChanges('GalaxySSIAgentHomeOutputView.swift', [[
  '        }\n      }\n    .environment(\\.agentReplySpeechBlankTap, {',
  `          if let session = activeAgentSession, GalaxySSIHealthCareAgentScope.concernID(session) != nil {
            GalaxySSIHealthCareAgentTranscriptView(
              records: .init(owner: store.profile.identityFingerprint, secrets: store.secrets),
              conversation: session.id, visible: homeVisible)
              .id([store.profile.identityFingerprint, session.id])
          }
        }
      }
    .environment(\\.agentReplySpeechBlankTap, {`
]]);
exactChanges('GalaxySSIAgentTranscriptScrollView.swift', [
  ['  @State private var pinnedToLatest = false\n', '  @State private var pinnedToLatest = false\n  @State private var hasPrivateHealthRows = false\n'],
  ['          if transcriptShowLatestButton, let last = messages.last {', '          if transcriptShowLatestButton && (!messages.isEmpty || hasPrivateHealthRows) {'],
  ['                proxy.scrollTo(last.id, anchor: .bottom)',
    '                if hasPrivateHealthRows { proxy.scrollTo(transcriptTail, anchor: .bottom) }\n                else if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }'],
  ['      .onChange(of: activeAgentConversationID) { _ in\n        scrollEpoch.invalidate()',
    '      .onChange(of: activeAgentConversationID) { _ in\n        scrollEpoch.invalidate()\n        hasPrivateHealthRows = false'],
  ['      .coordinateSpace(name: galaxySSIAgentTranscriptCoordinateSpace)\n',
    `      .coordinateSpace(name: galaxySSIAgentTranscriptCoordinateSpace)
      .onPreferenceChange(GalaxySSIHealthCareTranscriptRevisionKey.self) { value in
        guard scene == .active, value.conversation == activeAgentConversationID else {
          hasPrivateHealthRows = false
          return
        }
        hasPrivateHealthRows = value.hasRows
        guard value.hasRows else { return }
        guard transcriptAutoFollow, !draggingTranscript else {
          transcriptShowLatestButton = true
          return
        }
        let ticket = scrollEpoch.revision
        DispatchQueue.main.async {
          guard scrollEpoch.accepts(ticket), scene == .active, hasPrivateHealthRows,
                value.conversation == activeAgentConversationID, transcriptAutoFollow else { return }
          proxy.scrollTo(transcriptTail, anchor: .bottom)
        }
      }
`],
  ['      transcriptShowLatestButton = !messages.isEmpty\n', '      transcriptShowLatestButton = !messages.isEmpty || hasPrivateHealthRows\n']
]);
for (const name of ['AgentTaskSupervisor.swift', 'AgentModelToolLoop.swift', 'GalaxySSIAgentTranscriptMessagesView.swift',
  'GalaxySSIAgentHomeState.swift', 'GalaxySSIAgentHomeTranscriptView.swift', 'GalaxySSIServices.swift']) {
  const current = name === 'GalaxySSIAgentTranscriptMessagesView.swift'
    ? require('./check-health-legacy-reply-scope.cjs').retainedLegacyMessages(read(name)) : read(name);
  assert.equal(current, old(name), name + ': no changes outside declared private Health reply filtering');
}
const projection = read('GalaxySSIHealthCareAgentTranscriptProjection.swift');
for (const invariant of ['thread.agentConversationID == conversation', 'execution.agentConversationID == conversation',
  'approval.owner == owner', 'approval.threadID == thread.id', 'approval.concernID == thread.concernID',
  'approval.id == turn.id', 'approval.question == turn.question', 'approval.destinationDigest == turn.destination',
  'value.workspaceId == identity', 'value.taskId == identity', 'value.sessionId == thread.id.uuidString',
  'value.conversationId == conversation', 'approval.isCurrent(at: now) && isExecuting(approval)',
  'execution.stoppedAt ?? execution.receivedAt', 'turn.hasInterruptedReply', 'turn.retainedAnswer']) {
  assert(projection.includes(invariant), 'Exact projection fence: ' + invariant);
}
assert.match(projection, /func running\(at now: Date\) -> Bool \{ stoppedAt == nil && now < deadline \}/);
assert.doesNotMatch(projection, /URLSession|ChatMessage|UserDefaults|persist\(|\.response\b|providerPayload|toolCalls/);
const view = read('GalaxySSIHealthCareAgentTranscriptView.swift');
for (const invariant of ['scene == .active', 'UIApplication.shared.isProtectedDataAvailable', 'store.canReadAgentTranscript',
  'records.owner == store.profile.identityFingerprint', 'store.activeAgentConversationId == conversation',
  'GalaxySSIHealthCareAgentScope.concern(session, in: archive)', 'runtime.persistedWorkspaces()', 'runtime.isExecuting($0)',
  'profileInputsChanged', 'recordsChanged', 'protectedDataWillBecomeUnavailableNotification', 'galaxySSIRuntimePlaintextWillClear',
  'target.matches(archive)', 'reply(row.reply)', 'Text(verbatim: row.question)', 'clock.running(at: context.date)']) {
  assert(view.includes(invariant), 'Visible scope/lifecycle fence: ' + invariant);
}
assert.match(view, /visible && scene == \.active/);
assert.match(view, /onChange\(of: visible\) \{ if \$0 \{ refresh\(\) \} else \{ clear\(\) \} \}/);
assert.doesNotMatch(view, /appendMessage|persist\(|URLSession|responseBytes|\.send\(|providerPayload|\.response\b|UserDefaults|SceneStorage/);
const recovery = read('GalaxySSIHealthCareDiscussionRecovery.swift');
assert.match(recovery, /var stoppedAt: Date\?/);
assert.match(recovery, /if execution\.stoppedAt == nil \{ execution\.stoppedAt = now \}/);
assert.match(recovery, /guard now\.timeIntervalSinceReferenceDate\.isFinite, now >= execution\.startedAt/);
const scroll = read('GalaxySSIAgentTranscriptScrollView.swift');
assert.match(scroll, /onPreferenceChange\(GalaxySSIHealthCareTranscriptRevisionKey\.self\)/);
assert.match(scroll, /guard transcriptAutoFollow, !draggingTranscript/);
assert.match(scroll, /scrollEpoch\.accepts\(ticket\), scene == \.active, hasPrivateHealthRows/);
assert.match(scroll, /value\.conversation == activeAgentConversationID, transcriptAutoFollow/);
assert.match(scroll, /transcriptShowLatestButton && \(!messages\.isEmpty \|\| hasPrivateHealthRows\)/);
const tests = clean(fs.readFileSync(path.join(root, 'apps/ios/GalaxySSITests/GalaxySSIHealthCareAgentTranscriptTests.swift'), 'utf8'));
assert.equal((tests.match(/func test/g) || []).length, 9);
console.log('Health private transcript source scope passed (not native execution or typechecking).');
