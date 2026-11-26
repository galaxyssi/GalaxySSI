// Source contracts only, not native SQLite/crypto/migration/locking/latency evidence.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '0cd326c54bb1932bd57910d9fc72de4f3fe118c0';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));

function retainedWorkspaceCore(source) {
  assert.equal(source.split('\nenum AgentWorkspaceStoreBounds {').length, 2);
  return source.replace('\nenum AgentWorkspaceStoreBounds {', '\nprivate enum AgentWorkspaceStoreBounds {');
}
function retainedWorkspaceDefault(source) {
  assert.equal(source.split('IndexedAgentWorkspaceStore()').length, 2);
  return source.replace('IndexedAgentWorkspaceStore()', 'FileAgentWorkspaceStore()');
}
function validateIndexedWorkspace() {
  assert.equal(retainedWorkspaceCore(read(app + 'AgentWorkspaceStore.swift')), old(app + 'AgentWorkspaceStore.swift'),
    'Only share the existing size-fitting policy; protocol, revision/identity, reducers, codecs and recovery predicates unchanged');
  for (const file of ['FileAgentWorkspaceStore', 'AgentWorkspaceBoundsPolicy', 'AgentWorkspaceModels',
    'GalaxySSIHealthCareTaskStore', 'GalaxySSIHealthCareTaskRuntime'])
    assert.equal(read(app + file + '.swift'), old(app + file + '.swift'), file + ' retained');
  for (const file of ['GalaxySSIStore', 'AgentTaskRuntime', 'AgentRunRecoveryCoordinator'])
    assert.equal(retainedWorkspaceDefault(read(app + file + '.swift')), old(app + file + '.swift'),
      file + ': only real default store changes; lifecycle/recovery/permission/routing behavior retained');
  const store = read(app + 'IndexedAgentWorkspaceStore.swift');
  for (const token of ['NSRecursiveLock', 'legacyURL.standardizedFileURL.path',
    'let current = try db.workspace(id)', 'InMemoryAgentWorkspaceStore(initialWorkspaces: current.map { [$0] } ?? [], clock: clock)',
    'try db.persist(updated)', 'try db.transaction(willWrite: { changed })',
    'try reducer.delete(id, expectedRevision: expectedRevision)', 'if changed { notify() }',
    'storage: .indexedTransaction', 'records(recoverableOnly: true)',
    'receipt == nil || receipt == "pending" || receipt == "1", receipt == nil || exists',
    'guard !exists, receipt == nil', 'data.count == 32', 'try secrets.setString("pending"',
    'try db.initialize(allowImport: receipt != "1")', 'try AgentWorkspaceJsonCodec.decodePersistedList(raw)',
    'AgentWorkspaceJsonCodec.maxSerializedCharacters * 4', 'try secrets.setString("1"',
    'try? FileManager.default.removeItem(at: legacyURL)', 'var legacyCleanupPending: Bool',
    'path.prefix(components.count).elementsEqual(components)', 'workspace.index.master.v1.', 'workspace.index.import.v1.'])
    assert(store.includes(token), token);
  assert(store.indexOf('try db.initialize(') < store.indexOf('try secrets.setString("1"'));
  assert(store.indexOf('try secrets.setString("1"') < store.indexOf('try? FileManager.default.removeItem(at: legacyURL)'));
  const change = store.slice(store.indexOf('  private func change('), store.indexOf('  private func index()'));
  assert(change.indexOf('try db.transaction(') < change.indexOf('let current = try db.workspace(id)'));
  assert(change.indexOf('try db.persist(updated)') < change.indexOf('timingSink('));
  assert(!change.includes('.list()') && !change.includes('.records('));
  const db = read(app + 'AgentWorkspaceIndexDatabase.swift');
  for (const token of ['SQLITE_OPEN_FULLMUTEX', 'PRAGMA journal_mode=WAL', 'PRAGMA synchronous=FULL',
    'PRAGMA fullfsync=ON', 'PRAGMA cache_size=-512', 'PRAGMA mmap_size=0',
    'CREATE INDEX IF NOT EXISTS workspace_recovery', 'CREATE INDEX IF NOT EXISTS workspace_recency',
    'workspace_key TEXT PRIMARY KEY', 'BEGIN IMMEDIATE TRANSACTION', 'try? execute("ROLLBACK")',
    'if willWrite() { try beforeCommit() }', 'try execute("COMMIT")',
    'galaxyssi.workspace.rows.v1', 'galaxyssi.workspace.keys.v1', 'HKDF<SHA256>', 'HMAC<SHA256>',
    'AES.GCM.open', 'authenticating: aad(purpose)', 'purpose: "migration"',
    'purpose: "metadata:" + id', 'purpose: "workspace:" + id', 'try metadata(value) == meta',
    ' WHERE recoverable=1', ' WHERE workspace_key=?', ' LIMIT 65',
    'metadataRows().filter', 'retained.sort(by: oldestFirst)', 'retained.removeFirst(retained.count - count)',
    'retained.firstIndex(where: { $0.terminal }) ?? 0', 'AgentWorkspaceStoreBounds.fitSerializedLimit([workspace])',
    'envelope + retained.reduce(0) { $0 + $1.characters } + max(0, retained.count - 1)',
    'try remove(old.id)', 'if ids.contains(workspace.workspaceId) { try put(persisted) }',
    'AgentWorkspaceJsonCodec.encodeList([value]).count - AgentWorkspaceJsonCodec.emptyDocument().count',
    'completeUntilFirstUserAuthentication', '.posixPermissions: 0o700', '.posixPermissions: 0o600',
    'resources.isExcludedFromBackup = true', '!= .typeSymbolicLink']) assert(db.includes(token), token);
  const metadataRead = db.slice(db.indexOf('  private func metadataRows()'), db.indexOf('  private func readMetadata('));
  assert(!metadataRead.includes(',payload') && !metadataRead.includes('didDecodeBody()'));
  assert(db.includes('func clear() throws { try execute("DELETE FROM workspace_rows") }'), 'Clear retains the migration marker');
  const tests = read('apps/ios/GalaxySSITests/AgentWorkspaceIndexedStoreTests.swift');
  for (const name of ['LegacyImportRetiresPlaintextAndScopesBodyDecoding', 'IndexedMutationsKeepReferenceReducerAndRecoveryBehavior',
    'MigrationRollbackRetryAndCommittedMarkerPreventResurrection', 'FailedIndexCommitPreservesEvictionRecoveryAndNotifications',
    'IndependentDatabaseHandlesCompareRevisionInsideTheTransaction', 'CommittedKeyOrIndexLossCannotCreateReplacementOrReimport',
    'IndexedRetentionMatchesCountSizeAndTiePolicies', 'WrongNamespaceAndMalformedLegacyAreRejectedWithoutOverwrite'])
    assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['IndexedAgentWorkspaceStore', 'AgentWorkspaceIndexDatabase', 'AgentWorkspaceIndexedStoreTests'])
    assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedWorkspaceCore, retainedWorkspaceDefault, validateIndexedWorkspace};
if (require.main === module) {
  validateIndexedWorkspace();
  console.log('iOS production indexed workspace, scoped reads, atomic revision/retention/recovery and fenced migration source contracts passed; no native acceptance');
}
