const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const database = read('GalaxySSI/AgentKnowledgeDatabase.swift');
assert.match(database, /knowledge_vector_publication_append AFTER INSERT ON knowledge_vector_changes/);
assert.match(database, /PRIMARY KEY\(model_hash, item_hash\)/);
assert.match(database, /knowledge_vector_publication_ready/);
assert.match(database, /native_publications_schema/);
assert.match(database, /UPDATE knowledge_vector_native_enrollment SET after_item_hash = '', complete = 0/);
assert.match(database, /let size = min\(max\(limit, 1\), 64\)/);
assert.match(database, /ORDER BY p.item_hash ASC LIMIT \?/);
assert.match(database, /hasNativePublication\(modelHash: modelHash/);
assert.match(database, /guard matches.count <= 256/);
assert.match(database, /guard try readVectorFeedStamp\(modelHash: modelHash, on: connection\) == stamp/);
assert.match(database, /guard try vectorFeedStamp\(modelSHA256: provenance.modelSHA256, backgroundLease: backgroundLease\) == stamp/);
assert.match(database, /CROSS JOIN knowledge_browse_revision/);
assert.match(database, /checkpoint.chunkCount\) == sqlite3_column_int64\(row, 4\)/);
assert.match(database, /checkpoint.sourceStartUTF16 == match.startUTF16/);
assert.match(database, /checkpoint.sourceEndUTF16 == match.endUTF16/);
assert.match(database, /let range = checkpoint.validatedSourceRange\(in: item\)/);
assert.match(database, /String\(item.content\[range\].prefix\(360\)\)/);
assert.match(database, /sqlite3_column_int64\(latest, 3\) == Int64\(max\(chunkCount, 0\)\)/);
assert.doesNotMatch(database, /return ensureVectorFeedModel/);
const tests = read('GalaxySSITests/AgentKnowledgeNativePublicationTests.swift');
for (const name of ['PublicationPagesTrackLatestReadyRemovalAndReaddition',
  'ResolutionUsesAuthenticatedChunkAndCurrentPolicy', 'SourcePolicyMutationWithoutFeedAppendInvalidatesOldBatch',
  'OldNativePublicationCannotResolveAfterRemoveAndReadd', 'PublicationSchemaUpgradeReenrollsInsteadOfInventingHistory',
  'FailedFeedRegistrationThrowsWithoutRecursiveRetry']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
assert.match(read('GalaxySSI.xcodeproj/project.pbxproj'), /AgentKnowledgeNativePublicationTests.swift in Sources/);
console.log('iOS native publication and source resolution checks passed; not native execution');
