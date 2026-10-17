'use strict';

const { browserFailure, BrowserOperationError, checkBrowserNativeDependencies, browserRuntimeLaunchOptions } = require('./browser-session-engine.cjs');
const https = require('node:https');

async function verifyTlsInitialization(page, browser) {
  // A certificate-less loopback endpoint exercises NSS without internet access or bypassing TLS checks.
  const server = https.createServer({ minVersion: 'TLSv1.2' });
  server.on('tlsClientError', () => {});
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    try {
      await page.goto(`https://127.0.0.1:${server.address().port}/`, { timeout: 15000 });
      throw new Error('TLS probe unexpectedly accepted a server without a certificate');
    } catch (error) {
      if (!browser.isConnected() || !/ERR_SSL_VERSION_OR_CIPHER_MISMATCH|ERR_SSL_PROTOCOL_ERROR/.test(error.message)) throw error;
    }
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}

async function verifyBrowser(load = () => require('playwright'), verifyTls = verifyTlsInitialization) {
  let browser;
  try {
    const { chromium } = load();
    checkBrowserNativeDependencies();
    browser = await chromium.launch({ headless: true, timeout: 45000, ...browserRuntimeLaunchOptions(),
      ...(process.env.GALAXYSSI_BROWSER_EXECUTABLE ? { executablePath: process.env.GALAXYSSI_BROWSER_EXECUTABLE } : {}) });
    const page = await browser.newPage();
    await page.setContent('<title>GalaxySSI readiness</title><p>Local browser verification</p>', { timeout: 15000 });
    if (await page.title() !== 'GalaxySSI readiness') throw new Error('Readiness page mismatch');
    if (!(await page.locator('body').innerText()).includes('Local browser verification')) {
      throw new BrowserOperationError('browser_text_rendering_failed',
        'Chromium started but visible text did not render. Inspect Fontconfig and the browser pack fonts, then repeat readiness.',
        { goal_terminal: false });
    }
    await verifyTls(page, browser);
    await browser.close();
    browser = null;
    return { ok: true, result: { browser_ready: true, verification: 'chromium_local_page',
      tls_initialized: true, website_verified: false, goal_terminal: false } };
  } catch (error) {
    const failure = error.code === 'MODULE_NOT_FOUND'
      ? { code: 'browser_module_missing', message: 'Playwright cannot be loaded. Inspect the browser pack and NODE_PATH.', details: {} }
      : browserFailure(error, 'create');
    return { ok: false, error: { code: failure.code, message: failure.message,
      details: { ...failure.details, executed: false, browser_ready: false, goal_terminal: false } } };
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
}

if (require.main === module) verifyBrowser().then(result => process.stdout.write(JSON.stringify(result) + '\n'));
module.exports = { verifyBrowser, verifyTlsInitialization };
