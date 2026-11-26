// Source contracts only: no native execution, encrypted IO, OS scheduling or device proof.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), base = '5e6167ab76ee808fa271504fb324c879916bb86b';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', app = 'apps/ios/GalaxySSI/';
function retained(file, source) {
  if (file !== project) return source;
  return source.split('\n').filter(l => !/AgentIOSOriginalPageArchive(?:StoreTests|Store|Runtime)\.swift/.test(l)).join('\n')
    .replaceAll(' com.galaxyssi.chat.ios.original-page-archive', '');
}
function validate() {
  assert.equal(retained(project, read(project)), old(project));
  assert.equal((read(project).match(/ com\.galaxyssi\.chat\.ios\.original-page-archive/g) || []).length, 2);
  for (const name of ['Store', 'Runtime', 'StoreTests']) {
    assert.equal((read(project).match(new RegExp('AgentIOSOriginalPageArchive' + name + '\\.swift in Sources', 'g')) || []).length, 2);
  }
  const service = app + 'GalaxySSIServices.swift';
  const hooks = [
    ['  private lazy var originalPageArchives = AgentIOSOriginalPageArchiveRuntime(store: store)\n', ''],
    ['    originalPageArchives.wake()\n', ''],
    ['        self.originalPageArchives.wake()\n', ''],
    ['        let publicPageProfile = store.profile.identityFingerprint\n', ''],
    ['          await originalPageArchives.enqueue(publicPage, conversation: outgoing.conversationId,\n            turn: homeTurnId, expectedProfile: publicPageProfile)\n', '']
  ];
  let source = read(service);
  assert.equal(source.split('    originalPageArchives.wake()\n').length, 3);
  for (const [addition, before] of hooks) { assert(source.includes(addition), addition); source = source.replaceAll(addition, before); }
  assert.equal(source, old(service), 'Coordinator retained outside declared queue hooks');
  const views = app + 'GalaxySSIViews.swift';
  assert.equal(read(views).replace('    AgentIOSOriginalPageArchiveBackground.register()\n', ''), old(views));
  for (const name of ['AgentIOSPhonePublicHTMLAttachment', 'AgentIOSOriginalPageDocument', 'AgentIOSURLSessionWebMediaProvider',
    'AgentIOSPublicAddressPolicy', 'GalaxySSILocalAttachmentStore', 'AgentKnowledgeBackgroundScheduler'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const guardFile = 'apps/ios/tools/check-original-page-export-scope.cjs';
  assert.equal(read(guardFile), old(guardFile).replace(
    "const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
    "const read = f => require('./check-original-page-archive-queue-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));"));
  const store = read(app + 'AgentIOSOriginalPageArchiveStore.swift'), runtime = read(app + 'AgentIOSOriginalPageArchiveRuntime.swift');
  for (const text of ['GalaxySSILocalAttachmentStoring', 'private static let globalLock', 'OriginalPageQueue/', 'cipher.read(from: path, purpose:',
    'cipher.write(data, to:', 'value.profile == profile', 'candidate.failures < 3',
    'try write(Data(job.id.utf8), job.id, "done")', 'try cleanup(job.id)', 'FileManager.default.linkItem(at: temporary, to: destination)',
    '.completeFileProtection', 'GalaxySSIPrivateChatFiles.contains(directory, in: documents)',
    'values.isSymbolicLink != true', 'throw CocoaError(.fileWriteFileExists)', 'try validate(id)']) assert(store.includes(text), text);
  for (const text of ['job.profile == store.profile.identityFingerprint', '!session.privateMode', '!session.trackingPaused',
    'session.mergedIntoConversationId.isBlank', 'store.agentSessionMessages(job.conversation)',
    'publicWebConsent', 'started + 120_000', 'withTaskCancellationHandler', 'worker.cancel()',
    'if let staged = try queue.staged(job.id)', 'try queue.stage(document.data, id: job.id)',
    'guard self.allows(job)', 'try queue.publish(job, data: data)', 'runtime?.invalidate()',
    'requiresNetworkConnectivity = true', 'task.expirationHandler', 'AgentKnowledgeBackgroundCompletion',
    'UIApplication.protectedDataWillBecomeUnavailableNotification', 'expectedProfile: String']) assert(runtime.includes(text), text);
  assert.equal((read('apps/ios/GalaxySSITests/AgentIOSOriginalPageArchiveStoreTests.swift').match(/  func test/g) || []).length, 3);
  console.log('Scoped encrypted archive queue, live ownership/cancellation, Files publication, retained foreground transport and three authored-only fixture contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
