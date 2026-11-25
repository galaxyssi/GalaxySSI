'use strict';

// Source-scope assertions only; this does not compile or execute the iOS app.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const baseline = '953036acd22d83f16771937584ef83f2fa3c27a4';
const prefix = 'apps/ios/GalaxySSI/';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', `${baseline}:${file}`], { cwd: root, encoding: 'utf8' }));

function exactChanges(name, replacements) {
  const file = prefix + name;
  let expected = old(file);
  for (const [before, after] of replacements) {
    assert.equal(expected.split(before).length - 1, 1, `${name}: unique declared edit`);
    expected = expected.replace(before, after);
  }
  assert.equal(read(file), expected, `${name}: unrelated behavior retained`);
}

exactChanges('GalaxySSIHealthCareHistoryTool.swift', [
  ['struct Output: Equatable', 'struct Output: Codable, Equatable'],
  ['struct Approval {', 'struct Approval: Codable, Equatable {']
]);
exactChanges('GalaxySSIHealthCareFeedbackTool.swift', [
  ['struct Cursor: Equatable', 'struct Cursor: Codable, Equatable']
]);
exactChanges('GalaxySSIHealthCareSeries.swift', [
  ['struct Cursor: Equatable', 'struct Cursor: Codable, Equatable'],
  ['struct Binding: Equatable', 'struct Binding: Codable, Equatable']
]);
exactChanges('GalaxySSIHealthCareQuestions.swift', [
  ['struct Page {', 'struct Page: Codable, Equatable {'],
  ['struct Cursor {', 'struct Cursor: Codable, Equatable {'],
  ['private let token = UUID()', 'private let token: UUID'],
  ['self.after = after\n', 'self.after = after\n      self.token = UUID()\n']
]);
exactChanges('GalaxySSIHealthCareResearchHandoff.swift', [
  ['struct Handoff: Equatable', 'struct Handoff: Codable, Equatable']
]);
exactChanges('GalaxySSIHealthCareResearchControls.swift', [
  ['SHA256.hash(data: Data(key.utf8)) == approval.credentialDigest',
    'Data(SHA256.hash(data: Data(key.utf8))) == approval.credentialDigest']
]);
exactChanges('GalaxySSIHealthVisitJournalRead.swift', [
  ['destination: .cloud(model: model, endpoint: endpoint, credential: credential)',
    'destination: .cloud(model: model, endpoint: endpoint, credential: Data(credential))']
]);
exactChanges('FileAgentWorkspaceStore.swift', [
  ['private let writeFile: (Data, URL) throws -> Void',
    'private let writeFile: (Data, URL) throws -> Void\n  private let readFile: (URL) throws -> Data'],
  ['    writeFile: @escaping (Data, URL) throws -> Void',
    '    readFile: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },\n    writeFile: @escaping (Data, URL) throws -> Void'],
  ['self.writeFile = writeFile', 'self.writeFile = writeFile\n    self.readFile = readFile'],
  ['do { data = try Data(contentsOf: fileURL) }', 'do { data = try readFile(fileURL) }']
]);
for (const name of ['GalaxySSIHealthScopedReadTransport.swift', 'GalaxySSIHealthAnalysis.swift',
  'GalaxySSIHealthFollowUp.swift', 'GalaxySSIServices.swift', 'AgentTaskSupervisor.swift']) {
  const current = name === 'GalaxySSIHealthScopedReadTransport.swift'
    ? require('./check-health-discussion-rounds-scope.cjs').retainedScopedReadTransport(read(prefix + name))
    : read(prefix + name);
  assert.equal(current, old(prefix + name), `${name}: behavior retained outside declared hooks`);
}

const recovery = read(prefix + 'GalaxySSIHealthCareDiscussionRecovery.swift');
assert.match(recovery, /approval\.research == nil, approval\.model != nil/);
assert.match(recovery, /approval\.credentialDigest\?\.count == 32/);
assert.match(recovery, /execution\.state == \.prepared/);
assert.match(recovery, /execution\.response == response/);
assert.match(recovery, /response\.count <= 65_536/);
assert.match(recovery, /thread\.agentConversationID == execution\.agentConversationID/);
assert.match(recovery, /execution\.approval == approval/);
assert.match(recovery, /execution\.state == \.received/);
assert.match(recovery, /approval\.isCurrent\(at: received\)/);
assert.doesNotMatch(recovery, /URLSession|URLRequest|responseBytes|await |Task\s*\{/);
const view = read(prefix + 'GalaxySSIHealthCareDiscussionView.swift');
assert.match(view, /beginLocalCareDiscussionTurn\(review, persistExecution: true\)/);
assert.match(view, /dispatchLocalCareDiscussionTurn\(review\)[\s\S]*?responseBytes\(request/);
assert.match(view, /retainLocalCareDiscussionResponse\(review, response: bytes\)[\s\S]*?applySavedLocalCareDiscussionReply\(review\)/);
const runtime = read(prefix + 'GalaxySSIHealthCareTaskRuntime.swift');
assert.match(view, /runtime\.submit\(review\)/);
assert.match(view, /runtime\.restore\(review, mayApply: \{ active\?\.id == review\.id && currentRoute\(review\) != nil \}, resumeRound:/);
assert.match(runtime, /current\.state == \.received, mayApply\(\)/);
assert.match(runtime, /execution\.agentConversationID == thread\.agentConversationID/);
assert.match(runtime, /execution\.approval == approval/);
assert.match(runtime, /supervisor\.submit\(workspace: workspace, priority: \.foreground\)/);
assert.match(runtime, /supervisor\.resume\(workspaceId: id, priority: \.foreground\)/);
assert.match(runtime, /if let active = handles\[id\] \{ await active\.join\(\) \}/);
assert.match(runtime, /persisted\.cancellationRequested \|\| persisted\.status == \.cancelled/);
assert.match(runtime, /execution\(approval\)\.state == \.applied/);
assert.doesNotMatch(runtime, /URLSession|URLRequest|responseBytes|apiKey|memoryObserver:|\.question|\.payload|\.providerPayload/);
assert.match(view, /taskHandle\?\.task\.cancel\(\)/);
assert.match(view, /runtime\.cancel\(review\)/);
assert.match(view, /if !admitted[\s\S]*?health_discussion_task_not_admitted/);
assert.match(view, /await handle\.join\(\)[\s\S]*?AgentDataDisclosureLedger\.update/);
const taskStore = read(prefix + 'GalaxySSIHealthCareTaskStore.swift');
assert.match(taskStore, /AES\.GCM\.open\([\s\S]*?key\(create: false\), authenticating: aad/);
assert.match(taskStore, /AES\.GCM\.seal\(data,[\s\S]*?authenticating: aad/);
assert.match(taskStore, /\[\.atomic, \.completeFileProtection\]/);
assert.match(taskStore, /isExcludedFromBackup = true/);
assert.match(taskStore, /galaxyssi\.health\.discussion\.tasks\.v1:/);
assert.match(taskStore, /health-discussion-tasks/);
assert.match(view, /blockedDestinationIds\(\)\.contains\(contact\.id\)/);
assert.match(view, /private func cancelRequest\(\)[\s\S]*?interruptLocalCareDiscussionExecution/);
const records = read(prefix + 'GalaxySSIHealthRecords.swift');
assert.equal((records.match(/execution\?\.state = \.applied/g) || []).length, 4);
assert.match(records, /allowTerminalExecution \|\| \(execution\.state != \.interrupted && execution\.state != \.applied\)/);
const fixtures = read('apps/ios/GalaxySSITests/GalaxySSIHealthCareDiscussionRecoveryTests.swift');
assert.equal((fixtures.match(/func test/g) || []).length, 6);
const taskFixtures = read('apps/ios/GalaxySSITests/GalaxySSIHealthCareTaskRuntimeTests.swift');
assert.equal((taskFixtures.match(/func test/g) || []).length, 9);
console.log('Health discussion recovery source scope passed (not native execution or typechecking).');
