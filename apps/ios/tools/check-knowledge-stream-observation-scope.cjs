const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
require('./check-knowledge-source-replacement-scope.cjs');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, 'GalaxySSI', name), 'utf8');
const database = read('AgentKnowledgeDatabase.swift');
const replacement = database.slice(database.indexOf('  func replaceSource('), database.indexOf('  private func sourceRecord('));
assert.ok(replacement.indexOf('try stage.finishMutation()') < replacement.indexOf('knowledgeSourceMutation(stage: stage)'));
assert.ok(replacement.indexOf('try enqueueSourceObservation(event)') < replacement.indexOf('execute("COMMIT")'));
for (const text of ['func pendingSourceObservations(', '(1...64).contains(limit)', 'ORDER BY sequence LIMIT ?',
  'keyedHash(event.id) == hash', 'func acknowledgeSourceObservations(receipts:', 'WHERE receipt=?',
  'knowledge-observation:\\(receipt):\\(hash)', 'receipt TEXT NOT NULL UNIQUE,event_hash TEXT NOT NULL']) {
  assert.ok(database.includes(text), text);
}
const bulk = database.slice(database.indexOf('  func replaceAll('), database.indexOf('  func replaceSource('));
assert.ok(bulk.includes('DELETE FROM knowledge_source_observations'));
const stage = read('AgentKnowledgeSourceStaging.swift');
for (const text of ['func orderedVisit(', 'sqlite3_create_collation_v2', 'SOURCE_ORDER',
  'PRIMARY KEY(side,sort_key)', 'ORDER BY sort_key COLLATE SOURCE_ORDER', 'try orderKey(',
  'item.id.utf8.elementsEqual(key.id.utf8)', 'item.chunkIndex == key.chunk',
  'seen == (side == .incoming ? incomingCount : previousCount)', 'SQLITE_STMTSTATUS_SORT',
  'a.id.utf16.lexicographicallyPrecedes(b.id.utf16)', 'collationFailed = true',
  'func visitAllowed(', 'seen == allowedCount', 'if activeStatements > 0 { closing = true; return }']) {
  assert.ok(stage.includes(text), text);
}
const fold = read('GlobalPersistentContextObservations.swift');
const streaming = fold.slice(fold.indexOf('  private static func streamingKnowledgeSnapshot('), fold.indexOf('  private static func memoryUpserted('));
assert.doesNotMatch(streaming, /Dictionary\(grouping|items\.sorted|flatMap|allowedAgentIds\.sorted/);
for (const text of ['try stage.orderedVisit(side)', 'try stage.rememberAllowed(id)', 'try stage.visitAllowed',
  'digest.update(data:', '.prefix(2_001)', 'if tags.count > maxTags', 'contentFingerprint:', 'accessFingerprint:']) {
  assert.ok(streaming.includes(text), text);
}
const importer = read('AgentAttachmentKnowledgeImporter.swift');
assert.match(importer, /try store\.replaceAgentKnowledgeSourceCountChecked\(/);
assert.match(importer, /static func importDocumentsChecked/);
const store = read('GalaxySSIStoreKnowledge.swift');
const adapter = store.slice(store.indexOf('  private func replaceAgentKnowledgeSourceResult('), store.indexOf('  func upsertAgentKnowledge('));
assert.match(adapter, /AgentKnowledgeChunkSequence\(assessment.indexedContent\)/);
assert.doesNotMatch(adapter, /chunkKnowledgeContent\(|chunks\.count/);
const chunks = read('AgentKnowledgeChunkSequence.swift');
assert.doesNotMatch(chunks, /components\(separatedBy|\[String\]|Array\(/);
assert.match(chunks, /struct Iterator: IteratorProtocol/);
const tests = fs.readFileSync(path.join(root, 'GalaxySSITests', 'AgentKnowledgeSourceReplacementTests.swift'), 'utf8');
for (const name of ['StreamingObservationMatchesArraySnapshotAcrossPagesAndPolicyUnions',
  'OrderedVisitUsesRawUTF16IdentityAndCloseInsideConsumerFailsSafely',
  'SourceOutboxSurvivesReopenAndAcknowledgesOnlyExactReceipts',
  'OutboxAndCanonicalMutationRollbackTogetherOnPrecommitFailure',
  'LegacyBulkRestoreInvalidatesPendingObservationsAtomically',
  'OutboxPersistsOnlyCiphertextAndDetectsPayloadCorruption',
  'ChunkIteratorPreservesParagraphsLongSplitsUnicodeAndRepeatability',
  'CountImportUsesSameDurablePipelineAndDoesNotEmitPerChunkEvents']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
console.log('iOS streaming source observation/import source checks passed (not native execution)');
