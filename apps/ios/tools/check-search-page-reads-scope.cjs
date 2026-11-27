// Source contracts only: no native concurrency, provider, network or latency execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'deb134e35da3ec029978ddd998000a7e265ed52a', app = 'apps/ios/GalaxySSI/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
const compact = '    if let pageReads = CloudSearchPageReads.compactReceipts(in: pack) {\n      compactPackInput["page_reads"] = pageReads\n      compactPackInput["page_read_status"] = pack["page_read_status"]\n    }\n';
function retained(f, s) {
  if (f === app + 'CloudWebGrounding.swift' && s.includes('CloudSearchPageReads.read(')) {
    const a = '  private static func attachSearchPageReads(', b = '  private static func executeWeather(';
    return s.replace(section(s, a, b), section(old(f), a, b)).replace('              provider: provider,\n              context: context', '              registry: registry,\n              context: context').replace(compact, '');
  }
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return s.split('\n').filter(l => !/CloudSearchPageReads(?:Tests)?\.swift/.test(l)).join('\n');
  return s;
}
function validate() {
  for (const f of [app + 'CloudWebGrounding.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj']) assert.equal(retained(f, read(f)), old(f), f);
  const helper = read(app + 'CloudSearchPageReads.swift');
  for (const token of ['min(max(limit, 1), 4)', 'parts.user == nil, parts.password == nil',
    'seen.insert(AgentIOSWebEvidencePack.canonicalURL(raw))', 'let urls = Array(urls.prefix(4))',
    'min(max(budgetMillis, 0), 8_000)', 'context.deadlineEpochMillis ?? Int64.max', 'child.deadlineEpochMillis = deadline',
    'guard remaining >= 1_000 else', 'page_read_insufficient_budget',
    'DispatchQueue.global(qos: .userInitiated).async', 'let registry = try AgentNativeToolRegistry().registerExecutables(',
    'cancellationRequested: { collector.cancelled }', 'group.wait(timeout:', 'if cancelled()',
    'if !closed, finishedAt < wallDeadline, DispatchTime.now() < deadline',
    'min(remaining, wallRemaining, monotonicRemaining)', 'guard requestRemaining >= 1_000 else',
    '"timeout_ms": .int(requestRemaining)', 'beforePublication()\n    if cancelled()',
    'discardResults: reason == "page_read_cancelled"', 'defer { values.removeAll() }',
    'AgentMcpJSONCodec.sha256(["parent": .string(parent), "url": .string(url), "index": .int(Int64(index))])',
    'urls.enumerated().map', 'page_read_cancelled', 'page_read_deadline',
    'items[index] = .object(body)', 'body["rank"] = items[index].objectValue?["rank"]', 'for key in bodyOrder',
    'pack["page_reads"]', 'pack["page_read_status"]', 'stats["document_count"]', 'stats["discovery_count"]',
    'AgentIOSWebEvidenceVerification.attach(pack)', 'diagnostic_not_citation_evidence', 'source_url_sha256']) assert(helper.includes(token), token);
  assert(!helper.includes('bodies.values')); assert(!helper.includes('grantedPermissions.insert'));
  assert(!helper.includes('.prefix(100)'));
  assert(helper.indexOf('let requestRemaining =') > helper.indexOf('let registry = try'));
  assert(helper.indexOf('guard requestRemaining >=') < helper.indexOf('let result = registry.invoke'));
  const grounding = read(app + 'CloudWebGrounding.swift');
  assert(grounding.includes('arguments["read_pages"]?.boolValue == true'));
  assert(grounding.includes('CloudSearchPageReads.attach(to: output, attempts: attempts)'));
  assert(grounding.includes(compact));
  for (const name of ['AgentIOSWebEvidencePack', 'AgentIOSWebEvidenceVerification', 'AgentIOSURLSessionWebIntelligenceProvider',
    'AgentIOSURLSessionWebMediaProvider', 'AgentNativeToolExecutionModels', 'CloudConversationStreamToolRounds',
    'AgentIOSWebSearchCapacity', 'GalaxySSIHealthCareTaskRuntime', 'CloudConversationStreamEngine']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'));
  const fixture = read('apps/ios/GalaxySSITests/CloudSearchPageReadsTests.swift');
  assert.equal((fixture.match(/func test/g) || []).length, 15);
  for (const token of ['testTwoPageBodiesStartTogetherButResultsRetainRankOrder',
    'testChildRegistriesKeepOwnerGrantsAndOneSharedParentDeadline', 'testDeniedPermissionsNeverReachThePageProvider',
    'testFailedSiblingKeepsDiscoveryAndSuccessfulBodyWithTruthfulStats', 'testCancellationSealsTheSnapshotAndLateWorkerCannotPublishBody',
    'testActualSearchOptInReadsPagesAndKeepsScopeThroughRegistry', 'testNoOptInDoesNotIntroduceHiddenPageFetches',
    'testCompactedOutputRetainsBoundedFailuresWithoutInventingCitationURLs',
    'testCancellationAfterWorkersCompleteDiscardsBodiesBeforePublication', 'testQueuedWorkerCannotReuseTheAdmissionTimeout',
    'testChildIdentifiersUseTheFullParentAndURLWithoutTruncationCollisions',
    'testBodyCompletingAfterWallDeadlineCannotPublish']) assert(fixture.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  for (const name of ['CloudSearchPageReads', 'CloudSearchPageReadsTests']) assert.equal((project.match(new RegExp(name + '\\.swift in Sources \\*\\/', 'g')) || []).length, 2);
  const fast = 'apps/ios/tools/check-fast-search-defaults-scope.cjs';
  assert.equal(read(fast), old(fast).replace('function retainedFastGrounding(source) {\n', "function retainedFastGrounding(source) {\n  source = require('./check-search-page-reads-scope.cjs').retained(app + 'CloudWebGrounding.swift', source);\n"));
  const fallback = 'apps/ios/tools/check-web-fallback-scope.cjs';
  assert.equal(read(fallback), old(fallback).replace('function retainedFallbackFile(file, source) {\n', "function retainedFallbackFile(file, source) {\n  source = require('./check-search-page-reads-scope.cjs').retained(file, source);\n"));
  console.log('Bounded parallel per-worker registries, queue-inclusive deadlines, publication cancellation, full-parent identities and fifteen authored-only fixture contracts passed source checks; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
