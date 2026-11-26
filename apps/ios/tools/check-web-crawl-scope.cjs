// Source contracts only, not native networking/regex/cancellation/cache or performance acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '790a0e8e5f69e12da1427c9bf973a57d9823cf0a';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const show = (ref, file) => clean(cp.execFileSync('git', ['show', ref + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function section(source, first, last) {
  const start = source.indexOf(first), end = source.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  return source.slice(start, end);
}
function retainedCrawlProvider(source) {
  source = require('./check-web-extraction-scope.cjs').retainedExtractionProvider(source);
  if (!source.includes('var policy: AgentIOSWebCrawlPolicy')) return source;
  const prior = show(base, app + 'AgentIOSURLSessionWebIntelligenceProvider.swift');
  source = source.replace(section(source, '  private func crawl(', '  private func research('),
    section(prior, '  private func crawl(', '  private func research('));
  const navigation = 'return links.prefix(AgentIOSWebCrawlPolicy.maximumLinks).filter { ($0.stringValue?.utf8.count ?? 4_097) <= 4_096 }';
  assert.equal(source.split(navigation).length, 2);
  source = source.replace(navigation, 'return links.prefix(64).filter { ($0.stringValue?.utf8.count ?? 513) <= 512 }');
  assert(!source.includes('  private func urlAllowed(') && !source.includes('  private func links(fromHTML'));
  return source.replace('  private func titleFromHTML(', section(prior, '  private func urlAllowed(', '  private func titleFromHTML(') + '  private func titleFromHTML(');
}
function retainedCrawlMedia(source) {
  source = require('./check-encoded-web-request-scope.cjs').retainedEncodedMedia(source);
  const hook = 'let links = AgentIOSWebCrawlPolicy.links(output: ["text": .string(html)], baseURL: resource.finalURL, rawHTML: true)\n          output["links"] = .array(links.map(AgentMcpJSONValue.string))';
  if (!source.includes(hook)) return source;
  assert.equal(source.split(hook).length, 2);
  return source.replace(hook, 'let links = AgentIOSGenericArticleParser.links(in: html, baseURL: URL(string: resource.finalURL) ?? url, limit: 64)\n          if !links.isEmpty { output["links"] = .array(links.map(AgentMcpJSONValue.string)) }');
}
function validateWebCrawl() {
  const provider = read(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift');
  assert.equal(retainedCrawlProvider(provider), show(base, app + 'AgentIOSURLSessionWebIntelligenceProvider.swift'),
    'Only crawl, retired crawl-only helpers and shared navigation bounds changed; fetch/cache/permission/search/research/evidence policies retained');
  assert.equal(retainedCrawlMedia(read(app + 'AgentIOSURLSessionWebMediaProvider.swift')), show(base, app + 'AgentIOSURLSessionWebMediaProvider.swift'),
    'Only structured DOM navigation selection/count changed; HTTP/DNS/header/credential/redirect/bytes/decoder/render behavior retained');
  for (const file of ['AgentIOSWebIntelligenceNativeTools', 'AgentIOSWebIntelligenceCache', 'AgentIOSWebCacheIndex',
    'AgentIOSWebExecutionBudget', 'AgentIOSWebEvidencePack', 'AgentIOSGenericArticleParser', 'AgentIOSPublicAddressPolicy'])
    assert.equal(file === 'AgentIOSWebIntelligenceNativeTools' ? require('./check-web-page-diff-scope.cjs')
      .retainedDiffCatalog(read(app + file + '.swift')) : require('./check-web-watch-scope.cjs').retainedWatchFile(file, read(app + file + '.swift')), show(base, app + file + '.swift'), file);
  const crawl = section(provider, '  private func crawl(', '  private func research(');
  for (const token of ['AgentIOSWebCrawlPolicy(input: input)', 'AgentIOSWebCrawlDeadline(durationMillis: policy.timeoutMillis, startedAtMillis: started, now: uptimeMillis)',
    'grantedPermissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission)',
    'grantedConsents.contains(AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent)',
    'while pages.count < policy.maxPages', 'invocation.isCancellationRequested', 'budget.expired || invocation.isTimedOut',
    'try invocation.checkpoint()', 'try budget.invocation(parent: invocation',
    '? fetch(input: pageInput, invocation: child, operation: .fetch)', ': webMediaProvider.invoke(operation: .webFetch, input: pageInput, invocation: child)',
    'min(15_000, budget.remainingMillis, invocation.remainingTimeMillis)', 'policy.expand(node, finalURL: finalURL, links: links)',
    'failures.append(item); receipts.append(item)', '"text_decoding_lossless"', '"page_limit"', '"deadline_reached"',
    '"urls_discovered"', '"remaining_queue"', '"stop_reason"', 'if cacheScope { output["cache"]',
    'result.output = output; result.metadata = metadata(operation: .crawl)']) assert(crawl.includes(token), token);
  const policy = read(app + 'AgentIOSWebCrawlPolicy.swift');
  for (const token of ['maximumLinks = 100', 'intValue ?? 20, 1), 100)', 'intValue ?? 2, 0), 5)',
    'intValue ?? 60_000, 1_000), 600_000)', 'NSRegularExpression(pattern: value, options: [.caseInsensitive])', 'throw Failure.invalidPattern',
    'queue[head]', 'head += 1', 'discovered.insert(url).inserted', 'node.depth < maxDepth', 'node.depth + 1',
    'Self.origin(url) == Self.origin(root)', 'parts.port ?? 443', 'parts.user == nil, parts.password == nil',
    'AgentIOSPublicAddressPolicy.blocksHost(host)', 'discovered.count < 10_001', 'parts.fragment = nil',
    'SwiftSoup.parse', 'document.select("a[href]")', 'anchor.attr("href")', 'resolved.contains(node.url)',
    'options: .reportProgress', 'restoreUnstarted(node)', 'if shouldStop() { return nil }',
    'now().subtractingReportingOverflow(started)', '!elapsed.overflow', 'duration - min(duration, elapsed.partialValue)',
    'min(remainingMillis, parent.remainingTimeMillis, 15_000)', 'hardDeadlineEpochMillis: end',
    'parent.isCancellationRequested || self.expired']) assert(policy.includes(token), token);
  const reference = show('65655f0c79c6ab04121150229a65b089180f82f2', 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt');
  for (const token of ['arguments.integer("max_pages", 20, 1, 100)', 'arguments.integer("max_depth", 2, 0, 5)',
    'arguments.long("timeout_ms", 60_000L, 1_000L, 600_000L)', 'queue += root to 0', 'val queued = linkedSetOf(root)',
    'depth < maxDepth', 'origin(normalized) == rootOrigin', '"remaining_queue" to queue.size',
    'Regex(it.take(512), RegexOption.IGNORE_CASE)']) assert(reference.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebCrawlTests.swift');
  for (const name of ['DefaultLimitsAndDepthBoundedBreadthFirstQueue', 'DepthZeroRegexValidationAndExactOriginPorts',
    'DOMLinksKeepUnquotedAttributesAndOneHundredDestinations', 'MonotonicDeadlineSupportsTenMinutesAndClampsFixedChildren',
    'NativeRegistryCrawlReachesOneHundredAndReusesScopedCache', 'NetworkOnlyCrawlDoesNotOpenOrWriteTheEncryptedCache',
    'OverallDeadlineAndCancellationStopSubsequentRequests', 'FailedSiblingReceiptsSurviveAndAllFailedRootKeepsDiagnostics',
    'InvalidPatternsFailBeforeNativeTransport']) assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSWebCrawlPolicy', 'AgentIOSWebCrawlTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedCrawlProvider, retainedCrawlMedia, validateWebCrawl};
if (require.main === module) {
  validateWebCrawl();
  console.log('iOS crawl BFS/depth/origin/dedup/deadline, scoped cache and failure-receipt source contracts passed; no native acceptance');
}
