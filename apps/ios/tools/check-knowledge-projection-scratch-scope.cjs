// Source contracts only. This does not compile Swift or execute XCTest.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'b602dc1063447c70a13952d75b81116a45162aa4', app = 'apps/ios/GalaxySSI/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function retained(f, s) {
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return s.split('\n').filter(l => !/Agent(?:KnowledgeProjection(?:Order(?:Tests)?|Lease)|IOSObsidianTextScan|IOSProjectionDestination)\.swift/.test(l)).join('\n');
  if (f !== app + 'AgentIOSObsidianProjection.swift' || !s.includes('let publication = try AgentIOSProjectionDestination')) return s;
  const previous = old(f);
  for (const [a, b] of [
    ['    let fileManager = FileManager.default\n', '    var bodyHasher = SHA256()'],
    ['    func scanOrdered(', '        try consume('],
    ['    let temporary = ', '    defer { try? fileManager.removeItem(at: temporary) }'],
    ['    try publication.publish(temporary)', '    return outputHasher.finalize()']
  ]) {
    const originalStart = a === '    try publication.publish(temporary)' ? '    try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path)' : a;
    s = s.replace(section(s, a, b), section(previous, originalStart, b));
  }
  return s.replace('((URL, String?) throws -> String?)?', '((URL) throws -> String?)?')
    .replace('writeContent: { destination, expectedHash in', 'writeContent: { destination in')
    .replace('destination: destination,\n          expectedDestinationHash: expectedHash', 'destination: destination')
    .replace('scratchCipher suppliedScratchCipher: GalaxySSIAttachmentAtRestCipher? = nil,\n    expectedDestinationHash: String? = nil,\n    scratchOrder suppliedOrder: AgentKnowledgeProjectionOrder? = nil', 'scratchCipher suppliedScratchCipher: GalaxySSIAttachmentAtRestCipher? = nil')
    .replace('try publication.publish(Data(content.utf8), job: jobId)', 'try content.write(to: destination, atomically: true, encoding: .utf8)')
    .replace('    if indexed == nil && FileManager.default.fileExists(atPath: fileURL.path) { return .unchanged }\n', '')
    .replace('try writeContent(fileURL, indexed?.generatedHash)', 'try writeContent(fileURL)')
    .replace('            let scanned = try? AgentIOSObsidianTextScan.read(url, maximumUTF16: maximumCandidateCharacters) else { continue }\n      let currentHash = scanned.hash', '            let data = try? Data(contentsOf: url),\n            let content = String(data: data, encoding: .utf8) else { continue }\n      let currentHash = sha256(content)')
    .replace('content: scanned.prefix', 'content: String(content.prefix(maximumCandidateCharacters))')
    .replace('    guard let scanned = try? AgentIOSObsidianTextScan.read(url, maximumUTF16: maximumCandidateCharacters) else { return nil }\n    let content = scanned.prefix\n    guard frontMatterValue', '    guard let content = try? String(contentsOf: url, encoding: .utf8),\n          frontMatterValue')
    .replace('let actualHash = scanned.hash', 'let actualHash = sha256(content)');
}
function includes(source, values) { for (const value of values) assert(source.includes(value), value); }
function validate() {
  const projection = app + 'AgentIOSObsidianProjection.swift', project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  for (const f of [projection, project]) assert.equal(retained(f, read(f)), old(f), f);
  for (const name of ['AgentKnowledgeDatabase.swift', 'AgentIOSObsidianModels.swift']) assert.equal(read(app + name), old(app + name));
  const tests = 'apps/ios/GalaxySSITests/AgentIOSObsidianProjectionTests.swift';
  assert.equal(read(tests), old(tests), 'Retain existing projection fixtures');
  const projectGuard = 'tools/dev/check-ios-project.js';
  assert.equal(read(projectGuard), old(projectGuard).replace('  [models, "agent.obsidian.order.aes256.v1"],',
    '  [models, "obsidian-order-key:v2:"],\n  [models, "galaxyssi-knowledge-projection-v2"],\n  [models, "seen == count"],\n  [tests, "testLateScratchCorruptionCannotPublishOrReplaceTheDestination"],'));
  const guard = 'apps/ios/tools/check-knowledge-statistics-context-scope.cjs';
  assert.equal(read(guard), old(guard)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');", "const read = f => require('./check-knowledge-projection-scratch-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, s) {\n', "function retained(f, s) {\n  s = require('./check-knowledge-projection-scratch-scope.cjs').retained(f, s);\n"));
  const order = read(app + 'AgentKnowledgeProjectionOrder.swift');
  includes(order, ['SymmetricKey(size: .bits256)', 'AES.GCM.seal', 'AES.GCM.open', 'authenticating: Data(purpose.utf8)',
    'key = nil; fixture = nil', 'sqlite3_create_collation_v2', 'Unmanaged<Collation>.fromOpaque(context).release()',
    'left.id.utf16.lexicographicallyPrecedes(right.id.utf16)', 'if left != nil { return -1 }; if right != nil { return 1 }',
    'PRAGMA cache_size=-512', 'PRAGMA mmap_size=0', 'PRAGMA temp_store=FILE', 'WITHOUT ROWID',
    'String(cString: text) == expected', 'Self.hash(encrypted) == key.bodyHash', 'item.id.utf8.elementsEqual(key.id.utf8)',
    'if status == SQLITE_DONE { break }', 'status == SQLITE_ROW', 'seen < count', 'seen == count',
    'previous.id.utf16.lexicographicallyPrecedes(key.id.utf16)', 'SQLITE_STMTSTATUS_SORT, 0) == 0',
    'if activeStatements > 0 { closing = true; failed = true; return }', 'sqlite3_finalize(row); activeStatements -= 1']);
  for (const token of ['keyAccount:', 'Keychain', 'agent.obsidian.order.aes256.v1']) assert(!order.includes(token), token);
  const lease = read(app + 'AgentKnowledgeProjectionLease.swift');
  includes(lease, ['galaxyssi-knowledge-projection-v2', 'LOCK_EX | LOCK_NB', 'withParentLock(cleaning: true)',
    'O_NOFOLLOW', 'current.st_dev == anchored.st_dev, current.st_ino == anchored.st_ino',
    'Set(names).isSubset(of: Self.files)', 'info.st_nlink == 1', 'AT_SYMLINK_NOFOLLOW', 'AT_REMOVEDIR']);
  assert(lease.indexOf('for file in names {\n      var info') < lease.indexOf('for file in names { guard Darwin.unlinkat'));
  const scan = read(app + 'AgentIOSObsidianTextScan.swift');
  includes(scan, ['read(upToCount: 8_192)', 'hash.update(data: chunk)', 'maximumUTF16 - retained',
    'tail.isEmpty', 'for suffix in 1...min(3, bytes.count)', 'O_NOFOLLOW', 'scalar.value > 0xFFFF ? 2 : 1']);
  assert(!scan.includes('Data(contentsOf:'));
  const destination = read(app + 'AgentIOSProjectionDestination.swift');
  includes(destination, ['NSFileCoordinator()', 'try Self.fingerprint(target) == baseline', 'expected != baseline',
    'O_EXCL | O_NOFOLLOW', 'FileProtectionType.complete', 'replaceItemAt', 'Task.checkCancellation()']);
  const producer = read(projection);
  assert(producer.indexOf('try scanOrdered { part in') < producer.indexOf('let temporary = try publication.stage'));
  includes(producer, ['try order.finish()', 'try order.scan', 'expectedDestinationHash: expectedHash', 'content: scanned.prefix']);
  const fixture = read('apps/ios/GalaxySSITests/AgentKnowledgeProjectionOrderTests.swift');
  assert.equal((fixture.match(/func test/g) || []).length, 18);
  includes(fixture, ['testOrderUsesChunkAndRawUTF16IdentityNotItsDigest', 'testMissingAuthenticatedRowsCannotMasqueradeAsEOF',
    'testCloseDuringScanDefersNativeDisposalAndStopsFurtherDelivery', 'testLiveLeasesSurviveConcurrentJobSweep',
    'testTextScanHandlesUTF8SequencesAcrossEveryChunkBoundary', 'testDestinationChangedDuringPreparationPreservesUserEdit',
    'testActualProjectionRawIDTieOrderAndExactOutputHash', 'testLateScratchCorruptionCannotPublishOrReplaceTheDestination']);
  console.log('Projection scratch encryption, ordering/EOF, leases, bounded edit scan, coordinated publication and 18 authored fixture contracts passed source checks only; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
