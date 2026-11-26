// Source contracts only, not XCTest, Swift typecheck, native storage/transport or semantic verification.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '32b523c39e554012f2a2a16da902b450c5d6a630';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function once(source, before, after) {
  assert.equal(source.split(before).length, 2, 'One declared page-diff hook: ' + before);
  return source.replace(before, after);
}
function section(source, first, last) {
  const start = source.indexOf(first), end = source.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  return source.slice(start, end);
}
const watchGate = '      guard invocation.context.grantedPermissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.networkPermission),\n        invocation.context.grantedConsents.contains(AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent) else {\n        return failure("public_web_scope_required", "Checking saved page watches requires public web permission and consent")\n      }\n';
function retainedDiffProvider(source) {
  source = require('./check-web-watch-scope.cjs').retainedWatchProvider(source);
  if (!source.includes('AgentIOSWebPageDiff.summarize(')) return source;
  source = once(source, section(source, '  private func diff(', '  private func extract('),
    section(old(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift'), '  private func diff(', '  private func extract('));
  source = once(source, watchGate, '');
  source = once(source, '    status: String,\n    includeCacheMetadata: Bool = true\n', '    status: String\n');
  return once(source, '    if includeCacheMetadata {\n      output["cache"] = .object(cacheStore.cacheMetadata().merging([\n        "hit": .bool(false),\n        "shared_fetch": .bool(false)\n      ]) { _, next in next })\n    }',
    '    output["cache"] = .object(cacheStore.cacheMetadata().merging([\n      "hit": .bool(false),\n      "shared_fetch": .bool(false)\n    ]) { _, next in next })');
}
function retainedDiffCatalog(source) {
  if (!source.includes('maximum: operation == .diff ? 60_000 : 120_000')) return source;
  source = once(source, 'maximum: operation == .diff ? 60_000 : 120_000', 'maximum: 120_000');
  return once(source, '"fields": stringArraySchema(maxItems: 100, maxLength: 128),\n        "force": boolSchema(),\n        "timeout_ms": integerSchema(minimum: 1_000, maximum: 60_000)',
    '"fields": stringArraySchema(maxItems: 100, maxLength: 128),\n        "force": boolSchema(),\n        "timeout_ms": integerSchema(minimum: 1_000, maximum: 120_000)');
}
function validatePageDiff() {
  const provider = read(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift');
  assert.equal(retainedDiffProvider(provider), old(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift'),
    'Only diff, watch network gate and optional cache metadata projection change; fetch/extract/search/crawl/routing/HTTP kernels retained');
  assert.equal(retainedDiffCatalog(read(app + 'AgentIOSWebIntelligenceNativeTools.swift')), old(app + 'AgentIOSWebIntelligenceNativeTools.swift'),
    'Only diff/extract timeout input maxima change; required permissions, effects, executor, fetch/schema/output/pack policies retained');
  for (const name of ['AgentIOSURLSessionWebMediaProvider', 'AgentIOSWebIntelligenceCache', 'AgentIOSWebCacheIndex',
    'AgentIOSWebCrawlPolicy', 'AgentIOSWebLocalExtraction', 'AgentIOSWebExecutionBudget', 'AgentIOSWebEvidencePack'])
    assert.equal(require('./check-web-watch-scope.cjs').retainedWatchFile(name, read(app + name + '.swift')), old(app + name + '.swift'), name);
  const diff = section(provider, '  private func diff(', '  private func extract(');
  for (const token of ['try invocation.checkpoint()', 'grantedPermissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.networkPermission)',
    'grantedConsents.contains(AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent)',
    'grantedPermissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission)',
    'grantedConsents.contains(AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent)',
    'cacheScope ? cacheStore.document(url: url, allowStale: true) : nil', '"text/x-galaxyssi-search-result"',
    'AgentIOSWebTextDecoder.reusable', 'defaultValue: 15_000, minimum: 1_000, maximum: 60_000',
    'try budget.invocation(parent: invocation', 'operation: .webOpen', 'invocation: child',
    '"text_decoding_lossless"', 'AgentIOSWebPageDiff.summarize', 'try child.checkpoint()',
    'cacheScope && cacheFetchedDocument', 'includeCacheMetadata: cacheScope', '"write_committed"',
    'status: "completed"', '"trimmed_line_set"', '"summary_truncated"', '"previous_available"',
    'catch AgentNativeToolInvocationError.cancelled', 'catch AgentNativeToolInvocationError.timedOut']) assert(diff.includes(token), token);
  assert(diff.indexOf('AgentIOSWebPageDiff.summarize') < diff.indexOf('cacheFetchedDocument'));
  assert(diff.indexOf('"text_decoding_lossless"') < diff.indexOf('cacheFetchedDocument'));
  assert(provider.includes('    case "check", "check_due":\n' + watchGate));
  const helper = read(app + 'AgentIOSWebPageDiff.swift');
  for (const token of ['Set<[UInt16]>', 'result.keys.insert(Array(value.utf16)).inserted',
    'before.ordered.filter { !after.keys.contains(Array($0.utf16)) }', 'after.ordered.filter { !before.keys.contains(Array($0.utf16)) }',
    'values.prefix(40)', 'bounded(line, length: 300)', 'bounded(text, length: 32_768)',
    'removed.count > 40 || added.count > 40', 'line.utf16.count > 300', 'try checkpoint()',
    'trimmingCharacters(in: .whitespacesAndNewlines)', '(0xD800...0xDBFF)']) assert(helper.includes(token), token);
  assert(!/URLSession|cacheStore|Keychain|Logger|CloudModel|NaturalLanguage/.test(helper));
  const reference = clean(cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt'], {cwd: root, encoding: 'utf8'}));
  for (const token of ['(before - after).take(40)', '(after - before).take(40)', 'it.take(300)', 'trim().take(32_768)',
    '"summary" to if (changed) diffSummary(previous?.content.orEmpty(), current.content) else ""']) assert(reference.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebPageDiffTests.swift');
  for (const name of ['OrderedSetSummaryTrimsDeduplicatesAndIgnoresReordering', 'SummaryBoundsFortyLinesPerSideAndSafeUTF16Prefixes',
    'NativeRegistryProducesRealChangesThenEmptyUnchangedSummary', 'RawHashChangeWithoutReadableLineChangeHasEmptySummary',
    'NetworkFailureAndLossyDecodeDoNotReplacePriorSnapshot', 'OptionalCommitFailureKeepsPriorSnapshotAndReturnsNetworkDiff',
    'NetworkOnlyComparisonCannotReadWriteOrExposeCache', 'SearchSnippetCannotBecomePriorPageSnapshot',
    'WatchChecksRequireNetworkScopeAndReuseActualDiff', 'CheckpointCancellationAndDeclaredTimeoutCaps']) assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSWebPageDiff', 'AgentIOSWebPageDiffTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedDiffProvider, retainedDiffCatalog, validatePageDiff};
if (require.main === module) {
  validatePageDiff();
  console.log('iOS bounded ordered-line page diff, snapshot preservation, cache/network scope and timeout schema source contracts passed; no native acceptance');
}
