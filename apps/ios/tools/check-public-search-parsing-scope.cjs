// Source contracts only; this does not execute SwiftSoup, XCTest, WebKit or live search.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const android = '65655f0c79c6ab04121150229a65b089180f82f2';
const base = '492bebe922013c2f707b38e4ddc849a655deba68';
const git = (...args) => cp.execFileSync('git', args, { cwd: root, encoding: 'utf8', maxBuffer: 16_000_000 });
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const swift = name => 'apps/ios/GalaxySSI/' + name + '.swift';
const parser = read(swift('AgentIOSPublicSearchParser'));
for (const token of ['import SwiftSoup', 'SwiftSoup.parse(source, baseURL)',
  'sourceVerificationRequired', '.b_ad, .ads, [data-text-ad]', 'h2 a[href]',
  'card.attr("mu")', 'seen.insert(url)', 'Data(base64Encoded: value)',
  'components.user == nil, components.password == nil', 'final.fragment = nil',
  'query.first(where: { $0.name == key })', 'seenSnippets.insert(text)']) assert(parser.includes(token), token);
assert(!parser.includes('WKWebView'));
const provider = read(swift('AgentIOSURLSessionWebMediaProvider'));
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
const intelligence = read(swift('AgentIOSURLSessionWebIntelligenceProvider'));
const cacheStore = read(swift('AgentIOSWebIntelligenceCache'));
const oldCacheStore = git('show', base + ':' + swift('AgentIOSWebIntelligenceCache'));
assert.equal(cacheStore.slice(0, cacheStore.indexOf('final class AgentIOSWebIntelligenceCacheStore')),
  oldCacheStore.slice(0, oldCacheStore.indexOf('final class AgentIOSWebIntelligenceCacheStore')),
  'Persisted document/watch schemas unchanged');
assert.equal(cacheStore.slice(cacheStore.indexOf('  private struct Snapshot:'), cacheStore.indexOf('  static let maxDocuments'))
  .replace('    var learnedSources: [AgentIOSLearnedWebSource]? = nil\n', ''),
  oldCacheStore.slice(oldCacheStore.indexOf('  private struct Snapshot:'), oldCacheStore.indexOf('  static let maxDocuments')),
  'Encrypted envelope/document/watch v1 schema retained, with one optional legacy-decodable learned-source field');
assert.equal(cacheStore.slice(cacheStore.indexOf('  private func canonicalURL(')),
  oldCacheStore.slice(oldCacheStore.indexOf('  private func canonicalURL(')), 'Cache URL policy unchanged');
for (const token of ['let sharedState = Self.state(for: fileURL)', 'lock = sharedState.lock', 'url.standardizedFileURL.path',
  'Self.keyLock.lock()', 'func putDocuments(', 'guard var snapshot = readUnlocked() else { return false }',
  'encryptionKey(createIfMissing: false)', 'error.code == .fileReadNoSuchFile',
  'envelope.version == 1', 'snapshot.version == 1', 'AES.GCM.open', 'AES.GCM.seal',
  'try writeFile(encoded, fileURL)', '.completeFileProtectionUntilFirstUserAuthentication',
  '"committed": .bool(committed)', 'return committed ? removed : nil']) assert(cacheStore.includes(token), token);
assert(!cacheStore.includes('try? encoded.write'));
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
const learning = read(swift('AgentIOSWebSourceLearning'));
for (const token of ['results.prefix(20)', 'static let maximumSources = 512', 'queries.count >= (broad ? 3 : 2)',
  'count >= (broad ? 4 : 3)', 'previous?.status == "disabled"', 'sorted(by: >).prefix(16)',
  'queue.maxConcurrentOperationCount = 1', 'queue.operationCount < 17', 'queue.addOperation(task)',
  'repeated_discovery_not_content_or_permission_verification', 'builtInHosts.contains(where:',
  'compactMap(AgentIOSWebResearchPlanCodec.normalizedCategory)',
  'AgentIOSWebResearchPlanCodec.normalizedCategory(tag) == tag']) assert(learning.includes(token), token);
for (const token of ['let generation = state.generation', 'state.generation = UUID()',
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
const nativeCatalog = read(swift('AgentIOSWebIntelligenceNativeTools'));
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
for (const token of ['AgentIOSWebSearchEnginePolicy.accepts(globalEngines + rawPlanEngines + queryPlan.flatMap(\\.engines))',
  'let budget = AgentIOSWebExecutionBudget(', 'min(budget.remainingMillis, invocation.remainingTimeMillis)',
  '"status": .string("skipped_budget")', 'search(input: searchInput, invocation: child',
  'AgentIOSWebEvidenceReader(uptimeMillis: uptimeMillis)', 'results: remaining > 0 ? searchResults : []',
  'timeoutMillis: min(pageReadTimeout, remaining)', 'let childInvocation = try budget.invocation(',
  'else if executedQueries.count < queryPlan.count { status = "partial" }',
  'researchMetadata["shared_budget_exhausted"]']) assert(research.includes(token), token);
assert(research.indexOf('AgentIOSWebSearchEnginePolicy.accepts(') < research.indexOf('for (index, item) in queryPlan.enumerated()'));
assert(provider.includes('endpoints = endpoints.filter { requestedEngineIds.contains($0.provider) }'));
assert(provider.includes('throw AgentIOSURLSessionWebError.unsupportedSearchEngine'));
const completion = read(swift('AgentIOSWebSearchCompletionPolicy'));
for (const token of ['guard !explicitSources, normalizedProfile != "deep", limit > 0',
  'candidate.excerpt.utf16.count >= 30', 'queryTokens.intersection(words).count * 2 >= queryTokens.count',
  'AgentIOSWebEvidencePack.canonicalURL(candidate.url)', 'Set(evidence.map(\\.provider)).count >= 2',
  'return images.count >= limit', 'precomposedStringWithCompatibilityMapping.lowercased()',
  'zip(group, group.dropFirst())']) assert(completion.includes(token), token);
const oldCompletion = git('show', base + ':' + swift('AgentIOSWebSearchCompletionPolicy'));
assert.equal(completion.slice(completion.indexOf('    let successfulGroups ='), completion.indexOf('  private static func tokens(')),
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
assert(planning.includes('if call.name == "web_image_search" {'));
assert(planning.includes('"verticals": .array([.string("image")])'));
assert(planning.includes('try executor.executeTool(call: dispatch, context: context)'));
const oldProvider = git('show', base + ':' + swift('AgentIOSURLSessionWebMediaProvider'));
const section = (source, start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
const workspace = read(swift('AgentWorkspaceStore'));
const oldWorkspace = git('show', base + ':' + swift('AgentWorkspaceStore'));
const persistedReader = section(workspace, '  // Persistence cannot interpret', '  fileprivate static func encodedListLength(');
assert(persistedReader.includes('static func decodePersistedList('));
assert.equal(workspace.replace(persistedReader, ''), oldWorkspace,
  'Existing workspace identity/revision, event/checkpoint/cancel, bounds, tolerant codecs and JSON encoding unchanged');
for (const token of ['(1...version).contains(storedVersion)', 'JSONDecoder().decode(Header.self',
  'JSONDecoder().decode(LegacyHeader.self', 'values.count <= AgentWorkspaceBoundsPolicy.maxWorkspaces',
  'workspaces.count == values.count', 'Set(workspaces.map(\\.workspaceId)).count == values.count']) assert(persistedReader.includes(token), token);
const workspaceFile = read(swift('FileAgentWorkspaceStore'));
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
assert(read(swift('AgentTaskRuntime')).includes('workspaceStore: AgentWorkspaceStore = FileAgentWorkspaceStore()'));
assert(read(swift('GalaxySSIStore')).includes('workspaceStore: AgentWorkspaceStore = FileAgentWorkspaceStore()'));
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
assert.equal(section(provider, '  private func requestResource(', '  private func failure(_ error:'),
  section(oldProvider, '  private func requestResource(', '  private func failure(_ error:'),
  'HTTP bounds, redirect/public-host policy, resource extraction and browser transport stay unchanged');
for (const name of ['CloudWebGrounding', 'GalaxySSIServices']) {
  assert.equal(read(swift(name)), git('show', base + ':' + swift(name)), name + ' unchanged in this increment');
}
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
assert.equal(section(renderer, 'enum AgentIOSDynamicWebFallbackPolicy {', '#if canImport(WebKit) && canImport(UIKit)\nfinal class'),
  section(oldRenderer, 'enum AgentIOSDynamicWebFallbackPolicy {', '#if canImport(WebKit) && canImport(UIKit)\nfinal class'),
  'Static shell detection, HTTPS/private-address resolution, same-origin and subresource policy unchanged');
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
  if (file.endsWith('/AgentPublicWebSearchParser.kt')) return 'Adapted result-card DOM selection, excerpts, source verification detection, direct Baidu card URL and scoped redirect decoding using pinned SwiftSoup; native/network acceptance not run';
  if (file.endsWith('/AgentPublicWebSearchParserTest.kt')) return 'Three native fixture sources added, NOT executed; not complete Android test coverage';
  if (file.endsWith('/AgentPublicImageSearchParser.kt')) return 'Sogou inert script JSON parser connected to actual image-only endpoint and model evidence. Preserve source, original/thumbnail, dimensions and image identity; other image adapters/relevance/native acceptance incomplete';
  if (file.endsWith('/AgentPublicImageSearchTest.kt')) return 'Native parser and registry-to-evidence fixture sources added, NOT executed; not full image-search acceptance';
  if (file.endsWith('/AgentWebIntelligenceService.kt')) return 'Partial: shared research deadline, truthful partial evidence, atomic cache batches and failure-safe persistence. Actual scoped search queues bounded source observations into the same encrypted snapshot; cache listing and UI stats read saved records. Full clear invalidates queued generations. Source-health indexing, learned routing, full built-in catalog exclusion and indexed-storage performance incomplete';
  if (file.endsWith('/AgentWebMaintenanceQueue.kt')) return 'Native one-worker utility queue, at most 17 outstanding optional learning tasks and no caller-thread fallback. Per-cache standardized-path generation/lock invalidates queued pre-clear work; no durable page/tool evidence is queued. Fault/concurrency/device acceptance not run';
  if (file.endsWith('/AgentWorkspaceStore.kt')) return 'iOS retains one whole-file snapshot for records and derived recovery membership, now serializing same-path instances across revision check/atomic commit and rejecting unreadable/partial/unsupported snapshots before writes. Post-commit notification only; failed commit leaves prior bytes and derived recovery unchanged. Native fault/concurrency acceptance and indexed-storage/performance parity not verified; no encryption migration';
  if (file.endsWith('/AgentWebEvidencePack.kt')) return 'Native pack retains up to four validated media URLs per canonical source across retrieved bodies/discovery results, dimensions and thumbnail/original references; discovered URL metadata is explicitly not visual verification';
  if (file.endsWith('/AgentWebEvidenceVerification.kt')) return 'Only structurally valid source items authorize image destinations, only for typed Markdown images including wrapped images. Ordinary citation URLs remain restricted; original manifest/ID/hash gates and Markdown text/rendering retained. No runtime acceptance';
  if (file.endsWith('/AgentWebIntelligence.kt')) return 'Partial: profile defaults, supported engine validation and actual early-completion policy use substantial query-overlap excerpts/canonical sources, balanced cross-engine evidence, distinct image URLs and NFKC/CJK tokens. Explicit/deep opt-out and existing disjoint guard retained. Full adapters/ranker/acceptance incomplete';
  if (file.endsWith('/AgentWebExecutionBudget.kt')) return 'Monotonic research query/page budget plus existing configured cloud active budget now clamp actual provider rounds and queued retrieval invocations. Current limits preserved; no immediate synchronous-transport interruption or native acceptance claim';
  if (file.endsWith('/CloudModelStreaming.kt')) return 'Partial: actual streaming/compatibility model rounds and queued web tools consume remaining configured active time; terminal budget failures enter bounded finalization only before emitted answer text. Existing evidence/recovery/permissions retained. Missing timing spans and broader parity remain';
  if (file.endsWith('/CloudToolBatchExecutor.kt')) return 'Native ordered parallel dispatcher rechecks remaining active time at task start, emits non-retryable skipped output, caps per-tool hard deadline and propagates parent cancellation after batch. Live parallel transport cancellation/progress acceptance not verified';
  if (file.endsWith('/AgentWebRendererHealth.kt')) return 'Native shared monotonic 30-second process/startup-failure cooldown; caller/page failures excluded. Pure native fixture sources added, NOT executed';
  if (file.endsWith('/AgentIsolatedWebViewRenderer.kt')) return 'iOS adaptation: process cooldown, 5-second bounded main-queue startup and one deadline across DNS/capacity/render; unconditional cancellation/one-shot completion and no late cancelled start. Not Android Binder implementation or WK fault acceptance';
  if (file.endsWith('/AgentIsolatedWebRenderService.kt')) return 'Native serialized off-main DNS preflight bounds caller wait and cancels queued work. Existing nonpersistent WK store/process-pool/same-origin and auth policies retained. OS getaddrinfo already running is not forcibly interrupted; no device recovery guarantee';
  if (file.endsWith('/build.gradle.kts') || file.endsWith('/AndroidManifest.xml') || file.endsWith('/GalaxySSIApplication.kt')) return 'Android platform/build change, not copied into iOS; no iOS version change';
  if (file.includes('/androidTest/') || file.includes('/src/test/') || file.startsWith('docs/')) return 'Reference evidence inventoried, not reproduced or claimed as iOS acceptance';
  return 'Inventoried only; requires separate code comparison and implementation or explicit existing-equivalence evidence. Not complete';
};
const inventory = { androidPR: 3007, androidCommit: android, incrementalBase: base,
  scope: 'Public web/Sogou image search, media citations, query-aware completion, renderer/research/cloud caps, atomic cache batches and workspace snapshot commits; actual scope-gated deferred source learning with encrypted records, generation invalidation, cache listing and live UI counts. Learned routing/full built-in catalog exclusion, source-health/indexed-storage performance, other image adapters/relevance, timing spans and native acceptance incomplete.',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', android + ':' + file)).digest('hex'), disposition: disposition(file) })) };
const output = path.join(root, 'apps/ios/ANDROID_3007_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(output, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(output, 'utf8')), inventory);
console.log('Android #3007: public web/image evidence, scoped deferred source learning and cache/workspace persistence contracts. Partial port; source checks only, no native or network acceptance.');
