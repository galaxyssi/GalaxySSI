// Retained-source contracts only; not Swift, DOM, network or device acceptance.
const assert = require('node:assert/strict');
const cp = require('node:child_process'), fs = require('node:fs'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701';
const app = 'apps/ios/GalaxySSI/';
const read = f => require('./check-original-page-archive-queue-scope.cjs').retained(f, fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n'));
const old = f => cp.execFileSync('git', ['show', base + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
function between(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start);
  assert.equal(source.indexOf(start, a + start.length), -1, 'Unique hook ' + start);
  return source.slice(a, b);
}
const file = app + 'AgentIOSPhonePublicHTMLAttachment.swift', attachment = read(file);
const hook = between(attachment, '          if let export = preparation.export,', '        }\n        accumulator.set');
assert.equal(attachment.replace(hook, ''), old(file), 'Only explicit export hook changes preparation');
for (const text of ['network.webMediaProvider as? AgentIOSURLSessionWebMediaToolProvider',
  'invocation.remainingTimeMillis > 0', '!invocation.isCancellationRequested',
  'media.originalPageAsset(address, maxBytes: limit, invocation: invocation)',
  'AgentIOSPhonePublicHTMLExport(id: export.id', 'data: original.data']) assert(hook.includes(text), text);
const providerFile = app + 'AgentIOSURLSessionWebMediaProvider.swift', provider = read(providerFile);
const method = between(provider, '  func originalPageAsset(', '  private func executeWeb(');
assert.equal(provider.replace(method, ''), old(providerFile), 'Existing transport, redirects, classification and tool kernels unchanged');
for (const text of ['grantedPermissions.contains', 'grantedConsents.contains',
  'validatedPublicHTTPSURL(address)', 'contentPolicy: .download', '8 * 1_024 * 1_024',
  'min(invocation.deadlineEpochMillis, startedAt + 15_000)',
  'hardDeadlineEpochMillis: invocation.deadlineEpochMillis',
  'cancellationRequested: { invocation.isCancellationRequested }', '!resource.isPartial']) assert(method.includes(text), text);
const builder = read(app + 'AgentIOSOriginalPageDocument.swift');
for (const text of ['import SwiftSoup', 'SwiftSoup.parse(decoded.text, base)', 'guard decoded.lossless',
  'attempted.count < 128', 'remaining = maximumAssetBytes', 'remaining -= item.data.count',
  'encodedRemaining -= item.data.count', 'data.count <= maximumOutputBytes',
  '"data-src", "data-original", "data-lazy-src", "src"', 'try link.replaceWith(style)',
  'css(text, item.finalURL)', 'encodedRemaining -= rewritten.utf8.count',
  'default-src \'none\'', 'img-src data:', 'form-action \'none\'',
  'element.removeAttr(attribute.getKey())', '"noopener noreferrer"',
  'galaxyssi-archive-missing-assets', 'LanguagePolicySettings.resolveInterface(language)',
  'table: "WeChatArticleExportNative"']) assert(builder.includes(text), text);
assert(!builder.includes('WKWebView') && !builder.includes('URLSession'), 'Pure builder does not execute markup or create transport');
const testsFile = 'apps/ios/GalaxySSITests/AgentIOSPhonePublicHTMLAttachmentTests.swift', tests = read(testsFile);
const addedTests = between(tests, '  func testOriginalPageAssetLoaderKeepsPermissionDeadlineAndByteBounds()', '  @MainActor');
assert.equal(tests.replace('import SwiftSoup\n', '').replace(addedTests, ''), old(testsFile), 'Existing fixtures retained');
assert.equal((addedTests.match(/  func testOriginalPage/g) || []).length, 6);
for (const locale of ['en', 'zh-Hans']) {
  const file = app + locale + '.lproj/WeChatArticleExportNative.strings';
  const source = read(file), additions = source.split('\n').filter(l => l.startsWith('"original_page_archive_'));
  assert.equal(additions.length, 3);
  assert.equal(source.split('\n').filter(l => !l.startsWith('"original_page_archive_')).join('\n'), old(file));
  assert(additions.some(l => l.includes('%1$lld') && l.includes('%2$@')));
}
const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', project = read(projectFile);
assert.equal(project.split('\n').filter(l => !l.includes('AgentIOSOriginalPageDocument.swift')).join('\n'), old(projectFile));
assert.equal((project.match(/AgentIOSOriginalPageDocument.swift in Sources/g) || []).length, 2);
for (const name of ['AgentIOSWebIntelligenceNativeTools', 'AgentIOSURLSessionWebIntelligenceProvider',
  'AgentIOSPublicAddressPolicy', 'GalaxySSIPublicPageHTMLExportDocument']) assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
console.log('Original-DOM explicit export, bounded asset loader, retained transport/privacy/attachment sources and six authored-only fixture contracts passed; no native acceptance.');
