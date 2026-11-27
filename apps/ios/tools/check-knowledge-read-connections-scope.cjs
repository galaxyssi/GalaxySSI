// Source contracts only; not Swift, native SQLite, filesystem or concurrency execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '78a541cf118c37f0a01187357c8818e51f4a3709';
const app = 'apps/ios/GalaxySSI/', tests = 'apps/ios/GalaxySSITests/';
const read = f => require('./check-knowledge-index-memo-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'));
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const route = `    if let pending {
      return try readFrames(pending, reference: reference, itemHash: itemHash, partition: partition, checkActive: checkActive)
    }
    return try readConnections.read(root: root, file: root.appendingPathComponent(partition + ".sqlite"),
      directoryDescriptor: directoryDescriptor, checkActive: checkActive,
      open: { try open(partition, create: false, readOnly: true) }) { database in
      try readFrames(database, reference: reference, itemHash: itemHash, partition: partition, checkActive: checkActive)
    }
  }

  private func readFrames(_ database: OpaquePointer, reference: Reference, itemHash: String, partition: String,
                          checkActive: () throws -> Void) throws -> Data {
`;
function retained(f, source) {
  source = require('./check-knowledge-index-memo-scope.cjs').retained(f, source);
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(l => !/AgentKnowledge(?:ReadConnectionPool|PrimaryReadConnections)(?:Tests)?\.swift/.test(l)).join('\n');
  if (f === app + 'AgentKnowledgePrimaryPartitions.swift') return source
    .replace('  private let readConnections: AgentKnowledgePrimaryReadConnections\n', '')
    .replace('       afterAllocationFile: @escaping (String) throws -> Void = { _ in },\n       readConnections: AgentKnowledgePrimaryReadConnections = .shared) {',
      '       afterAllocationFile: @escaping (String) throws -> Void = { _ in }) {')
    .replace('    self.readConnections = readConnections\n', '')
    .replace('    try? readConnections.clear(root: root)\n', '')
    .replace(route, '    let database = try pending ?? open(partition, create: false, readOnly: true)\n    defer { if pending == nil { AgentKnowledgeSQLiteStatements.shared.close(database) } }\n')
    .replace('    try readConnections.clear(root: root, requireIdle: true)\n', '')
    .replace('    try readConnections.retire(root: root, file: root.appendingPathComponent(id + ".sqlite"))\n', '');
  if (f === tests + 'AgentKnowledgePrimaryPartitionsTests.swift') return source
    .replace('         readerSlots: AgentKnowledgePrimaryReaderSlots = .shared,\n         readConnections: AgentKnowledgePrimaryReadConnections = .shared) throws {',
      '         readerSlots: AgentKnowledgePrimaryReaderSlots = .shared) throws {')
    .replace('readerSlots: readerSlots,\n        readConnections: readConnections)', 'readerSlots: readerSlots)');
  return source;
}
function validate() {
  const partitionFile = app + 'AgentKnowledgePrimaryPartitions.swift', primary = read(partitionFile);
  assert.equal(retained(partitionFile, primary), old(partitionFile), 'Retain SQL, frame authentication, writes, leases and reclaim except declared reader hooks');
  assert(primary.includes(route), 'Real authenticated read path uses connection reuse; pending writer readback remains separate');
  for (const text of ['private let readConnections: AgentKnowledgePrimaryReadConnections',
    'readConnections: AgentKnowledgePrimaryReadConnections = .shared', 'self.readConnections = readConnections',
    'try? readConnections.clear(root: root)', 'try readConnections.retire(root: root, file: root.appendingPathComponent(id + ".sqlite"))',
    'guard try Self.flock(accessDescriptor, LOCK_EX) else {\n      return nil\n    }\n    try readConnections.clear(root: root, requireIdle: true)\n    return try operation()']) assert(primary.includes(text), text);
  for (const f of [tests + 'AgentKnowledgePrimaryPartitionsTests.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj']) assert.equal(retained(f, read(f)), old(f), f);
  const guard = 'apps/ios/tools/check-knowledge-statements-scope.cjs';
  assert.equal(read(guard), old(guard)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-knowledge-read-connections-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, source) {\n', "function retained(f, source) {\n  source = require('./check-knowledge-read-connections-scope.cjs').retained(f, source);\n"));
  for (const name of ['AgentKnowledgeDatabase', 'AgentKnowledgeSQLiteStatements', 'AgentKnowledgePrimaryReaderSlots',
    'AgentKnowledgePrimaryAllocations', 'AgentKnowledgePrimaryDurability', 'AgentKnowledgePrimaryFrameCodec', 'AgentKnowledgeStorageBackground'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const pool = read(app + 'AgentKnowledgeReadConnectionPool.swift');
  for (const text of ['entries.count < capacity', 'entries.first(where: { !$0.busy && $0.key == key })',
    'entries.first(where: { !$0.busy })', 'condition.wait(until: Date(timeIntervalSinceNow: 0.05))',
    'try Task.checkCancellation(); try checkActive()', 'if sameKey, try valid(current)',
    'resource = nil; dispose(current)', 'resource = try create()', 'if closed || entry.discard',
    'if requireIdle && selected.contains(where: { $0.busy })', 'entry.discard = true',
    'if !failed && !closed && !entry.discard', 'entries.removeAll { $0 === entry }; entries.append(entry)',
    'closed = true; condition.broadcast()', 'catch { failed = true; throw error }',
    'let action = release, discard = failed', 'release = nil', 'condition.unlock()\n    if let resource { dispose(resource) }\n    remove(entry)']) assert(pool.includes(text), text);
  const cache = read(app + 'AgentKnowledgePrimaryReadConnections.swift');
  for (const text of ['capacity: Int = 8', 'precondition((1...8).contains(capacity))',
    'AgentKnowledgeSQLiteStatements.shared.close($0.handle)', 'Key(root: root.path, file: file.path)',
    '$0.stamp == (try Self.stamp', 'let before = try Self.stamp', 'guard before == (try Self.stamp',
    'defer { lease.end() }', 'return try lease.access { try action($0.handle) }', 'requireIdle: true',
    'UIApplication.didReceiveMemoryWarningNotification', '.galaxySSIRuntimePlaintextWillClear',
    'cleanup.async { [weak self]', 'self.pool.invalidate(where: { _ in true })',
    'Darwin.fstat(descriptor, &anchored)', 'Darwin.lstat(root.path, &current)',
    'current.st_dev == anchored.st_dev, current.st_ino == anchored.st_ino',
    'AT_SYMLINK_NOFOLLOW', 'mode_t(S_IFREG)', '["", "-wal", "-shm", "-journal"]',
    'inode: UInt64(main.st_ino)']) assert(cache.includes(text), text);
  for (const forbidden of ['JSONDecoder', 'decrypt(', 'AgentKnowledgeItem', 'resolvingSymlinksInPath']) assert(!cache.includes(forbidden), forbidden);
  const poolTests = read(tests + 'AgentKnowledgeReadConnectionPoolTests.swift');
  const cacheTests = read(tests + 'AgentKnowledgePrimaryReadConnectionsTests.swift');
  assert.equal((poolTests.match(/  func test/g) || []).length, 12);
  assert.equal((cacheTests.match(/  func test/g) || []).length, 12);
  for (const name of ['testActivePlusIdleBoundAndSingleSlotEviction', 'testReturnOrderLRUEvictsOldestIdleKey',
    'testFactoriesValidationAndDisposalCanInspectPoolWithoutDeadlock', 'testInvalidationDuringFactoryPreventsPublicationAndKeepsBound',
    'testCloseWakesBlockedBorrowerAndDefersActiveDisposal']) assert(poolTests.includes(name), name);
  for (const text of ['testReplacedRegularFileReopensInsteadOfServingOldInode', 'testSwapDuringOpenClosesRejectedHandle',
    'testMemoryWarningAndRuntimeClearTrimOnCleanupQueue', 'testActualPrimaryRetirementDrainsReadersBeforeUnlink',
    'AgentKnowledgePrimaryPartitionsTests.Fixture(readConnections: cache)',
    'UPDATE frames SET sealed=x\'00\'', 'XCTAssertThrowsError(try f.store.read']) assert(cacheTests.includes(text), text);
  console.log('Eight active-plus-idle read connections, actual authenticated read routing, identity/retirement/async trim contracts and 24 authored-only fixtures passed source checks; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
