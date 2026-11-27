const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, 'GalaxySSI', name), 'utf8');
const database = read('AgentKnowledgeDatabase.swift');
const replacement = database.slice(database.indexOf('  func replaceSource('), database.indexOf('  private func insert(_ item:'));
assert.ok(replacement.length > 1000);
assert.doesNotMatch(replacement, /replaceAll\(|\.all\(|sourceGroups\(|orphanedVectorDocuments\(/);
for (const text of ['while let item = try next()', 'try stage.finishIncoming()', 'BEGIN IMMEDIATE',
  'ORDER BY item_hash LIMIT 64', 'try stage.rememberPrevious(old)', 'old.updatedAtMillis < policy!',
  'key < policy!.itemKey', 'try stage.finishPrevious()', 'comparable == old',
  'try stage.normalized(item)', 'try stage.finishMutation()', 'try beforeCommit(stage)',
  'if !committed', 'ROLLBACK', 'if changed > 0', 'knowledge_browse_revision',
  'WHERE item_hash=?', 'SELECT model_hash,? FROM knowledge_vector_enrollment', 'operation: .removal']) {
  assert.ok(replacement.includes(text), text);
}
assert.ok(replacement.indexOf('try stage.finishIncoming()') < replacement.indexOf('try locked'));
assert.ok(replacement.indexOf('try stage.scan(.incoming)') < replacement.indexOf('try stage.scan(.previous)'));
assert.ok(replacement.indexOf('try beforeCommit(stage)') < replacement.indexOf('execute("COMMIT")'));
assert.match(database, /knowledge_source_keypage_idx ON knowledge_items\(source_hash, item_hash\)/);
const stage = read('AgentKnowledgeSourceStaging.swift');
for (const text of ['SymmetricKey(size: .bits256)', 'HMAC<SHA256>', 'AES.GCM.seal', 'AES.GCM.open',
  'authenticating: aad(key, side: side)', 'ORDER BY token LIMIT 64', 'previousCount', 'incomingCount',
  'token(item.id) == key', 'O_EXCL', 'O_NOFOLLOW', 'FileProtectionType.complete',
  'cipherKey = nil; tokenKey = nil', 'sqlite3_finalize(row)']) {
  assert.ok(stage.includes(text), text);
}
assert.doesNotMatch(stage, /UserDefaults|Keychain|persist.*Key|\.map\(.*content/);
const store = read('GalaxySSIStoreKnowledge.swift');
const adapter = store.slice(store.indexOf('  func replaceAgentKnowledgeSource('), store.indexOf('  func upsertAgentKnowledge('));
assert.match(adapter, /agentKnowledgeDatabase\.replaceSource\(sourceKey/);
assert.match(adapter, /chunksIterator\.next\(\)/);
assert.match(adapter, /beforeCommit: \{ stage in/);
assert.match(adapter, /guard mutation.changed > 0/);
assert.match(adapter, /publishingCommittedKnowledgeCache = true/);
assert.match(adapter, /publishingCommittedKnowledgeCache = false/);
assert.doesNotMatch(adapter, /replaceAll\(|previousPolicy/);
assert.match(read('GalaxySSIStore.swift'), /guard !publishingCommittedKnowledgeCache else \{ return \}/);
const tests = fs.readFileSync(path.join(root, 'GalaxySSITests', 'AgentKnowledgeSourceReplacementTests.swift'), 'utf8');
for (const name of ['StagingDeduplicatesFirstValidIdentityAndEncryptsAllBodyFiles', 'StagingRejectsBlankStableIdentity',
  'TamperedIncomingFailsAuthenticationBeforeCatalogMutation', 'ProducerIsConsumedOnceAndPagesMoreThan64OldRecords',
  'OwnershipConflictPreflightLeavesCiphertextAndRevisionUnchanged', 'FailureAfterFirstMutationRollsBackCatalogFTSAndHeaders',
  'PrecommitCacheReadFailureRollsBackCanonicalMutation', 'OldestPolicyNotFirstChunkControlsEntireReplacement',
  'EqualTimestampPolicyUsesCatalogKeyTieBreak', 'NoopPreservesPhysicalRowsTimestampRevisionVectorsAndFeed',
  'ReplacementInvalidatesOnlyChangedVectorsAndEnqueuesReplacement', 'EmptyProducerDeletesOnlySelectedSource',
  'ThrowingProducerLeavesExistingSourceUnchanged', 'StoreAdapterPublishesNormalizedCacheAndInvalidatesChangedVector',
  'BlankSummaryNormalizesWithoutChangingIncomingOrderWinner', 'CancellationAfterMutationRollsBackBeforeCommit']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
console.log('iOS encrypted source replacement source checks passed (not Swift execution)');
