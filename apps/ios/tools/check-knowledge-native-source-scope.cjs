const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, 'GalaxySSI', name), 'utf8');
const database = read('AgentKnowledgeDatabase.swift');
const vectors = read('AgentKnowledgeVectorModels.swift');
const search = read('AgentKnowledgeHybridSearch.swift');
assert.match(database, /knowledge_vector_model_key ON knowledge_vectors\(model_hash, vector_key\)/);
assert.match(database, /WHERE model_hash = \? AND vector_key > \?/);
assert.match(database, /ORDER BY vector_key ASC LIMIT \?/);
assert.match(database, /ids.count <= 256/);
assert.match(database, /let pageSize = min\(max\(limit, 1\), 256\)/);
assert.match(database, /checkpoint.validatedSourceRange\(in: current\) != nil/);
assert.match(database, /guard status == SQLITE_DONE else/);
assert.match(database, /guard stored, storeVectorReplayOrdinal\(checkpoint, vectorKey: vectorKey\) else/);
assert.match(database, /CREATE TABLE IF NOT EXISTS knowledge_vector_replay_rows/);
assert.match(database, /UNIQUE\(model_hash, item_hash, source_revision_hash, chunk_index\)/);
assert.match(database, /knowledge_vector_replay_delete AFTER DELETE ON knowledge_vectors/);
assert.match(read('AgentKnowledgeCommittedReadView.swift'), /BEGIN DEFERRED TRANSACTION/);
assert.match(read('AgentKnowledgeCommittedReadView.swift'), /SELECT revision FROM knowledge_browse_revision WHERE id=1/);
assert.match(database, /page.events.first == event/);
assert.match(database, /latestSequence == event.sequence/);
assert.match(database, /knowledge_vector_change_document ON knowledge_vector_changes\(model_hash, item_hash, sequence\)/);
assert.match(database, /available == Int64\(event.chunkCount\)/);
assert.match(database, /checkpoint.provenance == provenance/);
assert.match(database, /ORDER BY r.chunk_index ASC LIMIT \?/);
assert.match(database, /min\(min\(max\(limit, 1\), 64\), event.chunkCount - afterChunkIndex\)/);
assert.match(database, /event.sequence > expectedPrevious, event.sequence <= state.head/);
assert.match(vectors, /sourceStartUTF16: Int\?/);
assert.match(vectors, /sourceEndUTF16: Int\?/);
assert.match(vectors, /Self.sourceRevision\(for: item\) == sourceRevision/);
assert.match(vectors, /0xdc00\.\.\.0xdfff/);
assert.match(vectors, /afterUTF16: sourceCursor/);
assert.match(vectors, /sourceCursor = offsets.location \+ offsets.length/);
assert.match(search, /database.validatedLexicalHits\(/);
assert.match(search, /index.search\(queryVector/);
assert.doesNotMatch(search, /USearchIndex|loadCatalog|database\.all\(|database\.vectorCatalog|offset:/);
const tests = fs.readFileSync(path.join(root, 'GalaxySSITests', 'AgentKnowledgeDatabaseTests.swift'), 'utf8');
for (const name of ['SourceRangesLocateRepeatedChunksWithoutSplittingSurrogates',
  'SourceRangeStorageRoundTripAndLegacyCompatibility', 'SourceRangeRejectsPartialReversedOutOfBoundsAndStaleSource',
  'SourceRangeWriteRejectionPreservesVectorFeed', 'KeysetCatalogSurvivesReopenAndIsolatesModels',
  'BoundedSourceLookupDeduplicatesAndReflectsDeletion',
  'PublishedVectorReplayUsesBoundedOrdinalPagesAndResumesAfterReopen',
  'VectorReplayRejectsLegacyRangesAndForgedPublication',
  'VectorReplayRejectsRemovedReaddedAndPolicyChangedSources']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
console.log('iOS native knowledge source prerequisites: source checks passed (not native execution)');
