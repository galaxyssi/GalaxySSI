'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { verifyBrowser } = require('./browser-runtime-readiness.cjs');

test('launch, local DOM verification and close are all required', async () => {
  const events = [];
  const result = await verifyBrowser(() => ({ chromium: { launch: async () => {
    events.push('launch');
    return { newPage: async () => ({ setContent: async () => events.push('content'),
      title: async () => 'GalaxySSI readiness', locator: () => ({ innerText: async () => 'Local browser verification' }) }), close: async () => events.push('close') };
  } } }), async () => events.push('tls'));
  assert.equal(result.result.browser_ready, true);
  assert.equal(result.result.website_verified, false);
  assert.equal(result.result.tls_initialized, true);
  assert.deepEqual(events, ['launch', 'content', 'tls', 'close']);
});

test('local DOM success is not readiness when TLS initialization crashes', async () => {
  let closed = false;
  const result = await verifyBrowser(() => ({ chromium: { launch: async () => ({
    newPage: async () => ({ setContent: async () => {}, title: async () => 'GalaxySSI readiness',
      locator: () => ({ innerText: async () => 'Local browser verification' }) }),
    close: async () => { closed = true; }
  }) } }), async () => { throw new Error('Target page, context or browser has been closed'); });
  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'browser_target_closed');
  assert.equal(closed, true);
});

test('a title without rendered body text is not a usable browser', async () => {
  const result = await verifyBrowser(() => ({ chromium: { launch: async () => ({
    newPage: async () => ({ setContent: async () => {}, title: async () => 'GalaxySSI readiness',
      locator: () => ({ innerText: async () => '' }) }), close: async () => {}
  }) } }));
  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'browser_text_rendering_failed');
});

test('real Chromium initializes TLS without a network or certificate-validation exception',
  { skip: process.env.GALAXYSSI_BROWSER_INTEGRATION !== '1' }, async () => {
    const result = await verifyBrowser();
    assert.equal(result.ok, true, JSON.stringify(result));
    assert.equal(result.result.tls_initialized, true);
    assert.equal(result.result.website_verified, false);
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
