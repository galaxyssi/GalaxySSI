// Retained-source contracts, not native/SQLite/background execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), base = 'a16f12311fa4ed70f576c347680a173f8f356fea';
const app = 'apps/ios/GalaxySSI/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const runtimeFile = app + 'AgentIOSOriginalPageArchiveRuntime.swift', storeFile = app + 'AgentIOSOriginalPageArchiveStore.swift';
const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
function section(source, start, end) { const a = source.indexOf(start), b = source.indexOf(end, a + start.length); assert(a >= 0 && b > a, start); return source.slice(a, b); }
function retained(file, source) {
  if (file === project) return source.split('\n').filter(l => !/AgentIOSOriginalPageArchiveOwner(?:Tests)?\.swift/.test(l)).join('\n');
  if (file === storeFile) return source
    .replace('  private let cipher: GalaxySSIAttachmentAtRestCipher\n', '  private let cipher: GalaxySSILocalAttachmentStoring\n')
    .replace('       cipher: GalaxySSIAttachmentAtRestCipher =', '       cipher: GalaxySSILocalAttachmentStoring =')
    .replace('    let encrypted = try cipher.encrypt(data, purpose: purpose(id, ext))\n    try encrypted.write(to: file(id, ext), options: [.atomic, .completeFileProtection])',
      '    try cipher.write(data, to: file(id, ext), purpose: purpose(id, ext))');
  if (file !== runtimeFile || !source.includes('  nonisolated static func prepare(')) return source;
  const original = old(runtimeFile);
  const worker = section(original, '        let worker = Task.detached(priority: .utility) { () throws -> Data in\n', '        do {');
  source = source.replace('        let worker = Task.detached(priority: .utility) { () throws -> Data in\n          try Self.prepare(job: job, queue: queue)\n        }\n', worker);
  source = source.replace(section(source, '  nonisolated static func prepare(', '  nonisolated static func next('), '')
    .replace('  nonisolated static func next(', '  nonisolated private static func next(')
    .replace('    if AgentIOSOriginalPageArchiveBackground.yieldToForeground(self) { return }\n', '')
    .replace('    AgentIOSOriginalPageArchiveBackground.ownerChanged()\n', '')
    .replace('  @MainActor private static var coldRun: (id: UUID, work: Task<Bool, Never>, job: AgentIOSOriginalPageArchiveStore.Job?)?\n', '')
    .replace('    coldRun?.work.cancel()\n', '')
    .replace('        let result = await readOnlySlice()',
      '        guard let runtime else { schedule(pending: true); completion.finish(success: false, pending: nil); return }\n        let result = await runtime.backgroundSlice()');
  source = source.replace(section(source, '  func readOnlyOwner()', '  func invalidate()'), '');
  const cold = source.indexOf('\n  @MainActor static func ownerChanged()');
  assert(cold > 0);
  return source.slice(0, cold) + '}\n';
}
function validate() {
  for (const file of [storeFile, runtimeFile, project]) assert.equal(retained(file, read(file)), old(file), file);
  const runtime = read(runtimeFile), previous = old(runtimeFile);
  const originalWorker = section(previous, '        let worker = Task.detached(priority: .utility) { () throws -> Data in\n', '        do {');
  const body = originalWorker.slice(originalWorker.indexOf('\n') + 1, originalWorker.lastIndexOf('        }\n'))
    .split('\n').map(l => l.startsWith('      ') ? l.slice(6) : l).join('\n');
  const helper = section(runtime, '  nonisolated static func prepare(', '  nonisolated static func next(');
  assert.equal(helper.slice(helper.indexOf('\n') + 1), body + '  }\n\n', 'Shared builder exactly extracted from prior worker');
  const guardFile = 'apps/ios/tools/check-original-page-archive-queue-scope.cjs';
  assert.equal(read(guardFile), old(guardFile)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-original-page-archive-cold-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(file, source) {\n', "function retained(file, source) {\n  source = require('./check-original-page-archive-cold-scope.cjs').retained(file, source);\n"));
  const owner = read(app + 'AgentIOSOriginalPageArchiveOwner.swift');
  for (const text of ['SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX', 'GalaxySSIEncryptedStateStore.load',
    'UUID(uuidString: identifier)', 'state.profile.identityFingerprint == job.profile',
    '!state.agentSafetySettings.executionPaused', '!conversation.privateMode', '!conversation.trackingPaused',
    'conversation.mergedIntoConversationId.isBlank', 'chatCipher.chatTurnTimingIndex',
    'AgentReplyWaitingIndicatorPolicy.turnKey(for: message) == job.turn', 'expectedPurpose: "chat-message:',
    'defaults.data(forKey: GalaxySSIEncryptedStateStore.stateKey) == encrypted',
    'count <= 4 * 1_024 * 1_024']) assert(owner.includes(text), text);
  for (const forbidden of ['GalaxySSIStore(', 'SQLITE_OPEN_CREATE', 'SQLITE_OPEN_READWRITE', '.set(', '.encrypt(', 'CREATE TABLE', 'UPDATE ']) assert(!owner.includes(forbidden), forbidden);
  const cold = runtime.slice(runtime.indexOf('  @MainActor private static func readOnlySlice()'));
  for (const text of ['owner.allows(job)', 'runtime === boundRuntime', 'coldRun?.id == ticket',
    'withTaskCancellationHandler', 'worker.cancel()', 'AgentIOSOriginalPageArchiveRuntime.prepare',
    'try queue.publish(job, data: data)', 'UIApplication.shared.isProtectedDataAvailable',
    'boundRuntime?.quiesce()', 'boundRuntime.permitsReadOnlyBackground(job)',
    'UIApplication.didBecomeActiveNotification']) assert(cold.includes(text), text);
  assert.equal((cold.match(/permits\(job\)/g) || []).length, 3);
  const store = read(storeFile);
  assert(store.includes('try cipher.encrypt(data, purpose: purpose(id, ext))'));
  assert(store.includes('try encrypted.write(to: file(id, ext), options: [.atomic, .completeFileProtection])'));
  for (const name of ['AgentIOSOriginalPageDocument', 'AgentIOSURLSessionWebMediaProvider', 'AgentIOSPhonePublicHTMLAttachment',
    'GalaxySSIServices', 'GalaxySSIViews', 'GalaxySSIStoreSessions', 'GalaxySSIChatHistoryDatabase', 'GalaxySSIEncryptedStateStore'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  assert.equal((read('apps/ios/GalaxySSITests/AgentIOSOriginalPageArchiveOwnerTests.swift').match(/  func test/g) || []).length, 3);
  console.log('Cold read-only account/turn admission, shared unchanged builder, cancellation handoff and atomic encrypted journal source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
