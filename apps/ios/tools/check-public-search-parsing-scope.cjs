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
assert.equal(section(provider, '  private func requestResource(', '  private func failure(_ error:'),
  section(oldProvider, '  private func requestResource(', '  private func failure(_ error:'),
  'HTTP bounds, redirect/public-host policy, resource extraction and browser transport stay unchanged');
for (const name of ['CloudConversationStreamEngine', 'CloudWebGrounding', 'GalaxySSIServices']) {
  assert.equal(read(swift(name)), git('show', base + ':' + swift(name)), name + ' unchanged in this increment');
}
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
  'testImageSearchReachesPublicEndpointAndKeepsImagesThroughEvidenceProjection']) assert(tests.includes('func ' + name + '('));
const files = git('diff', '--name-only', android + '^1', android).trim().split('\n');
const disposition = file => {
  if (file.endsWith('/AgentPublicWebSearchParser.kt')) return 'Adapted result-card DOM selection, excerpts, source verification detection, direct Baidu card URL and scoped redirect decoding using pinned SwiftSoup; native/network acceptance not run';
  if (file.endsWith('/AgentPublicWebSearchParserTest.kt')) return 'Three native fixture sources added, NOT executed; not complete Android test coverage';
  if (file.endsWith('/AgentPublicImageSearchParser.kt')) return 'Sogou inert script JSON parser connected to actual image-only endpoint and model evidence. Preserve source, original/thumbnail, dimensions and image identity; other image adapters/relevance/native acceptance incomplete';
  if (file.endsWith('/AgentPublicImageSearchTest.kt')) return 'Native parser and registry-to-evidence fixture sources added, NOT executed; not full image-search acceptance';
  if (file.endsWith('/AgentWebIntelligenceService.kt')) return 'Native research shares a monotonic deadline across query and page-read children, validates all engine IDs before searching, marks skipped queries/partial status and preserves evidence. Profile defaults applied; explicit limits retained. Ranking/cache/maintenance parity incomplete';
  if (file.endsWith('/AgentWebIntelligence.kt')) return 'Partial: native profile defaults and currently supported engine selection/validation adapted. General coordinator, relevance/ranker, all adapters and full acceptance remain incomplete';
  if (file.endsWith('/AgentWebExecutionBudget.kt')) return 'Monotonic research budget and nonextendable child invocations connected to actual search/page calls. Full model-round/tool-lane watchdog and immediate cancellation of already-running transport remain incomplete; no runtime acceptance';
  if (file.endsWith('/AgentWebRendererHealth.kt')) return 'Native shared monotonic 30-second process/startup-failure cooldown; caller/page failures excluded. Pure native fixture sources added, NOT executed';
  if (file.endsWith('/AgentIsolatedWebViewRenderer.kt')) return 'iOS adaptation: process cooldown, 5-second bounded main-queue startup and one deadline across DNS/capacity/render; unconditional cancellation/one-shot completion and no late cancelled start. Not Android Binder implementation or WK fault acceptance';
  if (file.endsWith('/AgentIsolatedWebRenderService.kt')) return 'Native serialized off-main DNS preflight bounds caller wait and cancels queued work. Existing nonpersistent WK store/process-pool/same-origin and auth policies retained. OS getaddrinfo already running is not forcibly interrupted; no device recovery guarantee';
  if (file.endsWith('/build.gradle.kts') || file.endsWith('/AndroidManifest.xml') || file.endsWith('/GalaxySSIApplication.kt')) return 'Android platform/build change, not copied into iOS; no iOS version change';
  if (file.includes('/androidTest/') || file.includes('/src/test/') || file.startsWith('docs/')) return 'Reference evidence inventoried, not reproduced or claimed as iOS acceptance';
  return 'Inventoried only; requires separate code comparison and implementation or explicit existing-equivalence evidence. Not complete';
};
const inventory = { androidPR: 3007, androidCommit: android, incrementalBase: base,
  scope: 'Public web/Sogou image evidence, renderer cooldown/bounded preflight/cleanup, monotonic research query/page budget, full-plan engine validation and truthful partial coverage. Other image engines/relevance, maintenance/index atomicity, full model-round budgets and native/performance acceptance incomplete.',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', android + ':' + file)).digest('hex'), disposition: disposition(file) })) };
const output = path.join(root, 'apps/ios/ANDROID_3007_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(output, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(output, 'utf8')), inventory);
console.log('Android #3007: public web/Sogou image parsing and actual evidence wiring contracts. Partial port; source checks only, no native or network acceptance.');
