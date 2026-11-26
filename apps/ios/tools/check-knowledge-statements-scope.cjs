// Source contracts only; no Swift compilation or native SQLite/XCTest execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'bfcd499370441adfa07ff6361e422e4bb997b1ac';
const app = 'apps/ios/GalaxySSI/', tests = 'apps/ios/GalaxySSITests/';
const production = ['AgentKnowledgeDatabase', 'AgentKnowledgePrimaryPartitions', 'AgentKnowledgePrimaryAllocations', 'AgentKnowledgePrimaryDurability'];
const fixtures = ['AgentKnowledgePrimaryPartitionsTests', 'AgentKnowledgePrimaryDurabilityTests'];
const read = f => require('./check-knowledge-read-connections-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'));
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function retained(f, source) {
  source = require('./check-knowledge-read-connections-scope.cjs').retained(f, source);
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(l => !/AgentKnowledgeSQLiteStatements(?:Tests)?\.swift/.test(l)).join('\n');
  if (production.some(n => f === app + n + '.swift')) {
    source = source.replaceAll('AgentKnowledgeSQLiteStatements.shared.prepare(', 'sqlite3_prepare_v2(')
      .replaceAll('AgentKnowledgeSQLiteStatements.shared.release(', 'sqlite3_finalize(')
      .replaceAll('AgentKnowledgeSQLiteStatements.shared.close(', 'sqlite3_close_v2(');
    if (f === app + 'AgentKnowledgeDatabase.swift') source = source.replace(
      '    if value.withCString({ sqlite3_bind_text(statement, index, $0, -1, Self.transient) }) != SQLITE_OK {\n      AgentKnowledgeSQLiteStatements.shared.markFailed(statement)\n    }',
      '    value.withCString { sqlite3_bind_text(statement, index, $0, -1, Self.transient) }');
    if (f === app + 'AgentKnowledgePrimaryPartitions.swift') source = source
      .replaceAll('      AgentKnowledgeSQLiteStatements.shared.markFailed(statement)\n', '')
      .replace('$0.baseAddress, count, Self.transient) }) == SQLITE_OK else {\n      throw AgentKnowledgeDatabaseError.unavailable\n    }',
        '$0.baseAddress, count, Self.transient) }) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }');
  }
  if (fixtures.some(n => f === tests + n + '.swift')) source = source.replaceAll('AgentKnowledgeSQLiteStatements.shared.close(', 'sqlite3_close_v2(');
  return source;
}
function validate() {
  for (const name of production) {
    const f = app + name + '.swift', source = read(f);
    assert.equal(retained(f, source), old(f), name + ': SQL/schema/transactions/crypto unchanged');
    assert(source.includes('AgentKnowledgeSQLiteStatements.shared.prepare('), name + ': actual prepare routing');
    assert(source.includes('AgentKnowledgeSQLiteStatements.shared.release('), name + ': actual return routing');
    assert(!/sqlite3_(prepare_v2|finalize|close_v2)\(/.test(source), name + ': no unmanaged lifetime');
  }
  for (const name of fixtures) { const f = tests + name + '.swift'; assert.equal(retained(f, read(f)), old(f), name); }
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal(retained(project, read(project)), old(project));
  const guard = 'apps/ios/tools/check-knowledge-primary-allocations-scope.cjs';
  assert.equal(read(guard), old(guard)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = f => require('./check-knowledge-statements-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, source) {\n', "function retained(f, source) {\n  source = require('./check-knowledge-statements-scope.cjs').retained(f, source);\n"));
  const pool = read(app + 'AgentKnowledgeSQLiteStatements.swift');
  for (const text of ['capacity: Int = 32, maximumSQLCharacters: Int = 65_536', 'chars = sql.utf16.count',
    'active[entry.statement] = entry', 'idle.remove(at: index)', 'sqlChars -= entry.chars; reused += 1',
    'let reset = sqlite3_reset(entry.statement)', 'let cleared = sqlite3_clear_bindings(entry.statement)',
    '!entry.failed, reset == SQLITE_OK, cleared == SQLITE_OK', 'entry.chars <= maximumSQLCharacters',
    'sqlChars > maximumSQLCharacters - entry.chars', 'evict(duplicate)', 'evict(0)',
    '["SELECT", "INSERT", "UPDATE", "DELETE", "REPLACE"].contains(keyword)',
    '!closed, !lease.released, active[lease.entry.statement] === lease.entry',
    'guard !lease.released else { return SQLITE_OK }', 'lease.released = true',
    'catch { lease.entry.failed = true; throw error }', 'closed = true',
    'bytes == -1, tail == nil', 'Failure.empty { return SQLITE_OK }', 'Failure.sqlite(let code) { return code }',
    'direct[statement] = handle', 'connections.removeValue(forKey: handle)', 'pool?.close()',
    'for lease in leases { lease.close() }', 'for statement in raw { sqlite3_finalize(statement) }',
    'return sqlite3_close_v2(handle)', 'unpooled != nil ? sqlite3_finalize(statement) : SQLITE_MISUSE']) assert(pool.includes(text), text);
  assert(pool.indexOf('pool?.close()') < pool.indexOf('return sqlite3_close_v2(handle)'));
  const fixture = read(tests + 'AgentKnowledgeSQLiteStatementsTests.swift');
  assert.equal((fixture.match(/  func test/g) || []).length, 14);
  for (const text of ['SQLITE_NULL', 'XCTAssertNotEqual', 'SQLITE_CONSTRAINT', 'SQLITE_RANGE',
    'testSQLBudgetCountsUTF16UnitsLikeAndroid', 'testOldLeaseCannotReturnAnEntryTwiceAfterReuse',
    'testPragmaAndTransactionProgramsAreNeverRetainedIdle', 'testCompatibilityCloseDrainsOutstandingRawBorrows',
    'driver.release(statement), SQLITE_MISUSE', 'AgentKnowledgePrimaryPartitionsTests.Fixture()',
    'f.store.read(itemHash: f.key, catalog: f.catalog)', 'XCTAssertGreaterThan(after.reused, before.reused)']) assert(fixture.includes(text), text);
  console.log('Bounded connection-local statement reuse, real knowledge query routing, retained SQL/schema/effects and fourteen authored-only fixture source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
