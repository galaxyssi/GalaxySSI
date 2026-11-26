// Static source contracts only; no Swift/native SQLite/device/crash execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'a51312cd07ff03dab56340d8493802d789cffc8b', app = 'apps/ios/GalaxySSI/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
const large = `    if old.frames > AgentKnowledgePrimaryCopyState.framePage {
      try beginCopy(itemHash: itemHash, old: old, catalog: catalog, batch: batch)
      return false
    }
    guard let original = try AgentKnowledgePrimaryCopyStore.original(catalog, key: itemHash, source: source) else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
`;
function retained(f, source) {
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(l => !/AgentKnowledgePrimaryCopy(?:State|Store)?(?:Tests)?\.swift/.test(l)).join('\n');
  if (f === app + 'AgentKnowledgeStorageBackground.swift') return source.replace('    guard started.isFinite, deadline.isFinite, now.isFinite, now >= started else { throw CancellationError() }\n    if now >= deadline { throw AgentKnowledgeStorageYield.exhausted }',
    '    guard started.isFinite, deadline.isFinite, now.isFinite, now >= started, now < deadline else { throw CancellationError() }');
  if (f === 'apps/ios/GalaxySSITests/AgentKnowledgePrimaryCompactionTests.swift') return source
    .replace('XCTFail("No live records"); return true', 'XCTFail("No live records")')
    .replace('    _ = try f.store.reclaim(catalog: f.catalog) // Register the paged copy before cancelling its first frame page.\n', '');
  if (f === app + 'AgentKnowledgePrimaryCompaction.swift' && source.includes('resumeCopy:')) return source
    .replace(section(source, '  @discardableResult', '  static func pending('), section(old(f), '  @discardableResult', '  static func pending('))
    .replace(" UNION ALL SELECT '1' FROM knowledge_primary_copy", '')
    .replace('  static func retire(', '  private static func retire(')
    .replace('    guard try !AgentKnowledgePrimaryCopyStore.references(db, key) else { throw AgentKnowledgeDatabaseError.corruptRecord }\n', '');
  if (f !== app + 'AgentKnowledgePrimaryPartitions.swift' || !source.includes('  private func beginCopy(')) return source;
  source = source.replace('  private let afterCopyFrame: (Int) throws -> Void\n', '')
    .replace('       readConnections: AgentKnowledgePrimaryReadConnections = .shared,\n       afterCopyFrame: @escaping (Int) throws -> Void = { _ in }) {', '       readConnections: AgentKnowledgePrimaryReadConnections = .shared) {')
    .replace('    self.afterCopyFrame = afterCopyFrame\n', '')
    .replace('    try AgentKnowledgePrimaryCopyStore.setup(catalog)\n', '')
    .replace('    return try decodeReference(itemHash: itemHash, partition: partition, encrypted: encrypted)\n  }\n\n  private func decodeReference(itemHash: String, partition: String, encrypted: Data) throws -> Reference {\n', '')
    .replace('    let moved = try AgentKnowledgePrimaryCompaction.advance(catalog, checkActive: checkActive,\n      resumeCopy: { try resumeCopy(catalog: catalog, batch: batch, checkActive: checkActive) }) { key, source in',
      '    let moved = try AgentKnowledgePrimaryCompaction.advance(catalog, checkActive: checkActive) { key, source in')
    .replace('checkActive: { try Self.finishCheckpoint(checkActive) }) }', 'checkActive: checkActive) }')
    .replace('    try Self.finishCheckpoint(checkActive)\n    try execute(catalog, "COMMIT")', '    try checkActive()\n    try Task.checkCancellation()\n    try execute(catalog, "COMMIT")')
    .replace('                        checkActive: () throws -> Void) throws -> Bool {', '                        checkActive: () throws -> Void) throws {')
    .replace(large, '')
    .replace('      try walkFrames(reader, reference: old, itemHash: itemHash, partition: source,\n        checkActive: { try Self.finishCheckpoint(checkActive) }) { encoded, _, ordinal in',
      '      try walkFrames(reader, reference: old, itemHash: itemHash, partition: source, checkActive: checkActive) { encoded, _, ordinal in\n        try checkActive()')
    .replace('    try Self.finishCheckpoint(checkActive)\n    let next = Reference', '    try Task.checkCancellation(); try checkActive()\n    let next = Reference')
    .replace('WHERE item_hash=? AND partition_id=? AND sealed_ref=?")', 'WHERE item_hash=? AND partition_id=?")')
    .replace('    try bind(original, index: 5, statement: update)\n', '')
    .replace('    return true\n  }\n\n  // Only a cooperative time budget', '  }\n\n  // Only a cooperative time budget')
    .replace(section(source, '  // Only a cooperative time budget', '  private func reclaimExclusively('), '')
    .replace('      guard try !AgentKnowledgePrimaryCopyStore.references(catalog, id) else { throw AgentKnowledgeDatabaseError.corruptRecord }\n', '')
    .replace('    if try AgentKnowledgePrimaryCopyStore.references(catalog, id) { return true }\n', '');
  return source;
}
function validate() {
  for (const f of [app + 'AgentKnowledgePrimaryPartitions.swift', app + 'AgentKnowledgePrimaryCompaction.swift',
    app + 'AgentKnowledgeStorageBackground.swift', 'apps/ios/GalaxySSITests/AgentKnowledgePrimaryCompactionTests.swift',
    'apps/ios/GalaxySSI.xcodeproj/project.pbxproj']) assert.equal(retained(f, read(f)), old(f), f);
  const guard = 'apps/ios/tools/check-knowledge-primary-compaction-scope.cjs';
  assert.equal(read(guard), old(guard)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-knowledge-primary-copy-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, source) {\n', "function retained(f, source) {\n  source = require('./check-knowledge-primary-copy-scope.cjs').retained(f, source);\n"));
  const primary = read(app + 'AgentKnowledgePrimaryPartitions.swift'), queue = read(app + 'AgentKnowledgePrimaryCompaction.swift');
  for (const text of [large, 'try AgentKnowledgePrimaryCopyStore.setup(catalog)', 'resumeCopy: { try resumeCopy(catalog: catalog',
    'try Self.finishCheckpoint(checkActive)', 'if try AgentKnowledgePrimaryCopyStore.references(catalog, id) { return true }',
    'guard try !AgentKnowledgePrimaryCopyStore.references(catalog, id)', 'AND partition_id=? AND sealed_ref=?',
    'try bind(original, index: 5, statement: update)']) assert(primary.includes(text), text);
  const helpers = section(primary, '  // Only a cooperative time budget', '  private func reclaimExclusively(');
  for (const text of ['try Task.checkCancellation()', 'catch is AgentKnowledgeStorageYield',
    'allocations.remember(destination, syncParent: syncRoot)', 'VALUES(?,?,0,1,1)', 'state.validate(old)',
    'Self.sha256(job.original)', 'expectedPurpose: copyPurpose(job)', 'AgentKnowledgePrimaryCopyStore.validateOwnership',
    'source: job.source) != job.original', 'AgentKnowledgePrimaryCompaction.retire(catalog, job.destination)',
    'DELETE FROM frames WHERE entry_id=? AND ordinal>=?', 'batch.pending.insert(job.destination)',
    'state.copiedHash = try AgentKnowledgePrimaryCopyState.chain', 'state.verifiedHash = try AgentKnowledgePrimaryCopyState.chain',
    'state.copiedHash == state.verifiedHash', 'AgentKnowledgePrimaryCopyStore.publish', 'AgentKnowledgePrimaryCopyStore.remove',
    'AgentKnowledgePrimaryCopyStore.checkpoint', 'ordinal>=? ORDER BY ordinal LIMIT 17',
    'while count < AgentKnowledgePrimaryCopyState.framePage', 'if count == 0 { throw yield }; break',
    'start + count == reference.frames, sqlite3_step(frames) != SQLITE_DONE', 'afterCopyFrame(ordinal)']) assert(helpers.includes(text), text);
  for (const forbidden of ['ensureSharedLease()', 'writerLock.lock()', 'var result = Data()', 'readFrames(']) assert(!helpers.includes(forbidden), forbidden);
  for (const text of ['if try AgentKnowledgePrimaryCopyStore.pending(db)', 'let moved = try resumeCopy()',
    'if try !relocate(key, source) { break }', 'catch let yield as AgentKnowledgeStorageYield', 'if moved == 0 { throw yield }',
    'guard try !AgentKnowledgePrimaryCopyStore.references(db, key)']) assert(queue.includes(text), text);
  const store = read(app + 'AgentKnowledgePrimaryCopyStore.swift'), state = read(app + 'AgentKnowledgePrimaryCopyState.swift');
  for (const text of ['CHECK(source_partition<>destination_partition)', 'substr(original,1,8193)', 'substr(checkpoint,1,8193)',
    'source_partition=? OR destination_partition=?', 'c.source=s.partition_id', 'd.sealed=1 AND d.records=1 AND d.bytes=?',
    'WHERE id=1 AND checkpoint=?', 'AND sealed_ref=?', 'sqlite3_changes(db) == 1', 'AgentKnowledgeSQLiteStatements.shared.prepare']) assert(store.includes(text), text);
  for (const text of ['static let framePage = 16', '(0...source.frames).contains(copied)', '(0...copied).contains(verified)',
    'verified == 0 || copied == source.frames', 'copiedPlainBytes == (try Self.bytes', 'verifiedPlainBytes == (try Self.bytes',
    'var number = UInt64(ordinal).bigEndian', 'SHA256.hash(data: bytes)', 'upper.overflow || storedBytes <= upper.partialValue']) assert(state.includes(text), text);
  for (const [file, count] of [['AgentKnowledgePrimaryCopyStateTests', 6], ['AgentKnowledgePrimaryCopyTests', 12]])
    assert.equal((read('apps/ios/GalaxySSITests/' + file + '.swift').match(/  func test/g) || []).length, count);
  for (const name of ['AgentKnowledgeDatabase', 'AgentKnowledgePrimaryReadConnections', 'AgentKnowledgeReadConnectionPool',
    'AgentKnowledgeSQLiteStatements', 'AgentKnowledgePrimaryReaderSlots', 'AgentKnowledgePrimaryAllocations', 'AgentKnowledgePrimaryDurability', 'AgentKnowledgePrimaryFrameCodec'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  console.log('Authenticated durable copy/verify cursors, physical-before-checkpoint ordering, exact-reference publication, ownership/retirement guards and 18 authored-only fixture contracts passed source checks; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
