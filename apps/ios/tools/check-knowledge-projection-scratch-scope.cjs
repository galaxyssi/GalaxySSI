// Source contracts only. This does not compile Swift or execute XCTest.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'd29e681d2bd99dffe3fc5e8a5af8e95108f2eb33', app = 'apps/ios/GalaxySSI/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function retained(f, s) {
  if (f === app + 'AgentKnowledgeModels.swift') return s.replace(section(s, 'enum AgentKnowledgeSourceRevision {', 'struct AgentKnowledgeSourceCursor:'),
    section(old(f), 'enum AgentKnowledgeSourceRevision {', 'struct AgentKnowledgeSourceCursor:'));
  if (f === app + 'AgentKnowledgeDatabase.swift' && s.includes('sourceRevision: AgentKnowledgeSourceRevision.digest(members)')) return s
    .replace(section(s, '  // Only an explicitly requested legacy source', '  func enumerateSourceSnapshotItems('), '')
    .replace('    let resolved = try resolveSourceExportGroup(group)\n', '')
    .replace('try enumerateSourceSnapshotItems(resolved)', 'try enumerateSourceSnapshotItems(group)')
    .replace('== resolved.sourceRevision', '== group.sourceRevision')
    .replace('        let view = try committedReadView()\n        defer { view.close() }\n        return try view.read { connection -> (Int64, AgentKnowledgePreparedSourceReplacement.Policy?) in',
      '        try readCommitted { connection -> (Int64, AgentKnowledgePreparedSourceReplacement.Policy?) in')
    .replace(section(s, '  func enumerateSourceSnapshotItems(', '  func sourceBrowseRevision()'),
      section(old(f), '  func enumerateSourceSnapshotItems(', '  func sourceBrowseRevision()'))
    .replace('            try stage.finishMutation()\n            if changed > 0 {', '            if changed > 0 {')
    .replace('          }\n          if changed > 0 {\n            try timing.measure(.observe)', '            try stage.finishMutation()\n          }\n          if changed > 0 {\n            try timing.measure(.observe)')
    .replace('updatedAtMillis: latest.updatedAtMillis,\n                  sourceRevision: try stage.sourceRevision(checkActive: { try prepared.checkActive() }))', 'updatedAtMillis: latest.updatedAtMillis)')
    .replace('          updatedAtMillis: latest.updatedAtMillis,\n          sourceRevision: AgentKnowledgeSourceRevision.digest(members)', '          updatedAtMillis: latest.updatedAtMillis');
  if (f === app + 'AgentKnowledgeSourceStaging.swift' && s.includes('  func sourceRevision(side:')) return s
    .replace('private(set) var previousCount', 'private var previousCount')
    .replace('      guard sqlite3_create_collation_v2(database, "SOURCE_ID_ORDER", SQLITE_UTF8, Unmanaged.passUnretained(self).toOpaque(), { context, ac, a, bc, b in\n        guard let context else { return 0 }\n        return Unmanaged<AgentKnowledgeSourceStaging>.fromOpaque(context).takeUnretainedValue().compare(a, ac, b, bc, identity: true)\n      }, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }\n', '')
    .replace('      try execute("CREATE INDEX source_identity_order ON ordering(side,sort_key COLLATE SOURCE_ID_ORDER)")\n', '')
    .replace('func orderedVisit(_ side: Side, byIdentity: Bool = false,', 'func orderedVisit(_ side: Side,')
    .replace('guard (phase == .finished || (byIdentity && phase == .prepared)), !collationFailed', 'guard phase == .finished, !collationFailed')
    .replace('      let collation = byIdentity ? "SOURCE_ID_ORDER" : "SOURCE_ORDER"\n      try statement("SELECT sort_key,token FROM ordering WHERE side=? ORDER BY sort_key COLLATE \\(collation)")',
      '      try statement("SELECT sort_key,token FROM ordering WHERE side=? ORDER BY sort_key COLLATE SOURCE_ORDER")')
    .replace('if let previous, !(byIdentity ? AgentKnowledgeSourceRevision.identityPrecedes(previous.id, key.id) : less(previous, key))', 'if let previous, !less(previous, key)')
    .replace(section(s, '  func sourceRevision(side:', '  func clearAllowed()'), '')
    .replace('bc: Int32, identity: Bool = false) -> Int32', 'bc: Int32) -> Int32')
    .replace('    if identity, let left, let right {\n      return AgentKnowledgeSourceRevision.identityPrecedes(left.id, right.id) ? -1 :\n        (AgentKnowledgeSourceRevision.identityPrecedes(right.id, left.id) ? 1 : 0)\n    }\n', '');
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return s.split('\n').filter(l => !/Agent(?:KnowledgeProjection(?:Order(?:Tests)?|Lease|IntegrationTests)|IOSObsidianTextScan|IOSProjectionDestination)\.swift/.test(l)).join('\n');
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
  return s.split('\n').filter(l => l.trim() !== 'try checkActive()').join('\n')
    .replace('knowledgeProjectionSpec(appStore: appStore, group: page.groups[index], canPrepareLegacy: written < writeLimit)', 'knowledgeProjectionSpec(appStore: appStore, group: page.groups[index])')
    .replace(section(s, '  private static func knowledgeProjectionSpec(', '    let source = group.localItemId'), section(previous, '  private static func knowledgeProjectionSpec(', '    let source = group.localItemId'))
    .replace('((URL, String?) throws -> String?)?', '((URL) throws -> String?)?')
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
  for (const name of ['AgentKnowledgeDatabase.swift', 'AgentKnowledgeModels.swift', 'AgentKnowledgeSourceStaging.swift', 'AgentIOSObsidianModels.swift'])
    assert.equal(retained(app + name, read(app + name)), old(app + name), 'Outside declared source revision/export hooks: ' + name);
  const tests = 'apps/ios/GalaxySSITests/AgentIOSObsidianProjectionTests.swift';
  assert.equal(read(tests), old(tests), 'Retain existing projection fixtures');
  const projectGuard = 'tools/dev/check-ios-project.js';
  assert.equal(read(projectGuard), old(projectGuard).replace('  [models, "agent.obsidian.order.aes256.v1"],',
    '  [models, "obsidian-order-key:v2:"],\n  [models, "galaxyssi-knowledge-projection-v2"],\n  [models, "seen == count"],\n  [tests, "testLateScratchCorruptionCannotPublishOrReplaceTheDestination"],')
    .replace('  [models, "PRAGMA query_only = ON"],', '  [read("apps/ios/GalaxySSI/AgentKnowledgeCommittedReadView.swift"), "PRAGMA query_only=ON"],'));
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
  includes(producer, ['guard let generation = database.nativeFiles.readToken()',
    'guard database.nativeFiles.readToken() == generation', 'func checkActive() throws']);
  assert.equal((producer.match(/try checkActive\(\)/g) || []).length, 4);
  assert(producer.indexOf('try scanOrdered { part in') < producer.indexOf('let temporary = try publication.stage'));
  includes(producer, ['try order.finish()', 'try order.scan', 'expectedDestinationHash: expectedHash', 'content: scanned.prefix']);
  const fixture = read('apps/ios/GalaxySSITests/AgentKnowledgeProjectionOrderTests.swift');
  assert.equal((fixture.match(/func test/g) || []).length, 18);
  includes(fixture, ['testOrderUsesChunkAndRawUTF16IdentityNotItsDigest', 'testMissingAuthenticatedRowsCannotMasqueradeAsEOF',
    'testCloseDuringScanDefersNativeDisposalAndStopsFurtherDelivery', 'testLiveLeasesSurviveConcurrentJobSweep',
    'testTextScanHandlesUTF8SequencesAcrossEveryChunkBoundary', 'testDestinationChangedDuringPreparationPreservesUserEdit',
    'testActualProjectionRawIDTieOrderAndExactOutputHash', 'testLateScratchCorruptionCannotPublishOrReplaceTheDestination']);
  const database = read(app + 'AgentKnowledgeDatabase.swift');
  const snapshot = section(database, '  func enumerateSourceSnapshotItems(', '  func sourceBrowseRevision()');
  includes(snapshot, ['let view = try committedReadView()', 'defer { view.close() }', 'try view.read { snapshot in',
    'current.sourceRevision == group.sourceRevision', 'sqlite3_step(header) == SQLITE_DONE', 'let status = sqlite3_step(page)',
    'if status == SQLITE_DONE { break }', 'status == SQLITE_ROW', 'try view.read { _ in try consume(item) }',
    'emitted == group.chunkCount', 'AgentKnowledgeDatabaseError.staleCursor']);
  assert(!snapshot.includes('sqlite3_open_v2') && !snapshot.includes('try locked'));
  includes(snapshot, ['let group = try resolveSourceExportGroup(group)']);
  const recovery = section(database, '  func resolveSourceExportGroup(', '  func enumerateSourceSnapshotItems(');
  includes(recovery, ['guard group.sourceRevision.isBlank else { return group }', 'current == group',
    'current.source.utf8.elementsEqual(group.source.utf8)', 'try sourceGeneration(hash: sourceHash, on: connection)',
    'prepareSourceReplacement(group.source, next: { nil })', 'prepared.token == token', 'prepared.revision == baseline.1',
    'stage.previousCount == Int64(group.chunkCount)', 'try stage.finishMutation()',
    'stage.sourceRevision(side: .previous, checkActive:', 'try beforePublication()', 'BEGIN IMMEDIATE',
    'sourceGeneration(hash: sourceHash) == prepared.revision', 'try originalHeader(on: database) == baseline.0',
    'WHERE source_hash=? AND encrypted_header=?', 'insertSourcePreview(resolved', "typeof(revision)='integer'",
    'revision<9223372036854775807', 'try prepared.commitCanonical', 'if !committed']);
  assert(recovery.indexOf('try beforePublication()') < recovery.indexOf('return try locked'));
  assert(recovery.indexOf('try stage.finishMutation()') < recovery.indexOf('stage.sourceRevision(side:'));
  assert(!/replaceAll|insert\(item\)|removeSourceRecord|beginWriteBatch|enqueueSourceObservation|requestIndexRetry/.test(recovery));
  const commit = section(database, '  func commitSourceReplacement(', '  private func validatePreparedIdentity(');
  assert(commit.indexOf('try stage.finishMutation()') < commit.indexOf('sourceRevision: try stage.sourceRevision'));
  const preparation = section(database, '  func prepareSourceReplacement(', '  func commitSourceReplacement(');
  includes(preparation, ['let view = try committedReadView()', 'return try view.read { connection']);
  assert(!/requestIndexRetry|try readCommitted/.test(preparation));
  includes(producer, ['canPrepareLegacy: written < writeLimit', 'if canPrepareLegacy {',
    'try appStore.agentKnowledgeDatabase.resolveSourceExportGroup(suppliedGroup)']);
  includes(database, ['sourceRevision: try stage.sourceRevision(checkActive:', 'sourceRevision: AgentKnowledgeSourceRevision.digest(members)']);
  const stage = read(app + 'AgentKnowledgeSourceStaging.swift');
  includes(stage, ['SOURCE_ID_ORDER', 'CREATE INDEX source_identity_order', 'byIdentity: Bool = false',
    'try orderedVisit(side, byIdentity: true)', 'guard phase == .finished, !collationFailed',
    'var accumulator = AgentKnowledgeSourceRevision.Accumulator()', 'try checkActive(); try accumulator.append($0); try checkActive()']);
  const sourceHash = section(stage, '  func sourceRevision(side:', '  func clearAllowed()');
  assert(!sourceHash.includes('[AgentKnowledgeItem]') && !sourceHash.includes('.sorted'));
  const revision = section(read(app + 'AgentKnowledgeModels.swift'), 'enum AgentKnowledgeSourceRevision {', 'struct AgentKnowledgeSourceCursor:');
  includes(revision, ['private var hasher = SHA256()', 'encoder.outputFormatting = [.sortedKeys]',
    'UInt64(data.count).bigEndian', 'withUnsafeBytes(of: &length)', 'hasher.update(data: data)',
    'identityPrecedes($0.id, $1.id)', 'left.utf16.lexicographicallyPrecedes(right.utf16)']);
  const integration = read('apps/ios/GalaxySSITests/AgentKnowledgeProjectionIntegrationTests.swift');
  assert.equal((integration.match(/func test/g) || []).length, 17);
  includes(integration, ['testBulkAndTargetedWritesPublishCompleteContentRevisions', 'testActualBridgeExportsFreshTargetedSourceAndExactOutputHash',
    'testStaleSourceGroupRejectsBeforeDeliveringAnyRecord', 'testSnapshotKeepsOldHeadersAndBodiesAcrossTargetedReplacement',
    'testLifecycleInvalidationStopsFurtherSnapshotDeliveryAndAllowsFreshView',
    'testStreamedSourceDigestUsesIdentityOrderAndLegacyEncoding', 'testMissingStagedRecordCannotPublishACompletedSourceDigest',
    'testLifecycleChangeDuringSecondRenderPassPreservesDestination', 'testSourceDigestCannotStartInsidePendingMutationTransaction',
    'testLegacyRevisionRecoverySurvivesReopenWithoutChangingSourceFields', 'testActualBridgeRecoversLegacyRevisionBeforePublishingOutput',
    'testLegacyRecoveryRejectsConcurrentSourceReplacement', 'testLegacyRecoveryRejectsSameLogicalHeaderWithDifferentCiphertext',
    'testLegacyRecoveryCountMismatchDoesNotPublishGuessedRevision', 'testLegacyRecoveryFaultAndLifecycleLossDoNotPublishAndAllowRetry',
    'testLegacyMetadataRepairKeepsPreparedSourceGenerationAndVectorLedger', 'testLegacyRecoveryRejectsUnauthenticatedHeaderWithoutPublishing']);
  console.log('Projection scratch, on-demand legacy revision recovery, finished-stage digest, lifecycle-safe export and 18 scratch plus 17 integration authored fixture contracts passed source checks only; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
