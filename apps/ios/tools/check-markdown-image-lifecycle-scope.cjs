// Source contracts only. Does not run Swift, URLSession, image decoding or XCTest.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const base = '921c4edeb74ae7c2f3715cae756b419cd64ace18';
const file = name => `apps/ios/GalaxySSI/${name}.swift`;
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n');
const old = name => cp.execFileSync('git', ['show', `${base}:${file(name)}`], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
const store = read(file('AgentMarkdownImageStore'));
for (const token of ['actor AgentMarkdownImageStore', 'maximumBytes = 12 * 1024 * 1024',
  'maximumCacheBytes = 64 * 1024 * 1024', 'keyAccount: "markdown-image.cache.aes256.v1"',
  'parts.fragment = nil', 'AgentIOSWebRenderURLPolicy.allows', 'SHA256.hash',
  'flights.count < 8', 'flight.waiters.count < 64', 'index >= 128',
  'guard let flight = flights[key], flight.id == id', 'flight.task.cancel()',
  'waiter.continuation.resume(throwing: CancellationError())', 'if flight.waiters.isEmpty',
  'Task.checkCancellation()', 'cipher.read(from: file, purpose: "markdown-image:" + key)',
  'cipher.write(data,', 'purpose: "markdown-image:" + key)', 'values.isSymbolicLink != true',
  'GalaxySSIImageResourceDecoder.canDecode', 'flights.removeAll()', 'cancelled.cancel()',
  'for _ in 0..<6', 'let remaining = 30 - (ProcessInfo.processInfo.systemUptime - started)',
  'try await preflight(url, timeout: remaining)', 'url = try AgentMarkdownImageStore.publicURL(next)']) {
  assert(store.includes(token), token);
}
assert(!store.includes('readMigratingPlaintext'));
const transfer = read(file('AgentRemoteImageTransfer'));
for (const token of ['URLSessionDataDelegate', 'withTaskCancellationHandler',
  'followsRedirects ? URLSessionConfiguration.default : .ephemeral', 'config.httpCookieStorage = nil',
  'config.urlCredentialStorage = nil', 'config.urlCache = nil', 'completionHandler(nil)',
  'response.value(forHTTPHeaderField: "Location")', 'http.expectedContentLength <= Int64(AgentMarkdownImageStore.maximumBytes)',
  'data.count <= AgentMarkdownImageStore.maximumBytes - body.count', 'guard outcome == nil',
  'session?.invalidateAndCancel()', 'waiter?.resume(with: result)']) assert(transfer.includes(token), token);
assert(transfer.indexOf('data.count <= AgentMarkdownImageStore.maximumBytes - body.count') < transfer.indexOf('body.append(data)'));
const loader = read(file('GalaxySSIAsyncAnimatedImageView'));
for (const token of ['publicWebImage: Bool = false', 'LoadID(url: url, publicWebImage:',
  'active: scene == .active', '.onDisappear { loader.cancel() }', '.galaxySSIRuntimePlaintextWillClear',
  'guard generation == current', 'activeTask?.cancel()', 'loadedURL = nil',
  'loader.represents(url: url, publicWebImage: publicWebImage)', 'AgentMarkdownImageStore.shared.image(url)',
  'timeout: 20, followsRedirects: true', 'onCancel: { task.cancel() }']) assert(loader.includes(token), token);
assert.equal(loader.slice(loader.indexOf('private struct GalaxySSIRemoteAnimatedImageView:')),
  old('GalaxySSIAsyncAnimatedImageView').slice(old('GalaxySSIAsyncAnimatedImageView').indexOf('private struct GalaxySSIRemoteAnimatedImageView:')),
  'Existing decoded animation/playback unchanged; this does not certify decoder memory bounds');
const rich = read(file('GalaxySSIRichContentView'));
assert.equal(rich.replace(',\n                publicWebImage: block.metadata["markdown_image_source"] == block.uri', '')
  .replace(',\n      publicWebImage: block.metadata["markdown_image_source"] == block.uri', ''), old('GalaxySSIRichContentView'),
  'Only Markdown network-mode propagation; rich rendering, copy/export, gestures and private attachments unchanged');
const viewer = read(file('GalaxySSIAnimatedImageView'));
assert.equal(viewer.replace('  let publicWebImage: Bool\n', '')
  .replace('    onSave: (() -> Void)? = nil,\n    publicWebImage: Bool = false', '    onSave: (() -> Void)? = nil')
  .replace('    self.publicWebImage = publicWebImage\n', '')
  .replace(', publicWebImage: item.publicWebImage', '')
  .replace('        },\n        publicWebImage: item.publicWebImage', '        }'), old('GalaxySSIAnimatedImageView'),
  'Only image-viewer mode propagation; local decoding, export and privacy behavior unchanged');
for (const name of ['GalaxySSIAdvancedOptionsView', 'GalaxySSIDataBackupView']) {
  const value = read(file(name)), previous = old(name);
  const start = '  private func clearRebuildableCache() {';
  const next = name === 'GalaxySSIAdvancedOptionsView' ? '  private func refreshCacheSize()' : '  private func refreshStorageMetrics()';
  assert.equal(value.slice(0, value.indexOf(start)), previous.slice(0, previous.indexOf(start)));
  assert.equal(value.slice(value.indexOf(next)), previous.slice(previous.indexOf(next)));
  const currentBody = value.slice(value.indexOf(start), value.indexOf(next));
  assert(currentBody.includes('await AgentMarkdownImageStore.shared.clear()'));
  assert(currentBody.indexOf('await AgentMarkdownImageStore.shared.clear()') < currentBody.indexOf('URLCache.shared.removeAllCachedResponses()'));
  const flattened = text => text.replace(/\s+/g, ' ').trim();
  assert.equal(flattened(currentBody.replace('    Task { @MainActor in\n', '')
    .replace('      await AgentMarkdownImageStore.shared.clear()\n', '').replace(/\n    }\n  }\n\n$/, '\n  }\n\n')),
    flattened(previous.slice(previous.indexOf(start), previous.indexOf(next))
      .replace('    URLCache.shared.removeAllCachedResponses()\n    let removedBytes = cacheBytes',
        '    let removedBytes = cacheBytes\n    URLCache.shared.removeAllCachedResponses()')), 'Existing cache purge/status retained');
}
const tests = read('apps/ios/GalaxySSITests/AgentMarkdownImageStoreTests.swift');
for (const name of ['testPublicURLRejectsUnsafeInputsAndCanonicalizesFragments',
  'testSharedFetchCancellationReleasesOnlyItsWaiter', 'testEncryptedCacheHitAndCorruptionRefetch',
  'testClearInvalidatesLateProducerBeforeNewRequest', 'testCacheWriteFailureDoesNotDiscardValidDownloadedImage',
  'testLoaderIgnoresLateOldURLAndClearsIdentityOnCancel']) assert(tests.includes('func ' + name + '('));
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentMarkdownImageStore', 'AgentRemoteImageTransfer', 'AgentMarkdownImageStoreTests']) {
  assert(project.includes(name + '.swift in Sources'));
}
console.log('Markdown image lifecycle source contracts passed; native build/network/UI acceptance NOT run. DNS preflight is NOT connection pinning.');
