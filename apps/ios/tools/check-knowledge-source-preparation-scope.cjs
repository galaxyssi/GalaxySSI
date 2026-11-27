const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
require('./check-knowledge-stream-observation-scope.cjs');
require('./check-knowledge-vector-read-admission-scope.cjs');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, 'GalaxySSI', name), 'utf8');
const database = read('AgentKnowledgeDatabase.swift');
const section = (from, to) => {
  const start = database.indexOf(from), end = database.indexOf(to, start + from.length);
  assert.ok(start >= 0 && end > start, from); return database.slice(start, end);
};
const preparation = section('  func prepareSourceReplacement(', '  func commitSourceReplacement(');
assert.doesNotMatch(preparation, /try locked|BEGIN IMMEDIATE|execute\("COMMIT/);
assert.doesNotMatch(preparation, /requestIndexRetry|try readCommitted/);
for (const text of ['let view = try committedReadView()', 'defer { view.close() }', 'return try view.read { connection', 'sourceGeneration(hash: sourceHash, on: connection)',
  'sourceRecord(hash: key, on: connection)', 'ORDER BY item_hash LIMIT 64', 'try onPage(count)',
  'key < policy!.itemKey', 'try stage.finishPrevious()', 'nativeFiles.readToken() == token']) assert.ok(preparation.includes(text), text);
const commit = section('  func commitSourceReplacement(', '  private func validatePreparedIdentity(');
assert.doesNotMatch(commit, /sourceRecord\(|SELECT item_hash FROM knowledge_items WHERE source_hash/);
for (const text of ['try prepared.claim(for: self)', 'try prepared.checkActive()', 'BEGIN IMMEDIATE',
  'sourceGeneration(hash: sourceHash) == prepared.revision', 'sourceReplacementChanged',
  'try validatePreparedIdentity', 'try prepared.commitCanonical', 'prepared.failed()', 'if !committed']) assert.ok(commit.includes(text), text);
assert.ok(commit.indexOf('sourceGeneration(hash:') < commit.indexOf('try validatePreparedIdentity'));
assert.ok(commit.indexOf('try validatePreparedIdentity') < commit.indexOf('try removeSourceRecord'));
const identity = section('  private func validatePreparedIdentity(', '  private func sourceRecord(');
assert.match(identity, /SELECT source_hash FROM knowledge_items WHERE item_hash=\?/);
assert.match(identity, /try stage.hasPreparedIdentity\(id\)/);
assert.match(identity, /guard prepared, String\(cString: source\) == sourceHash/);
assert.doesNotMatch(identity, /decrypt\(|decode\(|sourceRecord\(/);
for (const text of ['source_generation_schema', 'SELECT generation FROM knowledge_source_generations',
  "CHECK(typeof(generation)='integer' AND generation>0)", 'knowledge_source_generation_insert',
  'knowledge_source_generation_delete', 'knowledge_source_generation_update', 'knowledge_source_generation_move',
  'ON CONFLICT(source_hash) DO UPDATE SET generation=generation+1', 'if version == 0',
  'SELECT DISTINCT source_hash,1 FROM knowledge_items', '_ = setupSourceGenerations()']) assert.ok(database.includes(text), text);
const prepared = read('AgentKnowledgePreparedSourceReplacement.swift');
for (const text of ['owner === database', 'state == .ready', 'state = .applying', 'state == .applying, !closeRequested',
  'try commit()', 'state = .consumed; stage = nil', 'closeRequested = true', 'owned?.close()',
  'owner.nativeFiles.readToken() == token']) assert.ok(prepared.includes(text), text);
const importer = read('AgentAttachmentKnowledgeImporter.swift');
assert.match(importer, /return try attachments.reduce/);
assert.match(importer, /try store.replaceAgentKnowledgeSourceCountChecked/);
const store = read('GalaxySSIStoreKnowledge.swift');
const checked = store.slice(store.indexOf('  private func replaceAgentKnowledgeSourceResult('), store.indexOf('  func upsertAgentKnowledge('));
assert.match(checked, /throws ->/); assert.doesNotMatch(checked, /catch|try\?/);
const web = read('AgentIOSWebKnowledgeImporter.swift');
assert.match(web, /catch AgentKnowledgeDatabaseError.sourceReplacementChanged/);
assert.match(web, /code: "knowledge_source_changed"/);
const services = read('GalaxySSIServices.swift');
assert.match(services, /try settingsStore.replaceAgentKnowledgeSourceChecked/);
assert.match(services, /try AgentAttachmentKnowledgeImporter.importDocumentsChecked/);
assert.match(services, /agent_attachment_knowledge_conflict/);
assert.match(read('GalaxySSIAgentKnowledgeView.swift'), /catch AgentKnowledgeDatabaseError.sourceReplacementChanged/);
assert.match(fs.readFileSync(path.join(root, 'GalaxySSI/zh-Hans.lproj/Localizable.strings'), 'utf8'), /"galaxyssi.agent_knowledge.source_changed" =/);
const tests = fs.readFileSync(path.join(root, 'GalaxySSITests/AgentKnowledgeSourcePreparationTests.swift'), 'utf8');
for (const name of ['PreparationCompletesUnderHeldSourceWriterAndConflictsAfterItsCommit',
  'PagedPreparationAllowsUnrelatedSourceCommitAndKeepsItsSnapshot', 'SourceBodyAndPermissionChangesConflictWithoutOverwritingOrEmittingEvents',
  'DeletionAndIdenticalRecreationAreNotAnABABypass', 'InitiallyAbsentSourceDetectsCreationAndCreationDeletionABA',
  'IncomingIdentityClaimedElsewhereAfterPreparationIsRejectedInsideWriter', 'SuccessfulPreparedCommitIsSingleUseAndTransfersScratchLifetime',
  'ConflictConsumesPreparationAndRequiresFreshPreparation', 'ForeignDatabaseCannotConsumePreparedOperation',
  'CloseBeforeCommitRejectsAndCloseDuringApplyRollsBack', 'PreparationCallbackFailureLeavesCanonicalStoreUnchanged',
  'NoopDoesNotInvalidateAnExistingPreparation', 'LifecycleInvalidationAndApplyFailureRollbackAndConsume',
  'GenerationMigrationDoesNotRewriteExistingBodyCiphertext', 'GenerationOverflowFailsClosedWithoutLosingOriginalRecord',
  'NewVectorEvidenceDoesNotConflictButIsInvalidatedBySourceCommit',
  'WebImportReportsConflictWithoutAcknowledgingOrAutomaticallyRetrying']) assert.ok(tests.includes(`func test${name}(`), name);
console.log('iOS outside-writer source preparation source checks passed (not native execution)');
