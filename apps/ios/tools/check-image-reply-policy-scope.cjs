// Source contracts only. Does not execute providers, rendering or native tests.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const base = '4adcd727ffd5d3a62301ce5c8132f1432755abb0';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
const file = 'apps/ios/GalaxySSI/AgentRichContentMaterializer.swift';
const policy = read(file);
const instruction = 'For a simple image-search reply, use Markdown images and source links instead of rich JSON. Never repeat the same images in both Markdown and a rich image/gallery document.';
assert(policy.includes('  static let imageSearchInstruction = "' + instruction + '"\n'));
assert.equal(policy.replace('  static let imageSearchInstruction = "' + instruction + '"\n', '')
  .replace(' + " " + imageSearchInstruction', ''), old(file),
  'Only shared image answer guidance added; HTML/video verification, materialization and output validation unchanged');
for (const name of ['CloudModelClient', 'CloudModelClientStreaming', 'CloudConversationNonStreamingToolEngine',
  'CloudConversationStreamEngine', 'AgentConnectorStreamUpdate', 'AgentRichMarkdownParser', 'AgentIOSWebEvidenceVerification']) {
  const file = `apps/ios/GalaxySSI/${name}.swift`;
  assert.equal(read(file), old(file), name + ' unchanged');
}
const client = read('apps/ios/GalaxySSI/CloudModelClient.swift');
assert(client.includes('return systemPrompt(languagePolicy: languagePolicy) + "\\n" + AgentVisualOutputPolicy.prompt + "\\n" + textOnlyEvidence()'));
assert(client.includes('    \\(AgentVisualOutputPolicy.prompt)'));
const preparation = read('apps/ios/GalaxySSI/CloudModelClientStreaming.swift');
assert(preparation.includes('let systemPrompt = Self.conversationSystemPrompt(languagePolicy: languagePolicy, images: images)'));
const progress = read('apps/ios/GalaxySSI/AgentConnectorStreamUpdate.swift');
assert(progress.includes('"web_image_search": "Searching images"'));
assert(progress.includes('localize("galaxyssi.agent.progress.operation.\\(code)", operation)'));
assert(progress.includes('if status != "failed", ["web_search", "web_image_search"].contains(code) { return nil }'));
const chinese = read('apps/ios/GalaxySSI/zh-Hans.lproj/Localizable.strings');
assert(/"galaxyssi\.agent\.progress\.operation\.web_image_search"\s*=\s*"[^"]+";/.test(chinese));
const tests = read('apps/ios/GalaxySSITests/CloudModelClientStreamingTests.swift');
assert(tests.includes('func testDefaultImageSearchPresentationGuidanceReachesAllProviderAndCompatibilityBodies('));
const progressTestsFile = 'apps/ios/GalaxySSITests/AgentRunPolicyTests.swift';
const progressTests = read(progressTestsFile);
const start = progressTests.indexOf('  @MainActor\n  func testImageSearchProgressKeepsLocalizedFailureAndSuppressesRoutineSearchNoise(');
const end = progressTests.indexOf('  @MainActor\n  func testConnectorResearchDiagnosticsStayOnTheMatchingToolEventAcrossReplay(', start);
assert(start >= 0 && end > start);
assert.equal(progressTests.slice(0, start) + progressTests.slice(end), old(progressTestsFile),
  'Existing progress tests and baseline parser issues retained');
console.log('Shared image reply policy and existing localized image progress source contracts passed; no native model/provider/UI acceptance.');
