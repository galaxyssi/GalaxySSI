// Source contracts only, not native parsing, image rendering or artifact acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = 'ba6ffe5c8330d170054042378fae4e26f3ae8cb1', app = 'apps/ios/GalaxySSI/';
const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function retained(f, s) {
  if (f === app + 'AgentRichMarkdownParser.swift' && s.includes('fileprivate static func imageWrapper(')) {
    s = s.replace(section(s, '  fileprivate static func imageWrapper(', '  private static func citationReferenceEnd('), '');
    const start = '      if marker.lowerBound > text.startIndex {', end = '      let leading = String(text[cursor..<promotedStart])';
    return s.replace(section(s, start, end), section(old(f), start, end));
  }
  if (f === app + 'AgentRichContentModels.swift' && s.includes('      let rawURI = uri.replacingOccurrences')) {
    const a = '    if !uri.isEmpty {', b = '    if !fallbackText.isEmpty || !title.isEmpty {';
    return s.replace(section(s, a, b), section(old(f), a, b));
  }
  if (f.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return s.split('\n').filter(line => !line.includes('AgentOrderedReplyImagesTests.swift')).join('\n');
  return s;
}
function validate() {
  for (const f of [app + 'AgentRichMarkdownParser.swift', app + 'AgentRichContentModels.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj']) assert.equal(retained(f, read(f)), old(f), f);
  const parser = read(app + 'AgentRichMarkdownParser.swift');
  const helper = section(parser, '  fileprivate static func imageWrapper(', '  private static func citationReferenceEnd(');
  for (const token of ['markdownLabelEnd(characters, at: 0)', 'labelEnd == text.distance(from: start, to: imageEnd)',
    'markdownLink(characters, at: 0)', 'text.index(start, offsetBy: link.end)']) assert(helper.includes(token), token);
  const wrapper = section(parser, '      if marker.lowerBound > text.startIndex {', '      let leading = String(text[cursor..<promotedStart])');
  for (const token of ['text[opening] == "["', 'AgentMarkdownArtifactReferences.imageWrapper', 'isSafeMarkdownImageURL(value)', 'promotedEnd = wrapper.end']) assert(wrapper.includes(token), token);
  const models = read(app + 'AgentRichContentModels.swift');
  const identity = section(models, '    if !uri.isEmpty {', '    if !fallbackText.isEmpty || !title.isEmpty {');
  for (const token of ['URLComponents(string: rawURI)', 'components.scheme = scheme.lowercased()',
    'components.host = host.lowercased()', 'components.string ?? rawURI']) assert(identity.includes(token), token);
  for (const forbidden of ['rawURI.lowercased()', 'components.path =', 'components.query =', 'components.fragment =']) assert(!identity.includes(forbidden), forbidden);
  const tests = read('apps/ios/GalaxySSITests/AgentOrderedReplyImagesTests.swift');
  assert.equal((tests.match(/func test/g) || []).length, 11);
  for (const token of ['testBalancedSourceParenthesesConsumeTheEntireLinkedImage', 'testAngledSourceWithQuotedTitleDoesNotLeaveMarkdownResidue',
    'testReplyOrderAndCaptionsFollowMarkupNotURLSorting', 'testCaseSensitiveImagePathsRemainDistinctInDecodedReply',
    'testDuplicateQualityUpgradeRetainsOriginalSlotWithoutReorderingOthers', 'testAuthenticatedDigestAndLocalVideoIdentityRulesRemainUnchanged']) assert(tests.includes(token), token);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal((project.match(/AgentOrderedReplyImagesTests.swift in Sources \*\//g) || []).length, 2);
  for (const name of ['AgentDesktopArtifactModels', 'AgentBlobArtifactReceiver', 'AgentRichContentMaterializer', 'CloudConversationNonStreamingToolEngine']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'));
  assert.equal(read('apps/ios/GalaxySSITests/AgentRichContentMermaidTests.swift'), old('apps/ios/GalaxySSITests/AgentRichContentMermaidTests.swift'));
  const timing = 'apps/ios/tools/check-mqtt-inbound-timing-scope.cjs';
  assert.equal(read(timing), old(timing)
    .replace("const read = f => fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n');", "const read = f => require('./check-ordered-reply-images-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(f, s) {\n', "function retained(f, s) {\n  s = require('./check-ordered-reply-images-scope.cjs').retained(f, s);\n"));
  const reply = 'apps/ios/tools/check-image-reply-policy-scope.cjs';
  assert.equal(read(reply), old(reply).replace("const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');",
    "const read = file => require('./check-ordered-reply-images-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));"));
  console.log('Shared linked-image wrapper parsing, case-sensitive URI identity, retained caption/order/digest behavior and eleven authored-only fixture contracts passed source checks; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
