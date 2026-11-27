// Source contracts only; this does not execute SwiftSoup, XCTest, WebKit or live search.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const android = '65655f0c79c6ab04121150229a65b089180f82f2';
const base = '492bebe922013c2f707b38e4ddc849a655deba68';
const git = (...args) => cp.execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 16_000_000 });
const read = file => require('./check-web-fallback-scope.cjs').retainedFallbackFile(file,
  require('./check-web-network-assurance-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n')));
const swift = name => 'apps/ios/GalaxySSI/' + name + '.swift';
const parser = read(swift('AgentIOSPublicSearchParser'));
for (const token of ['import SwiftSoup', 'SwiftSoup.parse(source, baseURL)',
  'sourceVerificationRequired', '.b_ad, .ads, [data-text-ad]', 'h2 a[href]',
  'card.attr("mu")', 'seen.insert(url)', 'Data(base64Encoded: value)',
  'components.user == nil, components.password == nil', 'final.fragment = nil',
  'query.first(where: { $0.name == key })', 'seenSnippets.insert(text)']) assert(parser.includes(token), token);
assert(!parser.includes('WKWebView'));
const provider = require('./check-image-source-adapters-scope.cjs').retainedProvider(
  require('./check-json-search-adapters-scope.cjs').retainedJSONProvider(read(swift('AgentIOSURLSessionWebMediaProvider'))));
assert(provider.includes('results = try parseSearchResults('));
assert(provider.includes('baseURL: resource.finalURL'));
assert(provider.includes('AgentIOSPublicSearchParser.parse(html, baseURL: baseURL, limit: 100).filter'));
for (const token of ['"excerpt": .string(result.excerpt)', '"snippet": .string(result.excerpt)',
  'resultMetadata["unavailable_sources"]', '"error_code": .string(failure(error).error?.code',
  'return failure("source_verification_required", "Search source requires verification")']) assert(provider.includes(token));
assert(!provider.includes('private func normalizedSearchResultURL('));
assert(!provider.includes('private func duckDuckGoRedirectTarget('));
for (const token of ['if endpoint.imageSearch {', 'results = try AgentIOSPublicSearchParser.sogouImages(',
  'host: "pic.sogou.com", path: "/pics"', 'throw AgentIOSURLSessionWebError.unsupportedImageEngine',
  'result.image?["url"]?.stringValue ?? result.url', 'value["images"] = .array([.object(image)])']) assert(provider.includes(token));
for (const token of ['JSONSerialization.jsonObject', 'rows.prefix(100)', 'seen.insert(image)',
  'imageSearchURL(row["oriPicUrl"]) ?? imageSearchURL(row["picUrl"])',
  '"retrieval_status": .string("search_result_not_downloaded")', 'media["original_url"] = .string(original)']) assert(parser.includes(token));
const intelligence = require('./check-search-response-cache-scope.cjs').retainedResponseSearch(read(swift('AgentIOSURLSessionWebIntelligenceProvider')));
const cacheStore = require('./check-search-response-cache-scope.cjs').retainedResponseCache(read(swift('AgentIOSWebIntelligenceCache')));
const oldCacheStore = git('show', base + ':' + swift('AgentIOSWebIntelligenceCache'));
const indexedCache = require('./check-web-cache-index-scope.cjs');
const usesIndexedCache = indexedCache.isIndexedCache(cacheStore);
if (usesIndexedCache) indexedCache.validateIndexedCache();
else {
assert.equal(cacheStore.slice(0, cacheStore.indexOf('final class AgentIOSWebIntelligenceCacheStore')),
  oldCacheStore.slice(0, oldCacheStore.indexOf('final class AgentIOSWebIntelligenceCacheStore')),
  'Persisted document/watch schemas unchanged');
assert.equal(cacheStore.slice(cacheStore.indexOf('  private struct Snapshot:'), cacheStore.indexOf('  static let maxDocuments'))
  .replace('    var learnedSources: [AgentIOSLearnedWebSource]? = nil\n', '')
  .replace('    var sourceHealth: [AgentIOSWebSourceHealth]? = nil\n', ''),
  oldCacheStore.slice(oldCacheStore.indexOf('  private struct Snapshot:'), oldCacheStore.indexOf('  static let maxDocuments')),
  'Encrypted envelope/document/watch v1 schema retained, with optional legacy-decodable learned-source and health fields');
assert.equal(cacheStore.slice(cacheStore.indexOf('  private func canonicalURL(')),
  oldCacheStore.slice(oldCacheStore.indexOf('  private func canonicalURL(')), 'Cache URL policy unchanged');
for (const token of ['let sharedState = Self.state(for: fileURL)', 'lock = sharedState.lock', 'url.standardizedFileURL.path',
  'Self.keyLock.lock()', 'func putDocuments(', 'guard var snapshot = readUnlocked() else { return false }',
  'encryptionKey(createIfMissing: false)', 'error.code == .fileReadNoSuchFile',
  'envelope.version == 1', 'snapshot.version == 1', 'AES.GCM.open', 'AES.GCM.seal',
  'try writeFile(encoded, fileURL)', '.completeFileProtectionUntilFirstUserAuthentication',
  '"committed": .bool(committed)', 'return committed ? removed : nil']) assert(cacheStore.includes(token), token);
assert(!cacheStore.includes('try? encoded.write'));
}
for (const token of ['cacheMetadata["available"] != .bool(false)', 'cleared["committed"] == .bool(true)',
  'guard cacheStore.putWatch(watch)', 'guard cacheStore.putWatch(updated)', 'cacheStore.watchSnapshot()',
  'guard let removed = cacheStore.removeWatch(', 'return cacheStore.putDocuments(documents)',
  'cache["write_committed"] = .bool(committed)']) assert(intelligence.includes(token), token);
const cacheTests = read('apps/ios/GalaxySSITests/AgentIOSWebIntelligenceNativeToolTests.swift');
for (const name of ['testCorruptWebCacheCannotBeOverwrittenOrReportedAsCleared',
  'testMissingWebCacheKeyDoesNotRotateOrReplaceExistingCiphertext',
  'testWebCacheBatchCommitsOnceAndFailedReplacementPreservesSnapshot',
  'testWebCacheInstancesSerializeOneSnapshotReadModifyWrite',
  'testWebWatchAndClearToolsDoNotClaimFailedPersistenceSucceeded']) assert(cacheTests.includes('func ' + name + '('));
const learning = require('./check-mixed-media-search-scope.cjs').retainedMixedSource(read(swift('AgentIOSWebSourceLearning')));
for (const token of ['results.prefix(20)', 'static let maximumSources = 512', 'queries.count >= (broad ? 3 : 2)',
  'count >= (broad ? 4 : 3)', 'previous?.status == "disabled"', 'sorted(by: >).prefix(16)',
  'queue.maxConcurrentOperationCount = 1', 'queue.operationCount < 17', 'queue.addOperation(task)',
  'repeated_discovery_not_content_or_permission_verification', 'builtInHosts.contains { host == $0 || host.hasSuffix("." + $0) }',
  'compactMap(AgentIOSWebResearchPlanCodec.normalizedCategory)',
  'AgentIOSWebResearchPlanCodec.normalizedCategory(tag) == tag']) assert(learning.includes(token), token);
if (!usesIndexedCache) for (const token of ['let generation = state.generation', 'state.generation = UUID()',
  'guard state.generation == generation, !isCancelled()', 'self.applyLearning(observations, generation: generation',
  'state.lastLearningStatus = committed ? "saved" : "failed_write"',
  '(snapshot.learnedSources ?? []).allSatisfy(\\.isValid)', '"learned_sources_removed"',
  'snapshot.learnedSources = []']) assert(cacheStore.includes(token), token);
for (const token of ['invocation.context.grantedPermissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission)',
  'invocation.context.grantedConsents.contains(AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent)',
  '"skipped_cache_scope_required"', 'isCancelled: { invocation.isCancellationRequested }',
  'response.output["learning"] = .object(learning)', 'case "learned_sources":',
  'cacheMetadata = cacheStore.stats().merging(cleared)']) assert(intelligence.includes(token), token);
const learningCatalog = read(swift('AgentIOSWebIntelligenceSourceCatalog'));
assert(learningCatalog.includes('cacheStore.learnedSources()'));
assert(!learningCatalog.includes('defaults.integer(forKey: Self.learnedSourceCountKey)'));
const learningView = read(swift('GalaxySSIWebIntelligenceSourcesView'));
assert(learningView.includes('summary(learningStats: learningStats)'));
assert(learningView.includes('publisher(for: .galaxySSIWebLearningDidChange).receive(on: DispatchQueue.main)'));
assert(learningView.includes('summary.learningStats.available ? String('));
const nativeCatalog = require('./check-web-page-diff-scope.cjs').retainedDiffCatalog(read(swift('AgentIOSWebIntelligenceNativeTools')));
const oldNativeCatalog = git('show', base + ':' + swift('AgentIOSWebIntelligenceNativeTools'));
assert.equal(nativeCatalog.replace(', "learned_sources"]),', ']),')
  .replace('        "status": stringSchema(enumValues: ["candidate", "verified", "disabled"]),\n', ''), oldNativeCatalog,
  'Only cache listing schema extended; existing permissions/consents, operation schemas and capabilities retained');
for (const name of ['testSourceLearningRequiresRepeatedDiverseQueriesAndSafeDistinctHosts',
  'testSourceMaintenanceQueueIsBoundedWithoutCallerThreadFallback',
  'testFullCacheClearInvalidatesQueuedLearningAcrossInstancesButExpiredClearDoesNot',
  'testLearningUsesEncryptedSnapshotAndLegacyDocumentsRemainReadable',
  'testFailedOrCancelledLearningDoesNotPublishOrReplaceEvidence',
  'testActualSearchQueuesLearningOnlyWithCacheScopeAndCacheToolListsIt']) assert(cacheTests.includes('func ' + name + '('));
const sourceHealth = read(swift('AgentIOSWebSourceHealth'));
for (const token of ['consecutiveFailures >= 3', 'if receipt.status == "cancelled" { return next }',
  '["completed", "empty"].contains(receipt.status)', 'ewmaLatencyMillis * 0.75 + latency * 0.25',
  'Int64(1_800_000)', 'Int64(60_000) * (Int64(1) << exponent)',
  'end.overflow ? Int64.max', 'Double(attempts) + 1', 'if explicit { return Selection(',
  'filter { !blocked.contains($0.element) }']) assert(sourceHealth.includes(token), token);
if (!usesIndexedCache) for (const token of ['func sourceHealth(ids: Set<String> = [])', 'func recordSourceReceipts(',
  'receipts.allSatisfy(\\.isValid)', 'health[receipt.sourceID]', '.evolved(receipt, now: nowMillis())',
  'func resetSourceHealth()', 'snapshot.sourceHealth = []', '"source_health_removed"',
  '(snapshot.sourceHealth ?? []).allSatisfy(\\.isValid)']) assert(cacheStore.includes(token), token);
for (const token of ['native.sourceHealthStore = cacheStore', 'let webResult = searchProvider.invoke(',
  'case "source_health":', 'case "reset_source_health":', 'let reset = cacheStore.resetSourceHealth()',
  'cacheMetadata = cacheStore.stats().merging(reset)', 'result[key] = value']) assert(intelligence.includes(token), token);
for (const token of ['? sourceHealthStore : nil', 'healthStore?.sourceRoutingSnapshot()', 'let health = sourceSnapshot?.health',
  'AgentIOSWebSourceHealthRouting.select(', 'let endpoints = selection.selected.compactMap',
  '"search_sources_cooling_down"', 'let healthReceipts = attempts.compactMap(\\.healthReceipt)',
  'healthStore?.recordSourceReceipts(healthReceipts)', 'source_health_write_committed',
  'guard didStart else { return nil }', 'if case .cancelled = error { status = "cancelled" }',
  'results.isEmpty ? "empty" : "completed"', '(error as? URLError)?.code == .cancelled']) assert(provider.includes(token), token);
assert.equal((provider.match(/recordSourceReceipts\(healthReceipts\)/g) || []).length, 1,
  'One observed-attempt health batch, not one snapshot rewrite per provider');
for (const name of ['testSourceHealthBackoffEmptyCancellationAndOverflowRules',
  'testSourceHealthRoutingSkipsOpenCircuitsButRetainsExplicitAndSpecialistChoices',
  'testSourceHealthBatchAndResetCommitTruthfullyWithoutReplacingDocuments',
  'testActualNativeSearchUsesScopedHealthAndCacheHealthTools',
  'testSearchWithoutCacheScopeOrWithFailedHealthWriteRetainsNetworkEvidence',
  'testAllOpenSearchCircuitsSkipTransportWithoutInventingAttempts']) assert(cacheTests.includes('func ' + name + '('));
for (const token of ['var isSearchEligible: Bool', 'isValid && !AgentIOSWebSourceLearningPolicy.isBuiltInHost(host) && status == "verified" && vertical != "image"',
  'observations >= (broad ? 4 : 3) && queryFingerprints.count >= (broad ? 3 : 2)',
  'authority: min(max(confidence, 0.55), 0.85)', 'index % 2 == 0 ? "duckduckgo" : "bing"',
  '"search_available": .bool(isSearchEligible)']) assert(learning.includes(token), token);
for (const token of ['learnedSources.filter(\\.isSearchEligible)', 'requestedCategories.compactMap(',
  '!categories.isDisjoint(with: $0.categoryTags)', 'let catalog = orderedSources + learned']) assert(learningCatalog.includes(token), token);
for (const token of ['sourceHealthStore: AgentIOSWebIntelligenceCacheStore? = .shared',
  'AgentIOSWebSearchEnginePolicy.canResolve(requestedEngines)',
  'AgentIOSWebSearchEnginePolicy.accepts(requestedEngines, learnedSources: learned)',
  'learnedSources: imageSearch ? [] : learned', 'source.indexEngine == "duckduckgo" ? "html.duckduckgo.com" : "www.bing.com"',
  'URLQueryItem(name: "q", value: "site:\\(source.scope ?? host) \\(query)")',
  'return requestedEngineIds.compactMap { seen.insert($0).inserted ? byID[$0] : nil }',
  'output["learning"] = .object(healthStore.learnSourceCandidates(', '"selected_learned_sources"']) assert(provider.includes(token), token);
assert(!provider.includes('return Array(endpoints.prefix('), 'Candidate pool is not truncated before health filtering/fanout');
for (const token of ['private func acceptsEngines(', 'AgentIOSWebSearchEnginePolicy.canResolve(engines)',
  'AgentIOSWebSearchEnginePolicy.accepts(engines, learnedSources: learned)',
  'requestedCategories.isEmpty && requestedVerticals.isEmpty',
  '} else if webMediaProvider is AgentIOSURLSessionWebMediaToolProvider,',
  'let nativeLearning = webResult.output["learning"]?.objectValue', 'learning = nativeLearning']) assert(intelligence.includes(token), token);
assert(cacheStore.includes('func sourceRoutingSnapshot()'));
for (const name of ['testLearnedRoutingRequiresQualifiedRecordsAndModelSelectedTopics',
  'testActualLearnedSearchFiltersDestinationsAndLearnsOnlyOnceThenClearRevokesRouting',
  'testDirectRawSearchQueuesScopedLearningWithoutIntelligenceWrapper',
  'testLaterUnavailableLearnedEngineRejectsWholeResearchPlanBeforeSearching',
  'testTopicScopedLearnedSearchDoesNotReuseUnscopedTextCache',
  'testExplicitNativeSearchOrderIsRetainedWithoutDuplicateDispatch']) assert(cacheTests.includes('func ' + name + '('));
for (const token of ['let useCache = (input["use_cache"]?.boolValue ?? false) && !imageSearch && requestedEngines.isEmpty',
  'item.result["lead_image_url"]?.stringValue ?? item.result["url"]?.stringValue',
  'result["images"] = .array(images)', 'evidence["images"] = .array(images)',
  'result["unavailable_sources"] = unavailable']) assert(intelligence.includes(token));
const budget = read(swift('AgentIOSWebExecutionBudget'));
for (const token of ['systemUptime * 1_000', 'subtractingReportingOverflow(started)',
  'min(remainingMillis, parent.remainingTimeMillis, timeoutMillis)', 'hardDeadlineEpochMillis: deadline',
  'parent.isCancellationRequested || isCancelled() || self.expired',
  'self == .fast ? 6_000 : (self == .deep ? 35_000 : 15_000)']) assert(budget.includes(token));
const research = intelligence.slice(intelligence.indexOf('  private func research('), intelligence.indexOf('  private func readableFetchResult('));
for (const token of ['acceptsEngines(globalEngines + rawPlanEngines + queryPlan.flatMap(\\.engines), invocation: invocation)',
  'let budget = AgentIOSWebExecutionBudget(', 'min(budget.remainingMillis, invocation.remainingTimeMillis)',
  '"status": .string("skipped_budget")', 'search(input: searchInput, invocation: child',
  'AgentIOSWebEvidenceReader(uptimeMillis: uptimeMillis)', 'results: remaining > 0 ? searchResults : []',
  'timeoutMillis: min(pageReadTimeout, remaining)', 'let childInvocation = try budget.invocation(',
  'else if executedQueries.count < queryPlan.count { status = "partial" }',
  'researchMetadata["shared_budget_exhausted"]']) assert(research.includes(token), token);
assert(research.indexOf('acceptsEngines(') < research.indexOf('for (index, item) in queryPlan.enumerated()'));
assert(provider.includes('let byID = Dictionary(uniqueKeysWithValues: endpoints.map { ($0.provider, $0) })'));
assert(provider.includes('throw AgentIOSURLSessionWebError.unsupportedSearchEngine'));
const completion = read(swift('AgentIOSWebSearchCompletionPolicy'));
for (const token of ['guard !explicitSources, normalizedProfile != "deep", limit > 0',
  'candidate.excerpt.utf16.count >= 30', 'queryTokens.intersection(words).count * 2 >= queryTokens.count',
  'AgentIOSWebEvidencePack.canonicalURL(candidate.url)', 'Set(evidence.map(\\.provider)).count >= 2',
  'return images.count >= limit', 'precomposedStringWithCompatibilityMapping.lowercased()',
  'zip(group, group.dropFirst())']) assert(completion.includes(token), token);
const oldCompletion = git('show', base + ':' + swift('AgentIOSWebSearchCompletionPolicy'));
assert.equal(completion.slice(completion.indexOf('    let successfulGroups ='), completion.indexOf('  static func tokens(')),
  oldCompletion.slice(oldCompletion.indexOf('    let successfulGroups ='), oldCompletion.indexOf('  private static func canonicalURL(')),
  'Legacy URL-only caller thresholds unchanged');
assert.equal(completion.slice(completion.indexOf('  private static func canonicalURL(')),
  oldCompletion.slice(oldCompletion.indexOf('  private static func canonicalURL(')), 'Legacy URL-only completion path normalization unchanged');
for (const token of ['defer { accumulator.cancel() }', 'invocation: searchInvocation',
  'cancellationRequested: { invocation.isCancellationRequested || accumulator.isCancelled }',
  'hardDeadlineEpochMillis: requestDeadline', 'query: query, candidates: candidates, imageOnly: imageSearch',
  'excerpt: result.excerpt, imageURL: result.image?["url"]?.stringValue']) assert(provider.includes(token), token);
const budgetTests = read('apps/ios/GalaxySSITests/AgentIOSWebIntelligenceNativeToolTests.swift');
for (const name of ['testResearchBudgetKeepsEvidenceAndSkipsUnstartedQueriesAndPages',
  'testResearchValidatesLaterEngineBeforeAnyEarlierSearch', 'testSearchProfilesSupplyDefaultsButPreserveExplicitLimits',
  'testMonotonicResearchBudgetCapsProgressAwareChildDeadline']) assert(budgetTests.includes('func ' + name + '('));
const planning = read(swift('CloudModelAgentPlanningProvider'));
assert(planning.includes('try executor.executeTool(call: call, context: context)'));
assert(!planning.includes('functions.append(image)'));
const oldProvider = git('show', base + ':' + swift('AgentIOSURLSessionWebMediaProvider'));
const section = (source, start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
const oldPlanning = git('show', base + ':' + swift('CloudModelAgentPlanningProvider'));
assert.equal(planning, oldPlanning
  .replace(section(oldPlanning, '    if var image = functions.first(', '    return functions'), '')
  .replace(section(oldPlanning, '        var dispatch = call', '        let context = CloudConversationToolExecutionContext'), '')
  .replace('    var functions = CloudWebGrounding.openAITools()', '    let functions = CloudWebGrounding.openAITools()')
  .replace('try executor.executeTool(call: dispatch, context: context)', 'try executor.executeTool(call: call, context: context)'),
  'Supervision unchanged except reuse of the real image alias instead of cloning/translating it');
const workspace = require('./check-workspace-index-scope.cjs').retainedWorkspaceCore(read(swift('AgentWorkspaceStore')));
const oldWorkspace = git('show', base + ':' + swift('AgentWorkspaceStore'));
const persistedReader = section(workspace, '  // Persistence cannot interpret', '  fileprivate static func encodedListLength(');
assert(persistedReader.includes('static func decodePersistedList('));
assert.equal(workspace.replace(persistedReader, ''), oldWorkspace,
  'Existing workspace identity/revision, event/checkpoint/cancel, bounds, tolerant codecs and JSON encoding unchanged');
for (const token of ['(1...version).contains(storedVersion)', 'JSONDecoder().decode(Header.self',
  'JSONDecoder().decode(LegacyHeader.self', 'values.count <= AgentWorkspaceBoundsPolicy.maxWorkspaces',
  'workspaces.count == values.count', 'Set(workspaces.map(\\.workspaceId)).count == values.count']) assert(persistedReader.includes(token), token);
const workspaceFile = require('./check-workspace-creation-timing-scope.cjs')
  .retainedWorkspaceCreationTiming(read(swift('FileAgentWorkspaceStore')));
const oldWorkspaceFile = git('show', base + ':' + swift('FileAgentWorkspaceStore'));
assert.equal(section(workspaceFile, '  static func defaultFileURL(', '  func list()'),
  section(oldWorkspaceFile, '  static func defaultFileURL(', '  func list()'), 'Workspace storage paths unchanged');
assert.equal(section(workspaceFile, '  func clear()', '  func recoverable()'),
  section(oldWorkspaceFile, '  func clear()', '  func recoverable()'), 'Explicit clear behavior unchanged');
assert.equal((workspaceFile.match(/let store = try loadStore\(\)/g) || []).length, 5);
assert.equal((workspaceFile.match(/try persist\(store\)/g) || []).length, 5);
for (const token of ['lock = Self.gate(for: fileURL)', 'url.standardizedFileURL.path',
  'error.code == .fileReadNoSuchFile', 'try AgentWorkspaceJsonCodec.decodePersistedList(raw)',
  'try writeFile(Data(store.serializedSnapshot().utf8), fileURL)',
  '.completeFileProtectionUntilFirstUserAuthentication']) assert(workspaceFile.includes(token), token);
const workspacePersist = section(workspaceFile, '  private func persist(', '  private func locked<T>');
assert(workspacePersist.indexOf('try writeFile(') < workspacePersist.indexOf('NotificationCenter.default.post('));
assert(read(swift('AgentTaskRuntime')).includes('workspaceStore: AgentWorkspaceStore = IndexedAgentWorkspaceStore()'));
assert(read(swift('GalaxySSIStore')).includes('workspaceStore: AgentWorkspaceStore = IndexedAgentWorkspaceStore()'));
require('./check-workspace-index-scope.cjs').validateIndexedWorkspace();
const workspaceTests = read('apps/ios/GalaxySSITests/AgentWorkspacePersistentStoreTests.swift');
for (const name of ['testFailedWorkspaceCommitPreservesRecordsRecoveryAndNotifications',
  'testInvalidWorkspaceSnapshotsCannotBeOverwrittenByMutation',
  'testPersistedWorkspaceReaderKeepsLegacyAndEmptySnapshots',
  'testWorkspaceInstancesShareRevisionCompareAndCommit',
  'testWorkspaceEvictionAndRecoveryAreOneCommittedSnapshot']) assert(workspaceTests.includes('func ' + name + '('));
const pack = read(swift('AgentIOSWebEvidencePack'));
const oldPack = git('show', base + ':' + swift('AgentIOSWebEvidencePack'));
assert.equal(section(pack, '  static func canonicalURL(', '  private static func normalizedDocuments('),
  section(oldPack, '  static func canonicalURL(', '  private static func normalizedDocuments('), 'Citation URL canonicalization unchanged');
for (const token of ['Dictionary(grouping: documents + results)', '.flatMap(mediaImages)',
  '.filter { seenImages.insert($0.string("url")).inserted }.prefix(4)',
  'evidence["media_evidence_level"] = .string("discovered_url_not_visually_verified")',
  'url.user == nil, url.password == nil', 'for key in ["thumbnail_url", "original_url"]']) assert(pack.includes(token), token);
const verification = read(swift('AgentIOSWebEvidenceVerification'));
const oldVerification = git('show', base + ':' + swift('AgentIOSWebEvidenceVerification'));
assert.equal(section(verification, '  private static func citationSources(', '  static func attach('),
  section(oldVerification, '  private static func citationSources(', '  static func attach('), 'Source identity/hash/citation-ID gates unchanged');
assert.equal(section(verification, '  static func verify(', '  static func validateAnswer('),
  section(oldVerification, '  static func verify(', '  static func validateAnswer('), 'Manifest and conflict verification kernel unchanged');
for (const token of ['sourceIDs.contains(item.string("citation_id") + "\\n" + item.string("url"))',
  '$0.isImage && allowedImages.contains($0.url)', 'AgentMarkdownArtifactReferences.citationMarkup(resolved.text).links']) assert(verification.includes(token));
const markdown = read(swift('AgentRichMarkdownParser'));
const typedStart = markdown.indexOf('        let isImage = value[index] == "!"');
const typedEnd = markdown.indexOf('        if !omitLinks', typedStart);
assert(typedStart > 0 && typedEnd > typedStart);
const typedLinks = markdown.slice(typedStart, typedEnd);
for (const token of ['result.links.append((link.destination, isImage))', 'image.end <= labelEnd',
  'inlineCodeEnd(value, at: nested)', 'result.links.append((image.destination, true))']) assert(typedLinks.includes(token));
assert.equal((markdown.slice(0, typedStart) + markdown.slice(typedEnd))
  .replace('    var links: [(destination: String, isImage: Bool)] = []\n', ''),
  git('show', base + ':' + swift('AgentRichMarkdownParser')), 'Only typed destination observation added; text/legacy destinations/artifact stripping/rendering remain byte-identical');
const mediaTests = read('apps/ios/GalaxySSITests/AgentIOSWebEvidencePackTests.swift') + read('apps/ios/GalaxySSITests/AgentIOSWebEvidenceVerificationTests.swift');
for (const name of ['testImagesSurviveRetrievedBodyPreferenceAndAggregateOnlyTheirSourcePage',
  'testMediaURLsAreBoundedWebCandidatesNotLocalOrCredentialedLocations',
  'testDiscoveredImageURLsAreAllowedOnlyAsImagesNotOrdinaryCitationLinks',
  'testInvalidSourceIdentityCannotAuthorizeImageDestinations']) assert(mediaTests.includes('func ' + name + '('));
assert.equal(section(require('./check-image-source-adapters-scope.cjs').retainedProvider(provider), '  private func requestResource(', '  private func failure(_ error:'),
  section(oldProvider, '  private func requestResource(', '  private func failure(_ error:'),
  'HTTP bounds, redirect/public-host policy, resource extraction and browser transport stay unchanged');
for (const name of ['GalaxySSIServices']) {
  assert.equal(require('./check-plan-node-dispatch-scope.cjs').retainedServices(read(swift(name))),
    git('show', base + ':' + swift(name)), name + ' retained outside checked parallel dispatch-intent hook');
}
const grounding = read(swift('CloudWebGrounding'));
const aliasDefinition = section(grounding, '      functionTool(\n        name: "web_image_search",', '      functionTool(\n        name: "web_weather",');
const aliasNormalization = section(grounding, '    if name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "web_image_search" {', '    if operation(forToolName: name) == .search {');
const imageBoundedHook = section(grounding, '      if pack["presentation"] == .string("compact_image_candidates") {', '      let links = discoveredNavigationLinks');
assert(aliasDefinition.includes('maximum: 12'));
assert(aliasNormalization.includes('min(max(result["max_results"]?.intValue ?? 12, 6), 12)'));
assert(imageBoundedHook.includes('maximumCharacters: maximumToolResultCharacters'));
assert.equal(grounding.replace(aliasDefinition, '').replace(aliasNormalization, '').replace(imageBoundedHook, '')
  .replace('case "web_search", "web_image_search", AgentIOSWebIntelligenceNativeToolCatalog.search.lowercased():',
    'case "web_search", AgentIOSWebIntelligenceNativeToolCatalog.search.lowercased():'),
  git('show', base + ':' + swift('CloudWebGrounding')), 'Only image tool declaration/mapping/normalization and bounded presentation dispatch added; legacy weather, prompts, read-only, formats and native dispatch retained');
const imagePresentation = read(swift('CloudImageSearchEvidence'));
for (const token of ['AgentIOSWebEvidencePack.mediaURL', 'image.removeValue(forKey: "width")',
  'image.removeValue(forKey: "height")', '"search_preview"', '"original_url"',
  'String(item.string("excerpt").prefix(240))', 'AgentIOSWebEvidenceVerification.attach(pack)',
  'AgentIOSWebEvidenceVerification.attach(compact)', 'for candidate in [full, minimal]',
  'encode(selected + [trial]).count <= maximumCharacters', '"presentation_omitted_images"',
  '"media_fields_omitted"', 'not visual identification', 'image_candidate_output_limit']) assert(imagePresentation.includes(token), token);
assert(!imagePresentation.includes('URLSession'));
assert(pack.includes('return operation == "search" && CloudImageSearchEvidence.isImageOnly(output)'));
const rawNativeTools = read(swift('AgentIOSWebMediaNativeTools'));
const imageNativeHook = section(rawNativeTools, '    if operation == .webSearch, CloudImageSearchEvidence.isImageOnly(output) {', '    var metadata = execution.metadata');
assert(imageNativeHook.includes('output["evidence_pack"] = prepared["evidence_pack"]'));
assert.equal(rawNativeTools.replace(imageNativeHook, ''), git('show', base + ':' + swift('AgentIOSWebMediaNativeTools')),
  'Raw image pack addition only; operation namespace, permission/recovery/browser and native schemas retained');
const imagePresentationTests = read('apps/ios/GalaxySSITests/AgentIOSWebEvidencePackTests.swift');
for (const name of ['testImagePresentationUsesSecurePreviewAndRetainsSourceIdentity',
  'testImagePresentationRejectsInsecurePreviewsAndCannotRepairInvalidSourceIdentity',
  'testBoundedImagePresentationKeepsWholeURLsAndVerifiableRemainingCandidates',
  'testImageAliasIsRegisteredOnceNormalizedAndCoveredByResearchBudget',
  'testCloudImageAliasReachesNativeRegistryAndReturnsPreparedPreviewEvidence',
  'testRawNativeImageSearchAddsPreviewPackWithoutChangingOperation']) assert(imagePresentationTests.includes('func ' + name + '('));
const stream = read(swift('CloudConversationStreamEngine'));
const oldStream = git('show', base + ':' + swift('CloudConversationStreamEngine'));
const runtimeBudget = read(swift('CloudResearchRuntimeBudget'));
const oldRuntimeBudget = git('show', base + ':' + swift('CloudResearchRuntimeBudget'));
assert.equal(section(runtimeBudget, 'struct CloudResearchConfiguration:', '  let limits: Limits'),
  section(oldRuntimeBudget, 'struct CloudResearchConfiguration:', '  let limits: Limits'),
  'Retain current configurable research limits; do not restore historical fixed 60/180-second budgets');
assert.equal(runtimeBudget.slice(runtimeBudget.indexOf('enum CloudResearchRoundDeadline {')),
  oldRuntimeBudget.slice(oldRuntimeBudget.indexOf('enum CloudResearchRoundDeadline {')),
  'Existing round transport cancellation helper unchanged; no new hard transport-interruption claim');
for (const token of ['remainingActiveMillis == 0', 'finalizing ? limits.modelMillis : min(limits.modelMillis, remainingActiveMillis)',
  '"error_code": .string("web_execution_stopped")', '"retryable": .bool(false)', 'admitted tool calls.']) assert(runtimeBudget.includes(token));
for (const token of ['let transportMillis = min(roundMillis, research.modelRoundMillis(finalizing: finalRound))',
  'guard transportMillis > 0 else { throw URLError(.timedOut) }', 'millis: transportMillis)',
  'if !finalRound, !emittedText, roundFailure?.error.code == "WEB_DEADLINE"',
  'researchDeadlineEpochMillis: AgentControlPlaneClock.nowMillis() + research.remainingActiveMillis',
  'remainingResearchMillis: { research.remainingActiveMillis }', 'let remaining = remainingResearchMillis?()',
  'output: CloudResearchRuntimeBudget.stoppedToolResult(call.name)',
  'executionContext.researchToolTimeoutMillis = min(context.researchToolTimeoutMillis, remaining)',
  'toolExecutor.executeTool(call: call, context: executionContext)']) assert(stream.includes(token), token);
assert.equal(section(stream, '  private func withCloudCoordination(', '  private func executeToolCalls('),
  section(oldStream, '  private func withCloudCoordination(', '  private func executeToolCalls('),
  'Collaboration coordination, admission and scoped recall kernels retained');
const rounds = read(swift('CloudConversationStreamToolRounds'));
const oldRounds = git('show', base + ':' + swift('CloudConversationStreamToolRounds'));
assert.equal(section(rounds, 'enum CloudImageAnnotationSession {', 'struct CloudWebGroundingToolExecutor:'),
  section(oldRounds, 'enum CloudImageAnnotationSession {', 'struct CloudWebGroundingToolExecutor:'),
  'Image annotation and tool progress logic unchanged');
assert.equal(rounds.slice(rounds.indexOf('struct CloudModelStreamMutableConversation {')),
  oldRounds.slice(oldRounds.indexOf('struct CloudModelStreamMutableConversation {')),
  'Tool visibility, finalization and scoped collaboration schemas unchanged');
for (const token of ['var researchDeadlineEpochMillis: Int64? = nil', 'min(context.researchDeadlineEpochMillis ?? Int64.max,',
  'deadline <= started', 'return CloudResearchRuntimeBudget.stoppedToolResult(call.name)',
  '? deadline : nil']) assert(rounds.includes(token));
const roundTests = read('apps/ios/GalaxySSITests/CloudConversationStreamEngineTests.swift');
for (const name of ['testConfiguredResearchBudgetCapsActiveRoundsButRetainsFinalSynthesisLimit',
  'testCloudRetrievalUsesSharedHardDeadlineAndDoesNotInvokeExpiredProvider']) assert(roundTests.includes('func ' + name + '('));
const renderer = read(swift('AgentIOSDynamicWebRenderer'));
const oldRenderer = git('show', base + ':' + swift('AgentIOSDynamicWebRenderer'));
assert.equal(section(require('./check-public-address-policy-scope.cjs').retainedAddressRenderer(renderer), 'enum AgentIOSDynamicWebFallbackPolicy {', '#if canImport(WebKit) && canImport(UIKit)\nfinal class'),
  section(oldRenderer, 'enum AgentIOSDynamicWebFallbackPolicy {', '#if canImport(WebKit) && canImport(UIKit)\nfinal class'),
  'Static shell detection, HTTPS/DNS/same-origin/subresource policy unchanged outside checked shared address-classifier hooks');
assert.equal(section(renderer, '  func webView(\n    _ webView: WKWebView,\n    didReceive challenge:', '  private func finish('),
  section(oldRenderer, '  func webView(\n    _ webView: WKWebView,\n    didReceive challenge:', '  private func finish('),
  'Authentication, popup, media-capture and dialog policy unchanged');
for (const token of ['cooldownNanoseconds: UInt64 = 30_000_000_000', 'DispatchTime.now().uptimeNanoseconds',
  'case .contentProcessTerminated, .startupTimeout, .unavailable: return true',
  'queue.maxConcurrentOperationCount = 1', 'defer { state.close(); operation.cancel() }',
  'AgentIOSWebRenderPreflight.resolve(deadline: deadline', 'defer { coordinator.cancel() }',
  'if AgentIOSWebRendererHealth.isProcessFailure(error) { health.failed() }', 'health.succeeded()',
  'configuration.websiteDataStore = .nonPersistent()', 'configuration.processPool = WKProcessPool()',
  'let startupDeadline = min(deadline, DispatchTime.now() + .seconds(5))',
  'guard !isFinished else { return }', 'self.webView?.stopLoading()']) assert(renderer.includes(token), token);
const render = section(renderer, 'final class AgentIOSWKWebViewRenderer:', 'private final class AgentIOSWKWebViewRenderCoordinator:');
assert(render.indexOf('let deadline =') < render.indexOf('AgentIOSWebRenderPreflight.resolve('));
assert.equal((render.match(/try health.checkAvailable\(\)/g) || []).length, 2);
assert(render.indexOf('defer { coordinator.cancel() }') < render.indexOf('DispatchQueue.main.async { coordinator.start() }'));
const lifecycleTests = read('apps/ios/GalaxySSITests/AgentIOSDynamicWebRendererTests.swift');
for (const name of ['testRendererHealthUsesSharedCooldownWithoutExtendingRejectedChecks',
  'testRendererHealthDoesNotPoisonAvailabilityForPageOrCallerFailures',
  'testRendererPreflightRejectsCancellationCheckpointAndDeadlineBeforeResolver',
  'testRendererPreflightUsesCompletedResolutionWithoutNetwork']) assert(lifecycleTests.includes('func ' + name + '('));
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const token of ['AgentIOSPublicSearchParser.swift in Sources', 'SwiftSoup in Frameworks',
  'AgentIOSWebExecutionBudget.swift in Sources',
  'AgentIOSWebSourceLearning.swift in Sources',
  'AgentIOSWebSourceHealth.swift in Sources',
  'CloudImageSearchEvidence.swift in Sources',
  'productName = SwiftSoup;', 'repositoryURL = "https://github.com/scinfu/SwiftSoup";', 'version = 2.6.0;']) assert(project.includes(token));
const pins = JSON.parse(read('apps/ios/GalaxySSI.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'));
const pin = pins.pins.find(p => p.identity === 'swiftsoup');
assert.equal(pin.state.revision, '0e96a20ffd37a515c5c963952d4335c89bed50a6');
assert.equal(pin.state.version, '2.6.0');
const tests = read('apps/ios/GalaxySSITests/AgentIOSWebMediaNativeToolTests.swift');
for (const name of ['testPublicSearchParserKeepsCardsAndSnippetsButNotNavigationOrAds',
  'testPublicSearchParserUnwrapsOwnedRedirectsAndRejectsUnsafeDestinations',
  'testPublicSearchParserUsesBaiduCardDestinationAndReportsVerification',
  'testSogouImageParserKeepsOriginalSourceDimensionsAndThumbnailFallback',
  'testImageSearchReachesPublicEndpointAndKeepsImagesThroughEvidenceProjection',
  'testSearchEarlyCompletionRequiresSubstantialQueryRelatedExcerpts',
  'testBalancedSearchCompletionNeedsDistinctCanonicalSourcesAndEngines',
  'testImageEarlyCompletionCountsDistinctImagesAndKeepsExplicitAndDeepSources',
  'testSearchCompletionUsesCompatibilityNormalizedAndCJKQueryTokens']) assert(tests.includes('func ' + name + '('));
const files = git('diff', '--name-only', android + '^1', android).trim().split('\n');
const disposition = file => {
  if (file.endsWith('/MainActivity.kt')) return 'Partial platform adaptation: actual iOS planning/voice bridge now reuses a coordinator-retained realtime provider instead of discarding a temporary nonblocking provider on every call. Enabled startup prewarm queues source I/O on the existing separate utility queue, coalesces loads, skips obsolete queued work and fences late publication with refresh tokens. Fingerprint changes invalidate cached snapshots; compiled output rechecks current eligible/non-private/non-paused conversation IDs. Existing mandatory MainActor native catalog/recovery initialization remains; moving native catalog construction off that path and full startup/runtime acceptance are not completed';
  if (file.endsWith('/MainActivityGlobalAgent.kt')) return 'Platform adaptation: settings and global Agent dashboards now read cognition/runs/goals/research snapshots on a separate serial utility content queue, not in SwiftUI body or routing workers. MainActor generation ownership coalesces bursts into one trailing refresh, rejects departed/old-identity completions and preserves the last complete snapshot on source failure. Active pages refresh on entry/manual action and poll every 15 seconds; offscreen polls do not reactivate. Inbox/count projection remains in-memory on MainActor. Files are read separately, not atomically; backing store per-profile provenance, all other synchronous view reads and native concurrency/UI/performance acceptance remain unverified';
  if (file.endsWith('/MainActivityAgentExecution.kt')) return 'Platform adaptation: actual iOS local tool task projection now stamps the existing phone device identity via a cached-profile-only getter extracted without changing the existing pairing identifier algorithm. Eligible blank-device legacy rows upgrade on update; foreign-device workspaces are not relabeled. Cancellation/recovery accept current or legacy blank devices with unchanged task/conversation/remote/delivery gates. Workspace-only task projection recognizes the current phone device; explicit remote routes remain Desktop. Lower-level creation timing retained, not Android full submission elapsed timing. No identity/MQTT derivation or schema change; legacy ownership and native migration/cancellation/UI/performance acceptance remain unverified';
  if (file.endsWith('/MobileNativeAgentRuntime.kt')) return 'Reviewed actual startExecutionLoop diff: Android appends reasoning audit before persisting the loop event to avoid a second session save and adds monotonic prepare/persist diagnostics. iOS has execution-loop model/timeline types but no equivalent production startExecutionLoop/persistExecutionLoopEvent path. Existing task records, native audits and encrypted plan-node journal are distinct stores, so broad loop-start/audit batching and timing equivalence are NOT implemented or claimed complete';
  if (file.endsWith('/AppStore.kt')) return 'Existing iOS profile is a MainActor Published stored value, not a reconstructing JSON/disk getter. Local workspace attribution now uses a cached-profile-only localDeviceId helper extracted from the existing pairing identity algorithm, without constructing UIKit device metadata. Pairing IDs, Signal and MQTT identities remain unchanged. Android route initialization/repair is not newly reproduced; native performance/identity/legacy ownership acceptance remains unverified';
  if (file.endsWith('/MainActivityAgentPage.kt')) return 'Partial: actual iOS initialPlanningConversation now records separate monotonic metadata/history/global/assembly and total read spans via typed private-hash OSLog. Keep one scoped metadata lookup, exact existing history/global expressions/order, privacy defaults and selected-provider global-context suppression. Four fixture methods authored only. Android worker queue/hydration timing, native routing latency/UI acceptance and broader context indexing remain incomplete';
  if (file.endsWith('/CloudWebGrounding.kt')) return 'Partial production port: ordinary model web_search defaults to fast when profile is omitted; fast fanout defaults to three only when neither engine_fanout nor engines is present. Native search ID, image alias and research defaults remain distinct. Image alias/normalization and bounded image-aware delivery; request-focused untrusted guidance; whole HTTPS fallback sources through 4096 UTF-16 units, image exclusion, truthful localized synthesis with both actual engine language snapshots. Failed native results retain original diagnostics plus root timeout/stopped/renderer/invalid-engine non-retry hints, connecting native web_media_timeout to existing cross-read reuse. Typed URLSession timedOut stays typed; successful static fallback stays successful. Six fast-default, seven failure and six fallback fixture methods authored only. Complete native cancellation/model/transport/failure/timing/latency acceptance remains unverified';
  if (file.endsWith('/res/values/strings.xml') || file.endsWith('/res/values-zh-rCN/strings.xml')) return 'Changed fallback source/empty copy now matches the pinned Android English and Chinese strings, with both production cloud engines passing interface-language snapshots. Existing iOS image-search progress localization remains. Resource/source checks only, not native multilingual display or model compliance acceptance';
  if (file.endsWith('/AgentWebMediaNativeTools.kt')) return 'Ported the actual changed encoded-address behavior: validate HTTPS/public host/credentials/port without decoding or rebuilding encoded paths and queries, normalize authority/empty path and strip fragments before dispatch, and preserve case-sensitive path/query redirect identities. Existing manual per-hop revalidation, HTTP/header/credential/body/deadline policies retained. Seven native fixture methods authored only, including the exact Android encoded/signed redirect sample. Not native Foundation/URLSession/DNS or full WebMedia parity';
  if (file.endsWith('/AgentWebMediaNativeToolsTest.kt')) return 'Exact Android encoded path/query/signed redirect sample copied into an actual iOS registry/injected transport fixture, plus relative redirects, case-sensitive identities, fragment loops, empty path and private/credentialed/insecure redirect rejection. Seven fixture methods SOURCE ONLY, NOT executed; not full Android test coverage';
  if (file.endsWith('/AgentDynamicWebArticleFetcher.kt')) return 'Adapted the changed failure-path duration behavior: native webOpen/browserRender output and metadata measure total monotonic static-plus-fallback resolution, including caught renderer failure. Preserve static retrieval timestamp, separate successful render duration and existing fallback/cancellation gates. Native fixture sources added, NOT executed; not full fetcher/runtime parity';
  if (file.endsWith('/CloudWebToolLoopProgress.kt')) return 'Existing native cross-read timeout/renderer-unavailable result reuse and three-stalled-retrieval-batch finalization retained. Evidence identity now includes canonical source URL, content hash, evidence level and canonically hashed image array, plus existing reading-window identity. Actual common model loop consumes it without changing collaboration progress/recall or configured limits. Native fixtures NOT executed; not full runtime acceptance';
  if (file.endsWith('/AgentMarkdownImageStore.kt')) return 'Partial iOS adaptation: encrypted 64-MiB/128-entry URL cache, 12-MiB streamed-body bound, eight shared producers with cancellation leases, manual bounded HTTPS redirects and isolated cookie/credential-free URLSession. DNS preflight is NOT connection pinning; complete address policy, native transport/decoder/cache fault and performance acceptance remain incomplete. Existing Files export retained, not Android MediaStore';
  if (file.endsWith('/AgentPublicWebSearchParser.kt')) return 'Adapted result-card DOM selection, excerpts, source verification detection, direct Baidu card URL and scoped redirect decoding using pinned SwiftSoup; native/network acceptance not run';
  if (file.endsWith('/AgentPublicWebSearchParserTest.kt')) return 'Three native fixture sources added, NOT executed; not complete Android test coverage';
  if (file.endsWith('/AgentPublicImageSearchParser.kt')) return 'Sogou inert script JSON parser connected to actual image-only endpoint and model evidence. Preserve source, original/thumbnail, dimensions and image identity; other image adapters/relevance/native acceptance incomplete';
  if (file.endsWith('/AgentPublicImageSearchTest.kt')) return 'Native parser and registry-to-evidence fixture sources added, NOT executed; not full image-search acceptance';
  if (file.endsWith('/AgentWebIntelligenceService.kt')) return 'Partial: protected indexed scoped health/learning/cache, batch/point operations, shared clear/generation, fenced import, 2,000 documents; similarity is not ANN. Search default 10/max 100 reaches mixed native text/image/evidence/exact cache. Independent search keys persist until explicit cleanup; inclusive expiry matches Android, while each response remains bounded to 2MB and historical JSON import to 32 records. Crawl has reference depth/page/time bounds, canonical BFS dedup, exact origins, DOM links, ignore-case filters, partial/error receipts and scoped cache. Extract has local/URL preference, offline full records, separately authorized fetch/force, bounded literal fields/headings/language hints and local provenance. Diff refetches with fixed deadlines, compares readable full snapshots, emits ordered line-set changes bounded 40/side and 300/line, rejects lossy overwrite, preserves prior data on write failure and gates network/cache scope. Diff/extract timeout schemas match 60s runtime; fetch remains 120s. Invoked watch checks select default20/max100 due records, forward timeout, record completion time, preserve partial failures/receipts, require cache plus network grants and conditionally commit unchanged watch versions after document persistence. Documents/watch are separate transactions; OS scheduling and native fault/concurrency acceptance remain unverified. No semantic/native SQL/crypto/transport/performance acceptance';
  if (file.endsWith('/AgentWebMaintenanceQueue.kt')) return 'Native one-worker utility queue, at most 17 outstanding optional learning tasks and no caller-thread fallback. Per-cache standardized-path generation/lock invalidates queued pre-clear work; no durable page/tool evidence is queued. Fault/concurrency/device acceptance not run';
  if (file.endsWith('/CloudImageSearchEvidence.kt')) return 'Native image-only packs prefer safe HTTPS previews, retain originals without claiming download/visual verification, remove original dimensions and use exact-subject Markdown guidance. Image-aware bounded model formatting admits whole URLs and re-verifies remaining source identities, with explicit omissions/failure. Native/network/UI acceptance not run';
  if (file.endsWith('/CloudModelClient.kt')) return 'Adapted the two added image-search reply instructions into the existing shared visual-output prompt consumed by default text and vision conversation preparation. Preserve language/vision/tool trust, HTML/video guards, actual evidence/citations and structured custom prompts. Native provider/compatibility fixture sources added, NOT executed; model compliance/UI acceptance not claimed';
  if (file.endsWith('/MainActivityTaskEvents.kt')) return 'Existing iOS AgentConnectorPublicProgress already maps web_image_search to its operation label and Chinese localization key. Retain later routine-search-noise suppression, failed-search visibility and private-detail filtering instead of regressing to the historical Android display policy. Native regression fixture source added, NOT executed';
  if (file.endsWith('/AgentWorkspaceStore.kt')) return 'Generic workspace production/runtime/startup recovery now use encrypted per-record SQLite with HMAC lookup, small authenticated retention metadata and recovery indexes. One BEGIN IMMEDIATE covers revision comparison, target reducer, record/eviction/recovery writes; notify and typed private creation timing only after commit. Strict bounded legacy migration has encrypted marker plus pending/committed Keychain fencing, no missing-key replacement or committed-index-loss reimport; retire plaintext after commit and retry cleanup. Existing 64-record/serialized-size/terminal-first/shrink policies retained. Eight fixture methods authored only. Health owner-bound sealed task store remains unchanged. Native SQL/crypto/concurrency/migration/backup/logging and measured performance parity not verified';
  if (file.endsWith('/AgentTranscriptStore.kt')) return 'Adapted changed metadata access: session metrics reuse one conversation lookup, and the indexed primary/draft lookup no longer falls back through full conversation enumeration for a legacy or unknown ID. Only the matching legacy contact history is synthesized using unchanged list rules. Existing initial planning already uses that scoped metadata/history path. No transcript storage migration; native/latency acceptance and broader context indexing remain incomplete';
  if (file.endsWith('/AgentWebEvidencePack.kt')) return 'Native pack retains up to four validated media URLs per canonical source across retrieved bodies/discovery results, dimensions and thumbnail/original references; discovered URL metadata is explicitly not visual verification';
  if (file.endsWith('/AgentWebEvidenceVerification.kt')) return 'Only structurally valid source items authorize image destinations, only for typed Markdown images including wrapped images. Ordinary citation URLs remain restricted; original manifest/ID/hash gates and Markdown text/rendering retained. No runtime acceptance';
  if (file.endsWith('/AgentWebIntelligence.kt')) return 'Partial: all 41 base IDs/247 sites, query-aware completion and unified weight/language/authority/health scoring with category/vertical coverage; explicit IDs preserve order. Direct image-only and mixed text/media requests share fusion, global consensus, reference image scoring and all-image page diversity. Qualified learned-image site indexes are ordinary page references, never fake image URLs. Pinned ranker and ordered UTF-16 SHA-256 Float32 feature-hash semantics are wired. Scoped Brave/GitHub headers and DDG shared deadline retained. Other media, storage limits and native numeric/relevance/UI/performance acceptance remain incomplete';
  if (file.endsWith('/AgentWebExecutionBudget.kt')) return 'Monotonic research query/page budget plus existing configured cloud active budget now clamp actual provider rounds and queued retrieval invocations. Current limits preserved; no immediate synchronous-transport interruption or native acceptance claim';
  if (file.endsWith('/CloudModelStreaming.kt')) return 'Partial: actual streaming/compatibility model rounds and queued web tools consume remaining configured active time; terminal budget failures enter bounded finalization only before emitted answer text. Local OSLog diagnostics now record preparation/input length, once-only first activity, provider completion state and separate citation-repair validation with an independent monotonic clock and private hashed correlation, never prose/arguments/credentials. Existing evidence/recovery/permissions retained. Native timing, UI/end-to-end and broader acceptance remain unverified';
  if (file.endsWith('/CloudToolBatchExecutor.kt')) return 'Native ordered parallel dispatcher rechecks remaining active time at task start, emits non-retryable skipped output, caps per-tool hard deadline and propagates parent cancellation after batch. Live parallel transport cancellation/progress acceptance not verified';
  if (file.endsWith('/AgentWebRendererHealth.kt')) return 'Native shared monotonic 30-second process/startup-failure cooldown; caller/page failures excluded. Pure native fixture sources added, NOT executed';
  if (file.endsWith('/AgentIsolatedWebViewRenderer.kt')) return 'iOS adaptation: process cooldown, 5-second bounded main-queue startup and one deadline across DNS/capacity/render; unconditional cancellation/one-shot completion and no late cancelled start. Not Android Binder implementation or WK fault acceptance';
  if (file.endsWith('/AgentIsolatedWebRenderService.kt')) return 'Native serialized off-main DNS preflight bounds caller wait and cancels queued work. Existing nonpersistent WK store/process-pool/same-origin and auth policies retained. OS getaddrinfo already running is not forcibly interrupted; no device recovery guarantee';
  if (file.endsWith('/build.gradle.kts') || file.endsWith('/AndroidManifest.xml') || file.endsWith('/GalaxySSIApplication.kt')) return 'Android platform/build change, not copied into iOS; no iOS version change';
  if (file.includes('/androidTest/') || file.includes('/src/test/') || file.startsWith('docs/')) return 'Reference evidence inventoried, not reproduced or claimed as iOS acceptance';
  if (file.endsWith('/MobileNativeAgentExecution.kt')) return 'Partial: parallel plus ordinary sequential planned native/connector actions persist final routed/prepared input, active checkpoint and dispatch-intent audits in the encrypted node claim before effects. Sequential task ownership/checkpoint state is saved first; prior observed/pending claims are read before rerouting. Sequential replay/preparation rejects stale revisions, ambiguous actions/active checkpoints and mismatched stored dispatch checkpoints before receipt reuse or effects. Unknown outcomes stop non-retriably; fallback has its own specification and claim. Task/session state and node journal remain separate commits, not Android single-session persistence equivalence. Unplanned direct actions, visible capture/browser handoffs, cloud model loops, full audit batching and measured latency/native crash/fault acceptance remain incomplete';
  return 'Inventoried only; requires separate code comparison and implementation or explicit existing-equivalence evidence. Not complete';
};
const inventory = { androidPR: 3007, androidCommit: android, incrementalBase: base,
  scope: 'Public web/image evidence and bounded model delivery; partial encrypted Markdown image lifecycle; renderer/research/cloud caps, indexed workspace/cache, scoped health/learning, pinned adapters, mixed default-10/max-100 search, bounded BFS crawl, URL/local extraction, ordered-line page diff, invoked watch failure receipts/completion timing/conditional progress commits, typed media versus topic pages, explicit-cleanup search-key retention with bounded individual responses/inclusive expiry, encoded request/redirect identity preservation, feature-hash similarity and diagnostics. Health tasks remain sealed. DNS preflight is not connection pinning. Per-response byte bounds/OS watch scheduling/other media/context parity, UI/end-to-end timing and native acceptance remain incomplete.',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', android + ':' + file)).digest('hex'), disposition: disposition(file) })) };
const output = path.join(root, 'apps/ios/ANDROID_3007_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(output, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(output, 'utf8')), inventory);
console.log('Android #3007: web/image evidence and presentation, scoped learning/health and persistence contracts. Partial port; source checks only, no native or network acceptance.');
