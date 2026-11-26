// Source contracts only; not Swift typechecking, XCTest or native scheduling/storage acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '12ef97ab49a336936ea5b11b2d9c493333c2b44c';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const old = file => clean(cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function section(source, first, last) {
  const start = source.indexOf(first), end = source.indexOf(last, start + first.length);
  assert(start >= 0 && end > start, first);
  assert.equal(source.split(first).length, 2, first);
  return source.slice(start, end);
}
function retainedWatchProvider(source) {
  if (!source.includes('AgentIOSWebWatchPolicy.completed')) return source;
  return source.replace(section(source, '  private func watch(', '  private func search('),
    section(old(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift'), '  private func watch(', '  private func search('));
}
function retainedWatchCache(source) {
  if (!source.includes('  func watchRecord(')) return source;
  return source.replace(section(source, '  func watchRecord(', '  func watch(id:'), '');
}
function retainedWatchIndex(source) {
  if (!source.includes('  func compareAndPutWatch(')) return source;
  return source.replace(section(source, '  func compareAndPutWatch(', '  func clear('), '');
}
function retainedWatchFile(name, source) {
  if (name === 'AgentIOSWebIntelligenceCache') return retainedWatchCache(source);
  if (name === 'AgentIOSWebCacheIndex') return retainedWatchIndex(source);
  return source;
}
function validateWebWatch() {
  for (const [name, normalize] of [['AgentIOSURLSessionWebIntelligenceProvider', retainedWatchProvider],
    ['AgentIOSWebIntelligenceCache', retainedWatchCache], ['AgentIOSWebCacheIndex', retainedWatchIndex]])
    assert.equal(normalize(read(app + name + '.swift')), old(app + name + '.swift'), name + ': only declared watch hooks change');
  for (const name of ['AgentIOSWebIntelligenceNativeTools', 'AgentIOSURLSessionWebMediaProvider', 'AgentIOSWebPageDiff',
    'AgentIOSWebCrawlPolicy', 'AgentIOSWebLocalExtraction', 'AgentIOSWebExecutionBudget', 'AgentIOSWebEvidencePack'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const provider = section(read(app + 'AgentIOSURLSessionWebIntelligenceProvider.swift'), '  private func watch(', '  private func search(');
  for (const token of ['cachePermission', 'cacheConsent', 'networkPermission', 'publicWebConsent', 'try invocation.checkpoint()',
    'try cacheStore.watchRecord(id: id)', 'cacheStore.watchSnapshot()', 'AgentIOSWebWatchPolicy.isDue(item, now: now)',
    'defaultValue: 20, minimum: 1, maximum: 100', 'defaultValue: 15_000, minimum: 1_000, maximum: 60_000',
    'AgentIOSWebWatchPolicy.completed(item, hash: currentHash, now: nowMillis())', 'cacheStore.commitWatchCheck(completed.watch, expected: item)',
    '"write_committed"] == .bool(true)', '"watch_update_committed": .bool(false)', '"watch_update_committed": .bool(true)',
    '"source_receipts"', '"outcomes"', '"failures"', '"watch_changed"', '"persistence_failed"', '"cancelled"',
    '"remaining_count"', '"attempted_count"', 'checked.isEmpty ? "failed" : "partial"', 'details: output', 'result.output = output']) assert(provider.includes(token), token);
  assert(!provider.includes('try? invocation.checkpoint()'));
  const cache = read(app + 'AgentIOSWebIntelligenceCache.swift'), index = read(app + 'AgentIOSWebCacheIndex.swift');
  for (const token of ['guard permitted == updated', 'updated.lastCheckedAtMillis >= expected.lastCheckedAtMillis',
    'updated.lastChangedAtMillis >= expected.lastChangedAtMillis', 'updated.updatedAtMillis >= expected.updatedAtMillis',
    'compareAndPutWatch(try watchEntry(updated), expected: expected)', 'catch { return nil }']) assert(cache.includes(token), token);
  const cas = section(index, '  func compareAndPutWatch(', '  func clear(');
  for (const token of ['BEGIN IMMEDIATE TRANSACTION', 'ROLLBACK', 'entry(.watch, id: expected.id)',
    'saved.id == current.id', 'saved.updatedAtMillis == current.updated', 'guard saved == expected else { return false }',
    'try put(updated)', 'try beforeCommit()', 'try execute("COMMIT")']) assert(cas.includes(token), token);
  assert(cas.indexOf('guard saved == expected') < cas.indexOf('try put(updated)'));
  assert(cas.indexOf('try beforeCommit()') < cas.indexOf('try execute("COMMIT")'));
  const policy = read(app + 'AgentIOSWebWatchPolicy.swift');
  for (const token of ['(15...10_080)', 'watch.enabled', 'subtractingReportingOverflow', 'multipliedReportingOverflow',
    'age.partialValue >= 0', 'watch.lastCheckedAtMillis == 0', 'AgentIOSWebCrawlPolicy.canonical', 'validHash(value)',
    '!watch.lastSHA256.isEmpty', 'if changed { updated.lastChangedAtMillis = timestamp }']) assert(policy.includes(token), token);
  assert(!/URLSession|BGTask|Timer|Task\s*\{/.test(policy));
  const reference = clean(cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/AgentWebIntelligenceService.kt'], {cwd: root, encoding: 'utf8'}));
  const referenceWatch = section(reference, '    fun watch(', '    private fun runResearch(');
  for (const token of ['arguments.integer("limit", 20, 1, 100)', '"check_due"', 'arguments.long("timeout_ms", 15_000L, 1_000L, 60_000L)',
    'lastCheckedAtMillis = now', 'receipts.addAll((result["receipts"] as? List<*>).orEmpty())']) assert(referenceWatch.includes(token), token);
  assert(referenceWatch.indexOf('val now = clock()', referenceWatch.indexOf('val result = diff(')) > referenceWatch.indexOf('val result = diff('));
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebWatchTests.swift');
  for (const name of ['DueBoundaryDisabledFutureAndMalformedIntervals', 'CompletionUsesFinishTimeAndFirstBaselineDoesNotSignalChange',
    'MixedChecksPreserveFailureAndSuccessReceiptsAndForwardTimeout', 'NativeManualDisabledWatchUsesCompletionTimeAndActualDelta',
    'DueSelectionHonorsDefaultTwentyAndExplicitHundredWithoutFutureOrDisabled', 'CancellationStopsFurtherChecksAndPreservesUncommittedCursors',
    'SnapshotAndWatchCommitFailuresNeverAdvanceTheCursor', 'ConcurrentEditAndDeleteCannotBeOverwrittenOrResurrected',
    'IndependentIndexHandlesOnlyCommitOneExpectedWatchVersion', 'LocalActionsRequireCacheScopeAndValidateIDsWithoutNetwork']) assert(tests.includes('func test' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['AgentIOSWebWatchPolicy', 'AgentIOSWebWatchTests']) assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
}
module.exports = {retainedWatchProvider, retainedWatchCache, retainedWatchIndex, retainedWatchFile, validateWebWatch};
if (require.main === module) {
  validateWebWatch();
  console.log('iOS watch selection, completion clock, partial receipts and conditional cursor commits source contracts passed; no native acceptance');
}
