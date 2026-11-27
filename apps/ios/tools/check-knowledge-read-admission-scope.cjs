const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => require('./check-knowledge-statements-scope.cjs').retained('apps/ios/GalaxySSI/' + name,
  fs.readFileSync(path.join(root, 'GalaxySSI', name), 'utf8').replace(/\r\n/g, '\n'));
const database = read('AgentKnowledgeDatabase.swift');
const search = database.slice(database.indexOf('  func searchCandidates('), database.indexOf('  private func committedReadView('));
assert.equal((search.match(/try committedReadView\(\)/g) || []).length, 2);
assert.doesNotMatch(search, /locked \{|prepare\("SELECT|while sqlite3_step/);
for (const value of ['try view.read', 'try committed.read', 'return try snapshotItems.filter',
  'try decode(row, hashColumn: 0, payloadColumn: 1) == candidate', 'status == SQLITE_DONE',
  'status == SQLITE_ROW', 'try Task.checkCancellation()', 'return try view.read { _ in validated }',
  'try beforeValidation()', 'indexRetry.markFailure(); requestIndexRetry()']) assert.ok(search.includes(value), value);
const admission = database.slice(database.indexOf('  private func committedReadView('), database.indexOf('  private func readCommitted<T>'));
assert.match(admission, /if lock\.try\(\)/);
assert.doesNotMatch(admission, /lock\.lock\(\)|locked \{/);
assert.match(admission, /sqlite3_get_autocommit\(database\) != 0/);
assert.match(admission, /nativeFiles\.readToken\(backgroundLease: backgroundLease\) == token/);
const view = read('AgentKnowledgeCommittedReadView.swift');
for (const value of ['SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX', 'PRAGMA query_only=ON',
  'PRAGMA cache_size=-2048', 'PRAGMA mmap_size=0', 'SELECT revision FROM knowledge_browse_revision WHERE id=1',
  'sqlite3_column_type(row, 0) == SQLITE_INTEGER', 'sqlite3_step(row) == SQLITE_DONE',
  'try Task.checkCancellation(); try checkActive()', 'activeReads > 0', 'sqlite3_close_v2(database)']) {
  assert.ok(view.includes(value), value);
}
assert.doesNotMatch(view, /immutable=1|SQLITE_OPEN_CREATE|INSERT INTO|UPDATE knowledge/);
const retry = read('AgentKnowledgeIndexRetryGate.swift');
for (const value of ['guard needed, !queued', 'queue.async', 'let success = repair()',
  'generation == admitted', 'queued = false', 'needed = true; generation = UUID()']) assert.ok(retry.includes(value), value);
const recovery = database.slice(database.indexOf('  private func rebuildIndexIfNeeded()'), database.indexOf('  private func searchTokens('));
assert.match(recovery, /guard let itemCount/);
assert.match(recovery, /return replaceAll\(items\)/);
assert.match(database, /if !rebuildIndexIfNeeded\(\) \{ indexRetry.markFailure\(\) \}/);
const all = database.slice(database.indexOf('  func all()'), database.indexOf('  func items(ids:'));
assert.ok(all.includes('if status == SQLITE_DONE { return items }'));
assert.ok(all.includes('guard status == SQLITE_ROW else'));
const tests = fs.readFileSync(path.join(root, 'GalaxySSITests', 'AgentKnowledgeReadAdmissionTests.swift'), 'utf8');
for (const name of ['IndependentViewPinsCommittedStateAndIsQueryOnly', 'HeldWriterDoesNotBlockCandidateReadOrFinalCommittedValidation',
  'SecondCommittedViewRejectsReplacementDeletionAndACLChanges', 'LifecycleGenerationChangeCannotPublishThroughANewerValidationView',
  'ReentrantSearchInsideOwnUncommittedWriterIsRejected', 'ValidationAuthenticatesCiphertextRatherThanTrustingStableSQLIdentity',
  'ViewRejectsCloseDuringReadAndLifecycleInvalidation', 'CancelledCandidatePublicationThrowsAfterValidationHook',
  'RetryHintIsDeduplicatedAndRunsOffCaller', 'FailedRepairAndFailureDuringRepairRemainEligibleForRetry',
  'KnownFailedBackfillIsRetriedAsynchronouslyWithoutDiscardingCorpus']) assert.ok(tests.includes(`func test${name}(`), name);
console.log('iOS committed read admission source checks passed (not native execution)');
