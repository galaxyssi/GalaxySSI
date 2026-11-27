// Source contracts only. No native SQLite, XCTest, crash/reboot or power-loss run.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'a5d92e61c98c6a8ece94cb925bd07b49fd99a339';
const app = 'apps/ios/GalaxySSI/';
const read = f => require('./check-knowledge-primary-allocations-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'));
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const configureCatalog = '    do { try AgentKnowledgePrimaryDurability.configure(database, role: .catalog) }\n    catch { sqlite3_close_v2(database); self.database = nil; return }';
function retained(file, source) {
  source = require('./check-knowledge-primary-allocations-scope.cjs').retained(file, source);
  if (file.endsWith('AgentKnowledgeDatabase.swift')) return source.replace(configureCatalog,
    '    _ = execute("PRAGMA journal_mode = WAL")\n    _ = execute("PRAGMA synchronous = FULL")');
  if (file.endsWith('AgentKnowledgePrimaryPartitions.swift')) return source.split('\n')
    .filter(l => !l.includes('AgentKnowledgePrimaryDurability.verify(')).join('\n')
    .replace('      try AgentKnowledgePrimaryDurability.configure(database, role: .primary)',
      '      try execute(database, "PRAGMA journal_mode=WAL")\n      try execute(database, "PRAGMA synchronous=FULL")\n      try execute(database, "PRAGMA fullfsync=ON")');
  if (file.endsWith('AgentKnowledgePrimaryPartitionsTests.swift')) return source
    .replace('      try AgentKnowledgePrimaryDurability.configure(catalog, role: .catalog)', '      try sql("PRAGMA journal_mode=WAL")')
    .replace('    try AgentKnowledgePrimaryDurability.configure(catalog, role: .catalog)\n', '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(l => !/AgentKnowledgePrimaryDurability(?:Tests)?\.swift/.test(l)).join('\n');
  return source;
}
function validate() {
  for (const f of [app + 'AgentKnowledgeDatabase.swift', app + 'AgentKnowledgePrimaryPartitions.swift',
    'apps/ios/GalaxySSITests/AgentKnowledgePrimaryPartitionsTests.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj'])
    assert.equal(retained(f, read(f)), old(f), f);
  const primary = read(app + 'AgentKnowledgePrimaryPartitions.swift');
  assert.equal((primary.match(/AgentKnowledgePrimaryDurability.verify\(catalog, role: \.catalog\)/g) || []).length, 3);
  assert(primary.includes('try beforePartitionCommit(id)\n        try AgentKnowledgePrimaryDurability.verify(database, role: .primary)\n        try execute(database, "COMMIT")'));
  assert(primary.includes('try beforePartitionCommit(writer.id)\n      try AgentKnowledgePrimaryDurability.verify(writer.database, role: .primary)\n      try execute(writer.database, "COMMIT")'));
  assert(primary.includes('if batch.hasWrites { try syncRoot(); try beforeCatalogPublication() }\n      try AgentKnowledgePrimaryDurability.verify(catalog, role: .catalog)'));
  assert(primary.includes('if batch == nil { try syncRoot(); try beforeCatalogPublication() }\n    try AgentKnowledgePrimaryDurability.verify(catalog, role: .catalog)'));
  const policy = read(app + 'AgentKnowledgePrimaryDurability.swift');
  for (const text of ['sqlite3_db_readonly(handle, "main") == 0', 'sqlite3_get_autocommit(handle) != 0',
    'role == .primary ? "EXTRA" : "FULL"', '"PRAGMA journal_mode=WAL"', '"PRAGMA fullfsync=ON"',
    '"PRAGMA checkpoint_fullfsync=ON"', 'try verify(handle, role: role)',
    'try scalar(handle, "PRAGMA journal_mode").lowercased() == "wal"',
    'try scalar(handle, "PRAGMA synchronous") == (role == .primary ? "3" : "2")',
    'try scalar(handle, "PRAGMA fullfsync") == "1"', 'try scalar(handle, "PRAGMA checkpoint_fullfsync") == "1"',
    'sqlite3_step(statement) == SQLITE_ROW', 'sqlite3_step(statement) == SQLITE_DONE']) assert(policy.includes(text), text);
  const guardFile = 'apps/ios/tools/check-knowledge-primary-partitions-scope.cjs';
  assert.equal(read(guardFile), old(guardFile)
    .replace("const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = file => require('./check-knowledge-primary-durability-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(file, source) {\n', "function retained(file, source) {\n  source = require('./check-knowledge-primary-durability-scope.cjs').retained(file, source);\n"));
  for (const name of ['AgentKnowledgePrimaryFrameCodec', 'AgentKnowledgePrimaryReaderSlots', 'AgentKnowledgeStorageBackground', 'AgentKnowledgeNativeFiles'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/AgentKnowledgePrimaryDurabilityTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 7);
  assert(tests.includes('XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), previous)'));
  console.log('Checked primary EXTRA/catalog FULL WAL configuration, pre-commit/publication readback, retained formats/leases and seven authored-only fixture source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
