// Retained-source checks only; no Swift, XCTest, native background grant or Files rendering.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const feature = 'd05a9a53cbd28e870299876207e7ef3cf71898c1', main = 'e95979579e6680915e64d42b286c5f9b79ce84f1';
const cache = new Map(), project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
function at(ref, file) {
  const key = ref + ':' + file;
  if (!cache.has(key)) cache.set(key, cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  return cache.get(key);
}
const hooks = [
  '  private lazy var originalPageArchives = AgentIOSOriginalPageArchiveRuntime(store: store)\n',
  '    originalPageArchives.wake()\n',
  '        self.originalPageArchives.wake()\n',
  '        let publicPageProfile = store.profile.identityFingerprint\n',
  '          await originalPageArchives.enqueue(publicPage, conversation: outgoing.conversationId,\n            turn: homeTurnId, expectedProfile: publicPageProfile)\n'
];
function retained(file, source) {
  if (![project, app + 'GalaxySSIServices.swift', app + 'GalaxySSIViews.swift'].includes(file)) return source;
  const previous = at(feature, file);
  // Earlier guards repeatedly pass their exact, partially normalized checkpoints.
  if (source === previous || ['a16f12311fa4ed70f576c347680a173f8f356fea',
    '5e6167ab76ee808fa271504fb324c879916bb86b', '8a794e82ebe8f09790e41139295ffb7ac1ee9701']
    .some(ref => source === at(ref, file))) return source;
  if (file === project) {
    const owns = line => /AgentIOSOriginalPage(?:Document|Archive(?:Store|Runtime|Owner)(?:Tests)?)\.swift/.test(line);
    const lines = source.split('\n'), ownLines = lines.filter(owns);
    assert.equal(ownLines.length, 24, 'Six archive app/test registrations in four project locations');
    assert.deepEqual(ownLines, previous.split('\n').filter(owns), 'Retain exact archive IDs, phases and groups');
    assert.equal(source.split(' com.galaxyssi.chat.ios.original-page-archive').length, 3);
    assert.equal(lines.filter(line => !owns(line)).join('\n').replaceAll(' com.galaxyssi.chat.ios.original-page-archive', ''),
      at(main, file).split('\n').filter(line => !owns(line)).join('\n').replaceAll(' com.galaxyssi.chat.ios.original-page-archive', ''),
      'Retain every main source registration, setting, deployment version and background identifier');
  } else if (file.endsWith('GalaxySSIViews.swift')) {
    const registration = '    AgentIOSOriginalPageArchiveBackground.register()\n';
    assert.equal(source.split(registration).length, 2);
    assert(source.includes('    AgentKnowledgeStorageBackground.register()\n' + registration));
    assert.equal(source.replace(registration, ''), at(main, file).replace(registration, ''), 'Retain complete main startup and storage registration');
  } else {
    for (const anchor of [
      '  @Published private(set) var pendingPhonePublicPageExport: AgentIOSPhonePublicHTMLExport?\n' + hooks[0],
      '    installForegroundRecoveryWake()\n' + hooks[1] + '    recoverManagedBrowserMembers()',
      '  func resumePendingAgentDelivery() {\n' + hooks[1] + '    guard reconcileLegacyConversationSchedules()',
      '        self.continueForegroundCapturePermissions()\n' + hooks[2] + '        self.recoverManagedBrowserMembers()',
      '        let publicPages: [AgentIOSPhonePublicHTMLPreparation]\n' + hooks[3] + '        if phonePublicPageEnabled {',
      '        for publicPage in publicPages {\n' + hooks[4] + '          if let archiveName = publicPage.originalSourceArchiveName {'
    ]) assert(source.includes(anchor), 'Retain original archive hook location: ' + anchor);
    let restored = source;
    for (const hook of hooks) {
      assert.equal(source.split(hook).length, previous.split(hook).length, 'Retain exact archive hook multiplicity');
      restored = restored.replaceAll(hook, '');
    }
    let mainRestored = at(main, file);
    for (const hook of hooks) mainRestored = mainRestored.replaceAll(hook, '');
    assert.equal(restored, mainRestored, 'Retain exact main coordinator outside archive hooks');
  }
  return previous;
}
function validate() {
  for (const file of [project, app + 'GalaxySSIServices.swift', app + 'GalaxySSIViews.swift']) {
    const source = read(file);
    assert.equal(source, at(main, file), 'No production or project edits beyond current main');
    assert.notEqual(source, at(feature, file), 'Main changes must actually be present, not merely an old feature tree');
    assert.equal(retained(file, source), at(feature, file), file);
    assert.equal(retained(file, retained(file, source)), at(feature, file), 'Idempotent earlier-guard view');
  }
  for (const name of ['AgentIOSOriginalPageArchiveOwner', 'AgentIOSOriginalPageArchiveRuntime', 'AgentIOSOriginalPageArchiveStore',
    'AgentIOSOriginalPageDocument', 'AgentIOSPhonePublicHTMLAttachment', 'AgentIOSURLSessionWebMediaProvider'])
    assert.equal(read(app + name + '.swift'), at(feature, app + name + '.swift'), 'No archive/owner/network behavior changed: ' + name);
  for (const name of ['AgentIOSOriginalPageArchiveOwnerTests', 'AgentIOSOriginalPageArchiveStoreTests', 'AgentIOSPhonePublicHTMLAttachmentTests']) {
    const file = 'apps/ios/GalaxySSITests/' + name + '.swift';
    assert.equal(read(file), at(feature, file), 'Retain original authored fixtures: ' + name);
  }
  const file = 'apps/ios/tools/check-original-page-archive-cold-scope.cjs';
  const expected = at(feature, file)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-original-page-main-sync-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(file, source) {\n', "function retained(file, source) {\n  source = require('./check-original-page-main-sync-scope.cjs').retained(file, source);\n");
  assert.equal(read(file), expected, 'Preserve all prior owner/cold/background/transport assertions');
  console.log('PR #4599 main integration, both background registrations/identifiers, exact main coordinator and unchanged archive/privacy/fixture kernels passed source checks only; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
