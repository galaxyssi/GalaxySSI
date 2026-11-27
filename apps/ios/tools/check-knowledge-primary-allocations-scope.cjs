// Source contracts only. No SQLite, Darwin, XCTest or process-death execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'cace7bdadba48e0bd82d063ee8538e3ae5529042', app = 'apps/ios/GalaxySSI/';
const file = app + 'AgentKnowledgePrimaryPartitions.swift';
const read = f => require('./check-knowledge-statements-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'));
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(source, start, end) { const a = source.indexOf(start), b = source.indexOf(end, a + start.length); assert(a >= 0 && b > a, start); return source.slice(a, b); }
const fields = '  private let afterAllocationIntent: (String) throws -> Void\n  private let afterAllocationFile: (String) throws -> Void\n  private var allocations: AgentKnowledgePrimaryAllocations { AgentKnowledgePrimaryAllocations(root: root) }\n';
const initializers = '       readerSlots: AgentKnowledgePrimaryReaderSlots = .shared,\n       afterAllocationIntent: @escaping (String) throws -> Void = { _ in },\n       afterAllocationFile: @escaping (String) throws -> Void = { _ in }) {';
function retained(f, source) {
  source = require('./check-knowledge-statements-scope.cjs').retained(f, source);
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(l => !/AgentKnowledgePrimaryAllocations(?:Tests)?\.swift/.test(l)).join('\n');
  if (f !== file || !source.includes(fields)) return source;
  source = source.replace(fields, '').replace(initializers, '       readerSlots: AgentKnowledgePrimaryReaderSlots = .shared) {')
    .replace('    self.afterAllocationIntent = afterAllocationIntent\n    self.afterAllocationFile = afterAllocationFile\n', '')
    .replace(section(source, '  func reclaim(catalog:', '  func checkSharedAccess()'), section(old(file), '  func reclaim(catalog:', '  func checkSharedAccess()'))
    .replace(section(source, '  // Validate the entire set before unlinking', '  private func syncRoot()'), '')
    .replace('    try validatePartitionFiles(id, requireMain: false)\n', '')
    .replace('    for suffix in ["-wal", "-shm", "-journal", ""] {', '    for suffix in ["-wal", "-shm", ""] {')
    .replace('    for suffix in ["", "-wal", "-shm", "-journal"] {', '    for suffix in ["", "-wal", "-shm"] {')
    .replace('    try allocations.remember(id, syncParent: syncRoot)\n    try afterAllocationIntent(id)\n', '')
    .replace('    sqlite3_close_v2(database)\n    try syncRoot()\n    try afterAllocationFile(id)\n', '    sqlite3_close_v2(database)\n');
  return source;
}
function validate() {
  const source = read(file);
  assert.equal(retained(file, source), old(file), 'Only allocation/sidecar/reclaim hooks change primary implementation');
  const reclaim = section(source, '  func reclaim(catalog:', '  func checkSharedAccess()');
  for (const text of ['sqlite3_get_autocommit(catalog) != 0', '!allocations.hasPending()',
    'withExclusiveAccess(catalog: catalog)', 'allocations.replay(limit: min(pageSize, 8)',
    'allocationReferenced(id, catalog: catalog, includeRetired: true)',
    'validatePartitionFiles(id, requireMain: allocationReferenced(id, catalog: catalog, includeRetired: false))', 'try unlinkRetired(id)',
    'retired.complete && recovered.complete']) assert(reclaim.includes(text), text);
  assert(reclaim.indexOf('withExclusiveAccess(catalog: catalog)') < reclaim.indexOf('allocations.replay('));
  const partition = section(source, '  private func partition(catalog:', '  private func writer(');
  assert(partition.indexOf('allocations.remember(id, syncParent: syncRoot)') < partition.indexOf('open(id, create: true'));
  const preflight = section(source, '  private func validatePartitionFiles(', '  private func syncRoot()');
  for (const text of ['requireMain', 'AT_SYMLINK_NOFOLLOW', 'S_IFREG', '"-journal"']) assert(preflight.includes(text), text);
  assert(preflight.includes('UNION ALL SELECT 1 FROM knowledge_primary_retired WHERE partition_id=?'));
  assert(!preflight.includes('unlink'));
  const unlink = section(source, '  private func unlinkRetired(', '  // Validate the entire set');
  assert(unlink.indexOf('validatePartitionFiles') < unlink.indexOf('for suffix'));
  const journal = read(app + 'AgentKnowledgePrimaryAllocations.swift');
  for (const text of ['.allocations.sqlite', 'INSERT INTO pending(partition_id) VALUES(?)',
    '    }\n    try syncParent()', 'AgentKnowledgePrimaryDurability.configure(db, role: .primary)',
    'SQLITE_OPEN_READONLY', 'PRAGMA user_version=1', '(0...1).contains(value)',
    'SELECT partition_id FROM pending ORDER BY partition_id LIMIT ?',
    'if try referenced(id) { try verify(id) }', 'try remove(id); orphaned += 1',
    'DELETE FROM pending WHERE partition_id=?', 'if !committed { try? execute(db, "ROLLBACK") }',
    'try AgentKnowledgePrimaryDurability.verify(db, role: .primary)', 'Darwin.lstat',
    'Task.checkCancellation()', 'UUID(uuidString: id)?.uuidString.lowercased() == id']) assert(journal.includes(text), text);
  for (const forbidden of ['contentsOfDirectory', 'enumerator(', 'OR REPLACE', 'removeItem(']) assert(!journal.includes(forbidden), forbidden);
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal(require('./check-knowledge-primary-durability-scope.cjs').retained(project, read(project)),
    cp.execFileSync('git', ['show', 'a5d92e61c98c6a8ece94cb925bd07b49fd99a339:' + project], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  const guardFile = 'apps/ios/tools/check-knowledge-primary-durability-scope.cjs';
  assert.equal(read(guardFile), old(guardFile)
    .replace("base = '97374e5882356fd28a3a251873b6c5cd7dfa6a54'", "base = 'a5d92e61c98c6a8ece94cb925bd07b49fd99a339'")
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-knowledge-primary-allocations-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(file, source) {\n', "function retained(file, source) {\n  source = require('./check-knowledge-primary-allocations-scope.cjs').retained(file, source);\n"));
  for (const name of ['AgentKnowledgeDatabase', 'AgentKnowledgePrimaryDurability', 'AgentKnowledgePrimaryFrameCodec',
    'AgentKnowledgePrimaryReaderSlots', 'AgentKnowledgeStorageBackground']) assert.equal(read(app + name + '.swift'),
      name === 'AgentKnowledgeDatabase' ? require('./check-knowledge-statements-scope.cjs').predecessor(app + name + '.swift') : old(app + name + '.swift'), name);
  assert.equal((read('apps/ios/GalaxySSITests/AgentKnowledgePrimaryAllocationsTests.swift').match(/  func test/g) || []).length, 10);
  console.log('Separate allocation intent, EX-lease bounded replay, complete-set sidecar preflight and ten authored-only fixture source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
