'use strict';

const { browserFailure } = require('./browser-session-engine.cjs');

async function verifyBrowser(load = () => require('playwright')) {
  let browser;
  try {
    const { chromium } = load();
    browser = await chromium.launch({ headless: true, timeout: 45000,
      ...(process.env.GALAXYSSI_BROWSER_EXECUTABLE ? { executablePath: process.env.GALAXYSSI_BROWSER_EXECUTABLE } : {}) });
    const page = await browser.newPage();
    await page.setContent('<title>GalaxySSI readiness</title><p>Local browser verification</p>', { timeout: 15000 });
    if (await page.title() !== 'GalaxySSI readiness') throw new Error('Readiness page mismatch');
    await browser.close();
    browser = null;
    return { ok: true, result: { browser_ready: true, verification: 'chromium_local_page',
      website_verified: false, goal_terminal: false } };
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
module.exports = { verifyBrowser };
