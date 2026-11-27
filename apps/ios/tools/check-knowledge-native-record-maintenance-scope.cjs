// Static scope and call-path checks only, not Swift/Rust/native acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const app = 'apps/ios/GalaxySSI/', native = 'apps/ios/memory-native/';
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function has(s, values) { for (const value of values) assert(s.includes(value), value); }
const index = read(app + 'AgentKnowledgeNativeIndex.swift');
const maintenance = section(index, '  // Explicit maintenance only.', '  func search(_ vector:');
assert.equal(index.replace(maintenance, '').replace('  func recordsPartitioned() throws -> Bool\n  func migrateRecords(limit: Int) throws -> Bool\n', ''), old(app + 'AgentKnowledgeNativeIndex.swift'));
has(maintenance, ['backgroundLease != nil', '(1...256).contains(pageSize)', 'generation == token', 'try active(token)',
  'session.recordsPartitioned()', 'if partitioned { return true }', 'session.migrateRecords(limit: pageSize)', 'catch { close(); throw error }']);
assert.equal((maintenance.match(/try active\(token\)/g) || []).length, 3);
const bridge = read(app + 'AgentKnowledgeNativeBridge.swift');
const flags = section(bridge, '  func recordsPartitioned()', '  func cancel()');
assert.equal(bridge.replace(flags, ''), old(app + 'AgentKnowledgeNativeBridge.swift'));
has(flags, ['gs_memory_records_partitioned($0, $1)', 'gs_memory_migrate_records($0, UInt32(limit), $1)',
  '(1...256).contains(limit)', 'id > 0', 'call(id, &complete) == 0, complete <= 1']);
const controllerPath = app + 'AgentKnowledgeSemanticModel.swift', controller = read(controllerPath);
const background = section(controller, '  func runBackgroundSlice(', '  private func ensureRuntime()');
has(background, ['native.advance(maxPages: 4, token: lease.token)', 'native.maintainRecords(pageSize: 64, token: lease.token)',
  'native.needsReplay || !recordsComplete', 'await opened.close()']);
assert.equal(controller.replace('      let recordsComplete = try await Task.detached(priority: .utility) {\n        try native.maintainRecords(pageSize: 64, token: lease.token)\n      }.value\n      try check()\n', '')
  .replace(' || !recordsComplete', '').replace('      // Foreground replay readiness says nothing about the native record layout.\n      // Let a system-granted slice query/migrate it before clearing durable intent.\n', '')
  .replace('      AgentKnowledgeBackgroundScheduler.schedule(pending: state.enabled && state.installed)\n', '      AgentKnowledgeBackgroundScheduler.schedule(pending: state.enabled && state.installed && successor)\n')
  .replace('      var interrupted = false\n', '      var interrupted = false\n      var successor = true\n')
  .replace('          if indexed == 0 && !enrollmentPending && nativeEnrollmentComplete && !replayPending {\n', '          if indexed == 0 && !enrollmentPending && nativeEnrollmentComplete && !replayPending {\n            successor = !canUseNativeIndex\n'), old(controllerPath));
const lib = read(native + 'src/lib.rs');
const entry = section(lib, '#[unsafe(no_mangle)]\npub unsafe extern "C" fn gs_memory_records_partitioned', '#[unsafe(no_mangle)]\npub extern "C" fn gs_memory_cancel');
assert.equal(lib.replace(entry, ''), old(native + 'src/lib.rs'));
has(entry, ['aligned(complete)', 'complete.write(0)', 'owner::access(handle', 'engine.index.records_partitioned()',
  '(1..=256).contains(&limit)', 'engine.index.migrate_records(limit as usize)', 'complete.write(u8::from(value))']);
const symbols = read(native + 'exports.txt').trim().split('\n');
assert.equal(symbols.length, 10); assert.equal(new Set(symbols).size, 10);
for (const symbol of symbols) {
  const name = symbol.slice(1);
  assert(lib.includes('fn ' + name + '(')); assert(read(native + 'include/GalaxySSIMemory.h').includes('int32_t ' + name + '('));
}
const shared = 'apps/android/memory-native/src/';
for (const f of ['replay/mod.rs', 'sqlite_store/record_migration.rs', 'sqlite_store/records.rs', 'sqlite_store/codec.rs']) assert.equal(read(shared + f), old(shared + f));
for (const f of [native + 'Cargo.toml', native + 'Cargo.lock', native + 'src/owner.rs', native + 'src/buffers.rs',
  app + 'AgentKnowledgeNativeFiles.swift', app + 'AgentKnowledgeBackgroundScheduler.swift', app + 'AgentKnowledgeHybridSearch.swift']) assert.equal(read(f), old(f));
const swiftTests = read('apps/ios/GalaxySSITests/AgentKnowledgeNativeIndexTests.swift');
assert.equal((swiftTests.match(/func test/g) || []).length, 14);
has(swiftTests, ['testReadyGraphStillMigratesOneBoundedRecordPage', 'testForegroundReplayAndSearchNeverMigrateRecords',
  'testLeaseExpiryDuringMigrationRejectsLateCompletion', 'testIncompleteMigrationResumesAfterIndexOwnerRecreation']);
const rustTests = read(native + 'src/tests.rs');
assert.equal((rustTests.match(/#\[test\]/g) || []).length, 12);
assert(rustTests.startsWith(old(native + 'src/tests.rs')));
has(rustTests, ['record_maintenance_rejects_null_outputs_and_clears_error_flags',
  'partitioned_store_maintenance_is_idempotent_and_preserves_replay_after_reopen', 'cancelled_or_closed_record_maintenance_cannot_claim_completion']);
console.log('Native record C exports, bounded background-only migration/intent, retained engine/replay and ten newly authored fixture contracts passed source checks; no native execution.');
