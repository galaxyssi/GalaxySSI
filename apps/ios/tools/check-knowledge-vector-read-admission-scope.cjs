const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
require('./check-knowledge-read-admission-scope.cjs');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, 'GalaxySSI', name), 'utf8');
const database = read('AgentKnowledgeDatabase.swift');
const section = (from, to) => {
  const start = database.indexOf(from), end = database.indexOf(to, start + from.length);
  assert.ok(start >= 0 && end > start, from);
  return database.slice(start, end);
};
for (const [name, next] of [['vectorFeedStamp', 'nativePublicationPage'], ['nativePublicationPage', 'nativeRootSeed'],
  ['validatedLexicalHits', 'resolveNativeMatches'], ['resolveNativeMatches', 'vectorReplayPage'],
  ['vectorCatalog', 'vectorCatalogPage'], ['vectorCatalogPage', 'sourcePage'], ['vectorCheckpoints', 'clearVectorCheckpoints']]) {
  const code = section(`  func ${name}(`, `  func ${next}(`);
  assert.match(code, /readCommitted|registeredVectorRead/);
  assert.doesNotMatch(code, /try locked \{|BEGIN DEFERRED TRANSACTION/);
}
for (const [from, to] of [['  private func readVectorChangePage(', '  func vectorFeedStamp('],
  ['  private func readVectorReplayPage(', '  func pendingVectorItems(']]) {
  const code = section(from, to);
  assert.match(code, /on: connection/);
  assert.doesNotMatch(code, /try locked \{|BEGIN DEFERRED TRANSACTION|try vectorChangePage\(/);
}
const replay = section('  func vectorReplayPage(', '  private func readVectorReplayPage(');
assert.match(replay, /try beforeValidation\(\)/);
assert.match(replay, /== result.stamp else \{ return nil \}/);
assert.match(replay, /nativeFiles\.readToken\(backgroundLease: backgroundLease\) == token/);
const rootSeed = section('  func nativeRootSeed(', '  func validatedLexicalHits(');
assert.doesNotMatch(rootSeed, /lock\.lock\(\)|try locked \{/);
assert.match(rootSeed, /guard lock\.try\(\) else \{ return \}/);
assert.match(rootSeed, /sqlite3_busy_timeout\(database, 0\)/);
assert.match(rootSeed, /defer \{ sqlite3_busy_timeout\(database, 5_000\) \}/);
assert.match(rootSeed, /after_item_hash=excluded.after_item_hash/);
assert.ok(rootSeed.indexOf('return AgentKnowledgeNativeRootSeed(vector: vector') < rootSeed.indexOf('try saveRootSeekWithoutWaiting('));
assert.match(database, /readVectorCheckpoints\(itemId: checkpoint.itemId,[\s\S]*?on: database\)/);
assert.match(database, /catch \{ _ = execute\("ROLLBACK"\); return false \}/);
assert.match(database, /checkpoint.provenance.modelSHA256 == modelSHA256.lowercased\(\)/);
assert.match(database, /v.model_hash = r.model_hash AND v.item_hash = r.item_hash AND v.source_revision_hash = r.source_revision_hash/);
const files = read('AgentKnowledgeNativeFiles.swift');
assert.match(files, /if let backgroundLease \{ return validBackgroundLease\(backgroundLease\) \? generation : nil \}/);
assert.match(files, /lease.owner === self/);
assert.match(files, /backgroundLeases.contains\(lease.id\)/);
const driver = read('AgentKnowledgeNativeIndex.swift');
for (const text of ['backgroundLease: backgroundLease)', 'limit: 1, backgroundLease: backgroundLease)',
  'limit: 64, backgroundLease: backgroundLease)']) assert.ok(driver.includes(text), text);
const tests = fs.readFileSync(path.join(root, 'GalaxySSITests', 'AgentKnowledgeVectorReadAdmissionTests.swift'), 'utf8');
for (const name of ['WarmFeedCatalogCountReplayAndFinalResolutionDoNotWaitForSourceWriter',
  'RealNativeBootstrapReplayAndRankedSearchUnderHeldSourceWriter', 'ReplayRevalidatesAfterDecryptAndDropsChangedSource',
  'ResolutionAndLexicalValidationRejectChangesAfterDecode', 'LifecycleChangeBetweenViewsCannotPublishOldVectorResults',
  'ForeignAndEndedBackgroundLeasesCannotAuthorizeDatabaseReads',
  'BackgroundReadCapabilityDoesNotReenableForegroundOrSurviveProtectionLoss',
  'RealNativeBackgroundReplayKeepsReadLeaseThroughNestedCalls', 'ColdModelRegistrationAndVectorReadsSurviveDatabaseReopen',
  'CorruptEncryptedVectorDoesNotReturnPartialCatalogOrReplay', 'ForgedEpochAndFeedBoundsStillFailClosed',
  'WrongProvenanceCannotSupplyReplayOrNativeRootEvidence', 'WriterCompletionSeesItsOwnUncommittedFinalChunk',
  'CancelledReadCannotRegisterColdModel']) assert.ok(tests.includes(`func test${name}(`), name);
assert.match(tests, /let index = AgentKnowledgeNativeIndex\(database: database, provenance: spec\)/);
assert.match(tests, /index.search\(\[0.6, 0.8\]/);
console.log('iOS committed vector read admission source checks passed (not native execution)');
