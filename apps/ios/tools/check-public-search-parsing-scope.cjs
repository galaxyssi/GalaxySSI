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
assert(provider.includes('results: try parseSearchResults('));
assert(provider.includes('baseURL: resource.finalURL'));
assert(provider.includes('AgentIOSPublicSearchParser.parse(html, baseURL: baseURL, limit: 100).filter'));
for (const token of ['"excerpt": .string(result.excerpt)', '"snippet": .string(result.excerpt)',
  'resultMetadata["unavailable_sources"]', '"error_code": .string(failure(error).error?.code',
  'return failure("source_verification_required", "Search source requires verification")']) assert(provider.includes(token));
assert(!provider.includes('private func normalizedSearchResultURL('));
assert(!provider.includes('private func duckDuckGoRedirectTarget('));
const oldProvider = git('show', base + ':' + swift('AgentIOSURLSessionWebMediaProvider'));
const section = (source, start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
assert.equal(section(provider, '  private func requestResource(', '  private func failure(_ error:'),
  section(oldProvider, '  private func requestResource(', '  private func failure(_ error:'),
  'HTTP bounds, redirect/public-host policy, resource extraction and browser transport stay unchanged');
for (const name of ['AgentIOSDynamicWebRenderer', 'CloudConversationStreamEngine', 'CloudWebGrounding', 'GalaxySSIServices']) {
  assert.equal(read(swift(name)), git('show', base + ':' + swift(name)), name + ' unchanged in this increment');
}
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const token of ['AgentIOSPublicSearchParser.swift in Sources', 'SwiftSoup in Frameworks',
  'productName = SwiftSoup;', 'repositoryURL = "https://github.com/scinfu/SwiftSoup";', 'version = 2.6.0;']) assert(project.includes(token));
const pins = JSON.parse(read('apps/ios/GalaxySSI.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'));
const pin = pins.pins.find(p => p.identity === 'swiftsoup');
assert.equal(pin.state.revision, '0e96a20ffd37a515c5c963952d4335c89bed50a6');
assert.equal(pin.state.version, '2.6.0');
const tests = read('apps/ios/GalaxySSITests/AgentIOSWebMediaNativeToolTests.swift');
for (const name of ['testPublicSearchParserKeepsCardsAndSnippetsButNotNavigationOrAds',
  'testPublicSearchParserUnwrapsOwnedRedirectsAndRejectsUnsafeDestinations',
  'testPublicSearchParserUsesBaiduCardDestinationAndReportsVerification']) assert(tests.includes('func ' + name + '('));
const files = git('diff', '--name-only', android + '^1', android).trim().split('\n');
const disposition = file => {
  if (file.endsWith('/AgentPublicWebSearchParser.kt')) return 'Adapted result-card DOM selection, excerpts, source verification detection, direct Baidu card URL and scoped redirect decoding using pinned SwiftSoup; native/network acceptance not run';
  if (file.endsWith('/AgentPublicWebSearchParserTest.kt')) return 'Three native fixture sources added, NOT executed; not complete Android test coverage';
  if (file.endsWith('/AgentWebIntelligenceService.kt')) return 'Partial: actual iOS search provider now returns excerpts and unavailable-source codes; remaining ranking/cache/maintenance behavior not ported by this increment';
  if (file.endsWith('/build.gradle.kts') || file.endsWith('/AndroidManifest.xml') || file.endsWith('/GalaxySSIApplication.kt')) return 'Android platform/build change, not copied into iOS; no iOS version change';
  if (file.includes('/androidTest/') || file.includes('/src/test/') || file.startsWith('docs/')) return 'Reference evidence inventoried, not reproduced or claimed as iOS acceptance';
  return 'Inventoried only; requires separate code comparison and implementation or explicit existing-equivalence evidence. Not complete';
};
const inventory = { androidPR: 3007, androidCommit: android, incrementalBase: base,
  scope: 'Partial public web search parsing integration only. Image search, renderer recovery, maintenance/index atomicity, model-loop budgets and performance acceptance remain incomplete.',
  files: files.map(file => ({ path: file, sha256: crypto.createHash('sha256').update(git('show', android + ':' + file)).digest('hex'), disposition: disposition(file) })) };
const output = path.join(root, 'apps/ios/ANDROID_3007_SOURCE_INVENTORY.json');
if (process.argv.includes('--write')) fs.writeFileSync(output, JSON.stringify(inventory, null, 2) + '\n');
else assert.deepEqual(JSON.parse(fs.readFileSync(output, 'utf8')), inventory);
console.log('Android #3007: public result DOM parsing, excerpts and unavailable-source contracts. Partial port; source checks only, no native or network acceptance.');
