const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const store = read('GalaxySSI/GalaxySSIStoreKnowledge.swift');
assert.match(store, /func searchAgentKnowledgeHybrid/);
assert.match(store, /func retrieveAgentKnowledge/);
assert.match(store, /let candidates = try database.searchCandidates\(query: cleanQuery, limit: 256\)/);
assert.match(store, /AgentKnowledgeSemanticController.shared\(database: database\)/);
assert.match(store, /database.validatedLexicalHits\(bounded, stamp: stamp/);
assert.match(store, /database.nativeFiles.activeToken\(\) == token/);
assert.match(store, /AgentKnowledgeRetriever.retrieve\(hits: hits, query: query, targetId: targetId/);
const router = read('GalaxySSI/AgentPersonalDataCommandRouter.swift');
assert.match(router, /semanticQuery: AgentKnowledgeSemanticQuery\? = nil\) async throws -> Result\?/);
assert.match(router, /try await store.searchAgentKnowledgeHybrid/);
assert.match(router, /try await store.retrieveAgentKnowledge/);
assert.match(router, /let hits = store.searchAgentKnowledge\(query, limit: 500\)/);
const services = read('GalaxySSI/GalaxySSIServices.swift');
const start = services.indexOf('      let dataScope = store.agentKnowledgeDatabase.nativeFiles.token()');
const end = services.indexOf('    if contact.id == "hermes",', start);
assert.ok(start >= 0 && end > start);
const scoped = services.slice(start, end);
assert.match(scoped, /try await AgentPersonalDataCommandRouter.handle/);
assert.match(scoped, /defer \{ if knowledgeRead \{ finishPendingAgentReply/);
assert.ok(scoped.indexOf('nativeFiles.token() == dataScope') < scoped.indexOf('store.appendIncoming('));
const view = read('GalaxySSI/GalaxySSIAgentKnowledgeView.swift');
assert.match(view, /try await store.searchAgentKnowledgeHybrid/);
assert.match(view, /\.onDisappear \{ clearSearchResults\(\) \}/);
assert.match(view, /if phase != .active \{ clearSearchResults\(\) \}/);
const search = read('GalaxySSI/AgentKnowledgeHybridSearch.swift');
assert.match(search, /onCancel: \{ self.cancelRequest\(requestId\) \}/);
assert.match(search, /if activeRequest == id \{ index.cancelCurrentSession\(\) \}/);
assert.match(search, /index.cancellationCheck = \{ false \}/);
assert.match(search, /cancelledRequests.remove\(id\)/);
const cancellation = search.slice(search.indexOf('  private func cancelRequest'), search.indexOf('  @discardableResult'));
assert.doesNotMatch(cancellation, /nativeFiles.invalidate|clearTransientIndex/);
const index = read('GalaxySSI/AgentKnowledgeNativeIndex.swift');
assert.match(index, /private weak var cancellableSession/);
assert.match(index, /guard !cancellationCheck\(\)/);
const tests = read('GalaxySSITests/AgentKnowledgeAsyncRAGTests.swift');
for (const name of ['SearchUsesSemanticCandidatesWithoutLexicalOverlap', 'RAGPreservesCloudSummaryAndSelectedAgentPolicies',
  'RAGDropsPolicyChangedOrDeletedHitsAfterAwait', 'ResetOrCancelledCommandsDoNotProduceReadAudits',
  'ReadCommandsUseHybridResultsAndRecordCurrentAudits', 'DestructiveCommandsNeverUseTheSemanticBoundary',
  'EmptyOrZeroLimitSearchSkipsNativeExecution']) {
  assert.ok(tests.includes(`func test${name}(`), name);
}
assert.match(read('GalaxySSITests/AgentKnowledgeNativeIndexTests.swift'), /func testRequestCancellationDoesNotRotateDatabaseScopeOrCancelAnotherOwner/);
assert.match(read('GalaxySSI.xcodeproj/project.pbxproj'), /AgentKnowledgeAsyncRAGTests.swift in Sources/);
console.log('iOS async Agent/RAG and per-request cancellation source checks passed; no native execution');
