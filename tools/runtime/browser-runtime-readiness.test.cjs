'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { verifyBrowser } = require('./browser-runtime-readiness.cjs');

test('launch, local DOM verification and close are all required', async () => {
  const events = [];
  const result = await verifyBrowser(() => ({ chromium: { launch: async () => {
    events.push('launch');
    return { newPage: async () => ({ setContent: async () => events.push('content'),
      title: async () => 'GalaxySSI readiness' }), close: async () => events.push('close') };
  } } }));
  assert.equal(result.result.browser_ready, true);
  assert.equal(result.result.website_verified, false);
  assert.deepEqual(events, ['launch', 'content', 'close']);
});
test('missing module differs from missing executable and missing native library', async () => {
  for (const [error, code] of [
    [Object.assign(new Error('private path'), { code: 'MODULE_NOT_FOUND' }), 'browser_module_missing'],
    [new Error("Executable doesn't exist at /private/path"), 'browser_executable_missing'],
    [new Error('error while loading shared libraries: libX11.so.6'), 'browser_native_library_missing']
  ]) {
    const result = await verifyBrowser(() => { throw error; });
    assert.equal(result.error.code, code);
    assert.equal(result.error.details.browser_ready, false);
    assert.equal(JSON.stringify(result).includes('/private/path'), false);
  }
});
test('failed local verification closes its temporary browser', async () => {
  let closed = false;
  const result = await verifyBrowser(() => ({ chromium: { launch: async () => ({
    newPage: async () => ({ setContent: async () => {}, title: async () => 'wrong' }),
    close: async () => { closed = true; }
  }) } }));
  assert.equal(result.ok, false);
  assert.equal(closed, true);
});
