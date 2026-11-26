// Source contracts only, not Swift, XCTest, native regex/HTTP/cache or model acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '4a2802017ef5003d0bc8477978856ce0acb95a6a';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function section(source, start, end) {
  const first = source.indexOf(start), last = source.indexOf(end, first + start.length);
  assert(first >= 0 && last > first, start);
  return source.slice(first, last);
}
function retainedExtractionProvider(source) {
  source = require('./check-web-page-diff-scope.cjs').retainedDiffProvider(source);
  if (!source.includes('AgentIOSWebLocalExtraction.structured(')) return source;
  return source.replace(section(source, '  private func extract(', '  private func crawl('),
    section(old(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift'), '  private func extract(', '  private func crawl('));
}
function validateWebExtraction() {
  const provider = read(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift');
  assert.equal(retainedExtractionProvider(provider), old(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift'),
    'Only extract changes; existing fetch, search, crawl, cache, research, permissions, model budget and transport kernels retained');
  for (const name of ['AgentIOSWebIntelligenceNativeTools', 'AgentIOSURLSessionWebMediaProvider', 'AgentIOSWebEvidencePack',
    'AgentIOSWebIntelligenceCache', 'AgentIOSWebCacheIndex', 'AgentIOSWebExecutionBudget', 'AgentIOSPublicArticleParser'])
    assert.equal(name === 'AgentIOSWebIntelligenceNativeTools' ? require('./check-web-page-diff-scope.cjs')
      .retainedDiffCatalog(read(app + name + '.swift')) : read(app + name + '.swift'), old(app + name + '.swift'), name);
  const extract = section(provider, '  private func extract(', '  private func crawl(');
  for (const token of ['try invocation.checkpoint()', 'if !url.isEmpty', 'guard cacheScope else',
    'grantedPermissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission)',
    'grantedConsents.contains(AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent)',
    'grantedPermissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.networkPermission)',
    'grantedConsents.contains(AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent)',
    'fullCachedDocument(url: canonicalURL(url))', 'cachedFetchResult(document, requestedURL: url',
    'guard networkScope else', 'maximum: 60_000', 'try budget.invocation(parent: invocation',
    'result = fetch(input: fetchInput, invocation: child, operation: .fetch)',
    'AgentIOSWebLocalExtraction.requestedFields(input["fields"])', 'AgentIOSWebLocalExtraction.structured(',
    'details["structured"] = .object(structured)', 'details["requested_fields"]', '"local_readability_and_metadata"',
    '"supplied_content" : "url_document"', 'if url.isEmpty, cacheScope', 'now <= Int64.max - ttl && cacheStore.putDocument',
    '"fetch_tier": "local_content"', '"network": .bool(false)', '"retrieved_at_epoch_ms": .null',
    '"write_committed": .bool(committed)', 'catch AgentNativeToolInvocationError.cancelled']) assert(extract.includes(token), token);
  assert(extract.indexOf('guard networkScope else') < extract.indexOf('result = fetch('));
  assert(extract.indexOf('try AgentIOSWebLocalExtraction.structured(') < extract.indexOf('cacheStore.putDocument('));
  const helper = read(app + 'AgentIOSWebLocalExtraction.swift');
  for (const token of ['Set<[UInt16]>', 'limit: 128', 'result.count == 100', '(3...160).contains(count)',
    'count < 100', '".!?;:"', '$0 == 35 || $0 == 32', 'headings.count == 100',
    'NSRegularExpression.escapedPattern(for:', '.{1,500}', '.caseInsensitive, .anchorsMatchLines', 'fields.prefix(100)',
    'try checkpoint()', '(0x3400...0x9fff)', '(0x3040...0x30ff)', '(0xac00...0xd7af)', 'return "en"']) assert(helper.includes(token), token);
  assert(!/URLSession|NaturalLanguage|UserDefaults|cacheStore|Keychain|CloudModel/.test(helper));
  const policy = read(app + 'AgentIOSWebCrawlPolicy.swift');
  assert.equal(policy.replace('NSRegularExpression(pattern: value, options: [.caseInsensitive])', 'NSRegularExpression(pattern: value)'),
    old(app + 'AgentIOSWebCrawlPolicy.swift'), 'Only fix reference optionalRegex ignore-case behavior in crawl policy');
  const crawlTests = read('apps/ios/GalaxySSITests/AgentIOSWebCrawlTests.swift');
  assert.equal(crawlTests.replace('"include_pattern": .string("ROOT|KEEP"), "exclude_pattern": .string("BLOCKED")',
    '"include_pattern": .string("root|keep"), "exclude_pattern": .string("blocked")'), old('apps/ios/GalaxySSITests/AgentIOSWebCrawlTests.swift'));
  const nativeTests = read('apps/ios/GalaxySSITests/AgentIOSWebIntelligenceNativeToolTests.swift');
  assert.equal(nativeTests.replace('extract.output["evidence_pack"]?.objectValue?["items"]?.arrayValue?.first?.objectValue?["excerpt"]?.stringValue',
    'extract.output["text"]?.stringValue'), old('apps/ios/GalaxySSITests/AgentIOSWebIntelligenceNativeToolTests.swift'),
    'Existing local extraction assertion now inspects the retained evidence projection, not a stripped duplicate body');
  const reference = clean(cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt'], {cwd: root, encoding: 'utf8'}));
  for (const token of ['if (url.isNotBlank())', 'arguments.stringList("fields", 100, 128)', '"headings" to headings(document.content)',
    '"language" to AgentWebIntelligenceText.language(document.content)', 'findField(document.content, field)',
    '"local_readability_and_metadata"', 'RegexOption.IGNORE_CASE', 'it.length in 3..160',
    'line.length < 100', 'Regex.escape(field.trim())', '.{1,500}']) assert(reference.includes(token), token);
  const textReference = clean(cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligence.kt'], {cwd: root, encoding: 'utf8'}));
  const language = section(textReference, '    fun language(value:', '    fun canonicalUrl(');
  for (const token of ['u3400', 'u9fff', 'u3040', 'u30ff', 'uac00', 'ud7af', '-> "zh"', '-> "ja"', '-> "ko"', 'else -> "en"']) assert(language.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebExtractionTests.swift');
  for (const name of ['HeadingsAndLiteralRequestedFieldsFollowReferenceHeuristics', 'FieldHeadingAndCaptureBoundsAreExplicit',
    'LanguageHintRetainsReferenceRangePriority', 'RegistrySuppliedContentExtractsAndCachesWithoutNetwork',
    'CacheOnlyURLTakesPrecedenceOverSuppliedContent', 'NetworkURLReusesFetchAndForceRefreshWithBothScopes',
    'StructuredCheckpointAndCancelledProviderDoNotPersistLocalContent', 'DirectLocalExtractionWithoutCacheScopeHasNoPersistence'])
    assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSWebLocalExtraction', 'AgentIOSWebExtractionTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedExtractionProvider, validateWebExtraction};
if (require.main === module) {
  validateWebExtraction();
  console.log('iOS local/URL structured extraction, literal field bounds, optional network scope and crawl ignore-case source contracts passed; no native acceptance');
}
