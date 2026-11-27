// Source contracts only; no Swift compilation or native SQLite/XCTest execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'bfcd499370441adfa07ff6361e422e4bb997b1ac';
const integrated = 'a5d92e61c98c6a8ece94cb925bd07b49fd99a339';
const app = 'apps/ios/GalaxySSI/', tests = 'apps/ios/GalaxySSITests/';
const production = ['AgentKnowledgeDatabase', 'AgentKnowledgePrimaryPartitions', 'AgentKnowledgePrimaryAllocations', 'AgentKnowledgePrimaryDurability',
  'AgentKnowledgeCommittedReadView', 'AgentKnowledgeSourceStaging'];
const fixtures = ['AgentKnowledgePrimaryPartitionsTests', 'AgentKnowledgePrimaryDurabilityTests'];
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const integratedSource = f => cp.execFileSync('git', ['show', integrated + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function predecessor(f) {
  if (f === app + 'AgentKnowledgeDatabase.swift') return integratedSource(f).replace(
    '    _ = execute("PRAGMA journal_mode = WAL")\n    _ = execute("PRAGMA synchronous = FULL")',
    '    do { try AgentKnowledgePrimaryDurability.configure(database, role: .catalog) }\n    catch { sqlite3_close_v2(database); self.database = nil; return }');
  if (['AgentKnowledgeCommittedReadView', 'AgentKnowledgeSourceStaging'].some(n => f === app + n + '.swift')) return integratedSource(f);
  return old(f);
}
function retained(f, source) {
  if (f.endsWith('check-knowledge-primary-allocations-scope.cjs')) return source
    .replace("  assert.equal(require('./check-knowledge-primary-durability-scope.cjs').retained(project, read(project)),\n    cp.execFileSync('git', ['show', 'a5d92e61c98c6a8ece94cb925bd07b49fd99a339:' + project], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\\r\\n/g, '\\n'));",
      '  assert.equal(retained(project, read(project)), old(project));')
    .replace('    .replace("base = \'97374e5882356fd28a3a251873b6c5cd7dfa6a54\'", "base = \'a5d92e61c98c6a8ece94cb925bd07b49fd99a339\'")\n', '')
    .replace("'AgentKnowledgePrimaryReaderSlots', 'AgentKnowledgeStorageBackground']) assert.equal(read(app + name + '.swift'),\n      name === 'AgentKnowledgeDatabase' ? require('./check-knowledge-statements-scope.cjs').predecessor(app + name + '.swift') : old(app + name + '.swift'), name);",
      "'AgentKnowledgePrimaryReaderSlots', 'AgentKnowledgeStorageBackground']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);");
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(l => !/AgentKnowledgeSQLiteStatements(?:Tests)?\.swift/.test(l)).join('\n');
  if (production.some(n => f === app + n + '.swift')) {
    if (f === app + 'AgentKnowledgeCommittedReadView.swift') source = source.replace(
      '      // This private view owns the handle, including any escaped raw cursors.\n      AgentKnowledgeSQLiteStatements.shared.close(database, finalizingUnmanaged: true); self.database = nil',
      '      // No active callback remains; do not release retention on a zombie handle.\n      while let statement = sqlite3_next_stmt(database, nil) { sqlite3_finalize(statement) }\n      sqlite3_close_v2(database); self.database = nil');
    if (f === app + 'AgentKnowledgeSourceStaging.swift') source = source.replace(
      '    do { return try work(row) }\n    catch { AgentKnowledgeSQLiteStatements.shared.markFailed(row); throw error }',
      '    return try work(row)');
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
    assert.equal(retained(f, source), predecessor(f), name + ': SQL/schema/transactions/crypto unchanged');
    assert(source.includes('AgentKnowledgeSQLiteStatements.shared.prepare('), name + ': actual prepare routing');
    assert(source.includes('AgentKnowledgeSQLiteStatements.shared.release('), name + ': actual return routing');
    assert(!/sqlite3_(prepare_v2|finalize|close_v2)\(/.test(source), name + ': no unmanaged lifetime');
  }
  for (const name of fixtures) { const f = tests + name + '.swift'; assert.equal(retained(f, read(f)), old(f), name); }
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  assert.equal(require('./check-knowledge-primary-durability-scope.cjs').retained(project, read(project)), integratedSource(project));
  const guard = 'apps/ios/tools/check-knowledge-primary-allocations-scope.cjs';
  assert.equal(retained(guard, read(guard)), old(guard)
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
  assert.equal((fixture.match(/  func test/g) || []).length, 19);
  for (const text of ['SQLITE_NULL', 'XCTAssertNotEqual', 'SQLITE_CONSTRAINT', 'SQLITE_RANGE',
    'testSQLBudgetCountsUTF16UnitsLikeAndroid', 'testOldLeaseCannotReturnAnEntryTwiceAfterReuse',
    'testPragmaAndTransactionProgramsAreNeverRetainedIdle', 'testCompatibilityCloseDrainsOutstandingRawBorrows',
    'driver.release(statement), SQLITE_MISUSE', 'AgentKnowledgePrimaryPartitionsTests.Fixture()',
    'f.store.read(itemHash: f.key, catalog: f.catalog)', 'XCTAssertGreaterThan(after.reused, before.reused)']) assert(fixture.includes(text), text);
  for (const name of ['OwnedCloseDrainsIdleManagedAndUnmanagedPrograms',
    'GenericCloseDoesNotFinalizeAnUnrelatedStandalonePoolLease',
    'ActualCommittedViewReusesInitializationQueryAndDrainsOnClose',
    'ActualSourceStagingReuseKeepsIdentityAndBindingIsolation', 'SourceStagingCallbackFailureDoesNotPoisonLaterReads']) assert(fixture.includes('func test' + name + '('), name);
  assert(pool.includes('finalizingUnmanaged: Bool = false'));
  assert(pool.indexOf('for lease in leases { lease.close() }') < pool.indexOf('if finalizingUnmanaged {'));
  assert(pool.indexOf('while let statement = sqlite3_next_stmt(handle, nil)') < pool.indexOf('return sqlite3_close_v2(handle)'));
  const view = read(app + 'AgentKnowledgeCommittedReadView.swift');
  assert(view.indexOf('close(database, finalizingUnmanaged: true)') < view.indexOf('primarySnapshotLease = nil'));
  assert(read(app + 'AgentKnowledgeSourceStaging.swift').includes('catch { AgentKnowledgeSQLiteStatements.shared.markFailed(row); throw error }'));
  console.log('Bounded connection-local statement reuse, real knowledge query routing, retained SQL/schema/effects and nineteen authored-only fixture source contracts passed; no native acceptance.');
}
module.exports = {retained, validate, predecessor};
if (require.main === module) validate();
