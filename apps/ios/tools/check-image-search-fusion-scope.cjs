// Source contracts only, not execution of the native ranker or live image search.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const base = '55c4f7a3e199c1c7c9b480140b442f4188ce5ad5';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
function retainedProvider(source) {
  const hook = `      if imageSearch {
        merged = AgentIOSImageSearchFusion.fuse(query: query, groups: attempts.filter { $0.resource != nil }.map {
          .init(sourceID: $0.provider, results: $0.results, weight: 1.2, authority: 0.75)
        }, limit: maxResults)
      }
`;
  if (!source.includes(hook)) return source;
  const replacements = [
    [hook, ''],
    ['sogouImages(html, limit: 20)', 'sogouImages(html, limit: maxResults)'],
    ['for attempt in attempts where !imageSearch && attempt.resource != nil {', 'for attempt in attempts where attempt.resource != nil {'],
    ['      if imageSearch { resultMetadata["image_ranker"] = .string(AgentIOSImageSearchFusion.modelID) }\n', '']
  ];
  for (const [before, after] of replacements) {
    assert.equal(source.split(before).length, 2, 'Exactly one fusion hook: ' + before);
    source = source.replace(before, after);
  }
  return source;
}
module.exports = { retainedProvider };
if (require.main === module) {
  const old = file => cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
  const file = 'apps/ios/GalaxySSI/AgentIOSURLSessionWebMediaProvider.swift';
  assert.equal(retainedProvider(read(file)), old(file), 'Only image candidate pool/fusion/label changes; ordinary search, routing, permissions, HTTP, parser and lifecycle unchanged');
  const tokenFile = 'apps/ios/GalaxySSI/AgentIOSWebSearchCompletionPolicy.swift';
  assert.equal(read(tokenFile).replace('  static func tokens(', '  private static func tokens('), old(tokenFile));
  const fusion = read('apps/ios/GalaxySSI/AgentIOSImageSearchFusion.swift');
  const match = fusion.match(/static let weights = \[([^\]]+)\]/);
  assert(match);
  const reference = JSON.parse(cp.execFileSync('git', ['show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/assets/web-intelligence/ranker-v1.json'], {cwd: root, encoding: 'utf8'}));
  assert.deepEqual(JSON.parse('[' + match[1] + ']'), reference.weights, 'Exact Android reference model weights');
  for (const token of ['0.7 * titleOverlap + 0.3 * bodyOverlap', '1.0 / 61',
    '0.28 * reciprocalRank + 0.21 * lexical + 0.14 * consensus', '0.10 * item.authority + 0.07 * freshness + 0.20 * localModel',
    '0.45 * webScore + 0.35 * titleOverlap + 0.20 * titleSpecificity', 'let freshness = 0.35',
    'min(30, max(-30, value))', 'item.ranks[group.sourceID] = min(',
    'AgentIOSWebEvidencePack.canonicalURL(image)', '(first + remaining).prefix(limit)',
    'AgentIOSWebEvidencePack.canonicalURL(item.hit.url)', 'return $0.ordinal < $1.ordinal']) assert(fusion.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentIOSWebMediaNativeToolTests.swift');
  for (const name of ['testImageFusionUsesReferenceLogisticWeightsAndTitleSpecificity',
    'testImageFusionDiversifiesCanonicalSourcePagesBeforeLimitWithoutRewritingMediaURLs',
    'testImageFusionMergesImageIdentityAcrossSourcesAndRetainsFirstSourceAndMissingDimensions',
    'testImageSearchRanksCandidatesBeyondRequestedPrefixThroughActualRegistry']) assert(tests.includes('func ' + name + '('));
  assert(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').includes('AgentIOSImageSearchFusion.swift in Sources'));
  console.log('Image fusion source contracts passed; exact reference coefficients, no native build/model/network/UI acceptance.');
}
