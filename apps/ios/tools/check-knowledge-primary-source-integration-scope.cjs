const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
require('./check-knowledge-primary-partitions-scope.cjs').validate();
require('./check-knowledge-source-timing-scope.cjs');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const database = read('GalaxySSI/AgentKnowledgeDatabase.swift');
const start = database.indexOf('  func commitSourceReplacement(');
const commit = database.slice(start, database.indexOf('  private func validatePreparedIdentity(', start));
for (const text of ['try primaryPayloads.beginWriteBatch(catalog: database)',
  'defer { primaryPayloads.endWriteBatch(catalog: database) }',
  'try primaryPayloads.prepareBatchCommit(catalog: database, checkActive: { try prepared.checkActive() })']) assert.ok(commit.includes(text), text);
assert.ok(commit.indexOf('BEGIN IMMEDIATE') < commit.indexOf('beginWriteBatch('));
assert.ok(commit.indexOf('beginWriteBatch(') < commit.indexOf('sourceGeneration('));
assert.ok(commit.indexOf('try beforeCommit(stage)') < commit.indexOf('prepareBatchCommit('));
assert.ok(commit.indexOf('prepareBatchCommit(') < commit.indexOf('try prepared.commitCanonical'));
assert.ok(commit.indexOf('try prepared.commitCanonical') < commit.indexOf('execute("COMMIT")'));
const factory = database.slice(database.indexOf('  private func committedReadView('), database.indexOf('  private func readCommitted<'));
assert.ok(factory.indexOf('let primarySnapshotLease = try primaryPayloads.snapshotLease()') < factory.indexOf('return try AgentKnowledgeCommittedReadView('));
assert.match(factory, /primarySnapshotLease: primarySnapshotLease/);
const view = read('GalaxySSI/AgentKnowledgeCommittedReadView.swift');
assert.match(view, /self.primarySnapshotLease = primarySnapshotLease/);
const close = view.slice(view.indexOf('  func close()'));
assert.ok(close.indexOf('if activeReads > 0') < close.indexOf('primarySnapshotLease = nil'));
assert.ok(close.indexOf('sqlite3_close_v2(database)') < close.indexOf('primarySnapshotLease = nil'));
assert.ok(close.indexOf('sqlite3_next_stmt(database, nil)') < close.indexOf('sqlite3_close_v2(database)'));
const tests = read('GalaxySSITests/AgentKnowledgePrimarySourceIntegrationTests.swift');
for (const name of ['TargetedSourceCommitPublishesCompletePrimaryRecordsAndReopens',
  'TargetedSourcePrecommitFailureRollsBackPrimaryReferencesAndOutbox',
  'ActualCandidateReadRetainsPhysicalLeaseThroughValidation', 'CommittedViewRetainsLeaseUntilExplicitClose',
  'CloseInsideActiveReadDoesNotReleasePhysicalLeaseEarly', 'FailedViewInitializationReleasesPhysicalLease',
  'PreparedReplacementReadsPrimaryRecordsAndRetainsConflictFence',
  'CloseFinalizesLeakedCursorBeforeDroppingPhysicalLease']) assert.ok(tests.includes(`func test${name}(`), name);
console.log('iOS primary/source integration source checks passed (not native execution)');
