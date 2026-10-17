'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { BrowserSessions, websiteUrl, publicUrl, browserFailure, checkBrowserNativeDependencies,
  browserRuntimeLaunchOptions } = require('./browser-session-engine.cjs');

test('published pack fonts are available without writing into the signed image', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const root = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'browser-fonts-'));
  try {
    const fonts = path.join(root, 'pack/share/fonts');
    const original = path.join(root, 'pack/lib/fontconfig/fonts.conf');
    fs.mkdirSync(fonts, { recursive: true });
    fs.mkdirSync(path.dirname(original), { recursive: true });
    fs.writeFileSync(original, 'original config');
    const env = { FONTCONFIG_FILE: original, PLAYWRIGHT_BROWSERS_PATH: path.join(root, 'pack/lib/ms-playwright') };
    const options = { platform: 'linux', env, stateRoot: path.join(root, 'state') };
    const first = browserRuntimeLaunchOptions(options);
    assert.equal(first.env.PLAYWRIGHT_BROWSERS_PATH, env.PLAYWRIGHT_BROWSERS_PATH);
    assert.ok(fs.readFileSync(first.env.FONTCONFIG_FILE, 'utf8').includes(fonts));
    assert.equal(browserRuntimeLaunchOptions(options).env.FONTCONFIG_FILE, first.env.FONTCONFIG_FILE);
    assert.equal(fs.readdirSync(options.stateRoot).length, 1);
    assert.equal(fs.readFileSync(original, 'utf8'), 'original config');
    assert.equal(env.FONTCONFIG_FILE, original);
    assert.deepEqual(browserRuntimeLaunchOptions({ ...options, platform: 'win32' }), {});
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
});

test('NSS dlopen dependencies are checked in pack and system library paths before dispatch', () => {
  const modules = ['libsoftokn3.so', 'libfreeblpriv3.so', 'libnssckbi.so'];
  for (const missing of modules) {
    assert.throws(() => checkBrowserNativeDependencies({ platform: 'linux', arch: 'arm64', libraryPath: '/pack/libs',
      exists: file => file.startsWith('/pack/libs/') && !file.endsWith(missing) }), error =>
      error.code === 'browser_native_library_missing' && error.details.library === missing &&
      error.details.executed === false && error.message.includes('libnss3'));
  }
  for (const directory of ['/pack/libs', '/usr/lib/aarch64-linux-gnu']) {
    assert.doesNotThrow(() => checkBrowserNativeDependencies({ platform: 'linux', arch: 'arm64',
      libraryPath: '/pack/libs', exists: file => modules.some(name => file === `${directory}/${name}`) }));
  }
  assert.doesNotThrow(() => checkBrowserNativeDependencies({ platform: 'win32', exists: () => false }));
});

test('a cancelled queued mutation never executes or claims an unknown side effect', async () => {
  const engine = new BrowserSessions({});
  let release;
  const previous = new Promise(resolve => { release = resolve; });
  let executed = 0;
  let closed = 0;
  engine.sessions.set('fixture', { tail: previous, context: { close: async () => { closed++; } } });
  engine.operate = async () => { executed++; };
  const controller = new AbortController();
  const pending = engine.execute({ session_id: 'fixture', operation: 'click' }, controller.signal);
  controller.abort(); release();
  await assert.rejects(pending, error => error.code === 'browser_operation_cancelled' &&
    error.details.executed === false && !error.details.outcome_unknown);
  assert.equal(executed, 0);
  assert.equal(closed, 0);
});

test('handoff waits for an in-flight action and fences later model actions in the same queue', async () => {
  const engine = new BrowserSessions({});
  let finishAction;
  let reportStarted;
  const started = new Promise(resolve => { reportStarted = resolve; });
  const active = new Promise(resolve => { finishAction = resolve; });
  const session = { id: 'fixture', tail: Promise.resolve(), context: {},
    pages: new Map([['page', { isClosed: () => false }]]) };
  engine.sessions.set(session.id, session);
  let executions = 0;
  engine.operate = async () => { executions++; reportStarted(); await active; };
  const first = engine.execute({ session_id: session.id, page_id: 'page', operation: 'click' });
  await started;
  const handoff = engine.beginHumanControl({ session_id: session.id, page_id: 'page' });
  const queued = engine.execute({ session_id: session.id, page_id: 'page', operation: 'click' });
  const rejected = assert.rejects(queued, { code: 'browser_user_control_active' });
  assert.equal(session.humanControl, undefined);
  finishAction();
  await first;
  const lease = await handoff;
  await rejected;
  assert.equal(executions, 1);
  await engine.finishHumanControl({ session_id: session.id }, lease.control_token);
});

test('cancelling a queued handoff neither grants control nor closes the current browser', async () => {
  const engine = new BrowserSessions({});
  let release;
  let closed = false;
  const session = { id: 'fixture', tail: new Promise(resolve => { release = resolve; }),
    context: { close: async () => { closed = true; } }, pages: new Map() };
  engine.sessions.set(session.id, session);
  const controller = new AbortController();
  const handoff = engine.beginHumanControl({ session_id: session.id, page_id: 'page' }, controller.signal);
  controller.abort(); release();
  await assert.rejects(handoff, error => error.code === 'browser_operation_cancelled' && error.details.executed === false);
  assert.equal(session.humanControl, undefined);
  assert.equal(closed, false);
});

test('browser errors retain actionable native and network codes without typed secrets', () => {
  const network = browserFailure(new Error('page.goto: net::ERR_CERT_AUTHORITY_INVALID private-password'), 'navigate');
  assert.equal(network.details.network_error, 'ERR_CERT_AUTHORITY_INVALID');
  assert.equal(network.details.outcome_unknown, true);
  assert.ok(!JSON.stringify(network).includes('private-password'));
  const native = browserFailure(new Error('error while loading shared libraries: libnss3.so: private-path'), 'create');
  assert.equal(native.code, 'browser_native_library_missing');
  assert.equal(native.details.library, 'libnss3.so');
  assert.equal(native.details.outcome_unknown, false);
});

test('cancelling a running human preview does not destroy the live account context', async () => {
  const engine = new BrowserSessions({});
  let release;
  let started;
  let closed = 0;
  const ready = new Promise(resolve => { started = resolve; });
  const work = new Promise(resolve => { release = resolve; });
  const session = { id: 'fixture-preview', tail: Promise.resolve(), context: { close: async () => { closed++; } } };
  engine.sessions.set(session.id, session);
  const controller = new AbortController();
  const observation = engine.inSession({ session_id: session.id, operation: 'snapshot' }, controller.signal, async () => {
    started(); await work; return { observed: true };
  });
  await ready;
  controller.abort(); release();
  assert.equal((await observation).observed, true);
  assert.equal(closed, 0);
  assert.equal(session.lost, undefined);
});

test('browser URLs accept websites, reject file access and embedded credentials', () => {
  assert.equal(websiteUrl('https://example.com/a'), 'https://example.com/a');
  for (const value of ['file:///etc/passwd', 'javascript:alert(1)', 'https://user:secret@example.com', 'not a URL']) {
    assert.throws(() => websiteUrl(value), { code: 'invalid_url' });
  }
});

test('returned URLs redact common authentication parameters', () => {
  const safe = publicUrl('https://u:p@example.com/path?access_token=secret&code=otp&page=2#password');
  assert.equal(new URL(safe).searchParams.get('page'), '2');
  assert.ok(!safe.includes('secret') && !safe.includes('otp') && !safe.includes('password'));
});

test('interactive browser fixture: authentication, stale controls, contexts, frames and pagination',
  { skip: process.env.GALAXYSSI_BROWSER_INTEGRATION !== '1' }, async t => {
    const { chromium } = require('playwright');
    const engine = new BrowserSessions(chromium, { timeoutMs: 4000, launchOptions:
      process.env.GALAXYSSI_BROWSER_TEST_EXECUTABLE ? { executablePath: process.env.GALAXYSSI_BROWSER_TEST_EXECUTABLE } : {} });
    const server = http.createServer((req, res) => {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      if (req.url === '/login' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
          const name = new URLSearchParams(body).get('name');
          res.writeHead(303, { 'Set-Cookie': `fixture_account=${name}; HttpOnly; SameSite=Strict; Path=/`, Location: '/private?page=1' });
          res.end();
        });
        return;
      }
      if (req.url.startsWith('/private')) {
        const name = /fixture_account=(alice|bob)/.exec(req.headers.cookie || '')?.[1];
        if (!name) { res.writeHead(302, { Location: '/' }); res.end(); return; }
        const page = new URL(req.url, 'http://localhost').searchParams.get('page') || '1';
        res.end(`<h1>Signed in as ${name}</h1><table><tr><td>order-${page}</td></tr></table><a href="/private?page=2">Next page</a><button onclick="window.open('/popup')">Open details</button>`);
        return;
      }
      if (req.url === '/popup') { res.end('<h1>Details in a new tab</h1>'); return; }
      if (req.url === '/frame') { res.end('<h1>Embedded content</h1><button onclick="this.textContent=\'Frame clicked\'">Frame action</button>'); return; }
      if (req.url === '/frames') { res.end('<h1>Frames</h1><iframe src="/frame"></iframe>'); return; }
      if (req.url === '/long') {
        res.end(`<p>${'x'.repeat(33000)}END-OF-ARTICLE</p>${Array.from({ length: 205 }, (_, i) => `<button>Action ${i}</button>`).join('')}`); return;
      }
      if (req.url === '/dialog') {
        res.end('<h1>Dialog fixture</h1><button onclick="if(confirm(\'Confirm fixture action?\')) this.textContent=\'Confirmed\'">Confirm action</button>'); return;
      }
      if (req.url === '/stale') {
        res.end('<h1>Changing page</h1><button onclick="this.textContent=\'Clicked\'">Action</button>'); return;
      }
      res.end('<h1>Fixture sign in</h1><form method="POST" action="/login"><label>Name<input name="name"></label><label>Password<input name="password" type="password"></label><button>Sign in</button></form>');
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(async () => { await engine.close(); await new Promise(resolve => server.close(resolve)); });
    const base = `http://127.0.0.1:${server.address().port}`;
    const alice = await engine.execute({ operation: 'create', url: base });
    const bob = await engine.execute({ operation: 'create', url: base });
    const scope = result => ({ session_id: result.session_id, page_id: result.page_id });
    const observe = result => engine.execute({ ...scope(result), operation: 'observe' });
    async function act(result, operation, label, value) {
      const view = await observe(result);
      const node = view.controls.find(control => control.label === label);
      assert.ok(node, `Missing observed control: ${label}`);
      return engine.execute({ ...scope(result), operation, revision: view.revision, node_id: node.node_id, value });
    }

    await t.test('actual form login preserves cookies and never returns password values', async () => {
      await act(alice, 'fill', 'Name', 'alice');
      await act(alice, 'fill', 'Password', 'fixture-private-password');
      assert.ok(!JSON.stringify(await observe(alice)).includes('fixture-private-password'));
      const submitted = await act(alice, 'click', 'Sign in');
      assert.equal(submitted.business_success_verified, false);
      await engine.sessions.get(alice.session_id).pages.get(alice.page_id).waitForURL('**/private?page=1');
      assert.match((await observe(alice)).text, /Signed in as alice/);
    });
    await t.test('a second account context never inherits another account login', async () => {
      await engine.execute({ ...scope(bob), operation: 'navigate', url: `${base}/private?page=1` });
      assert.match((await observe(bob)).text, /Fixture sign in/);
      await act(bob, 'fill', 'Name', 'bob');
      await act(bob, 'click', 'Sign in');
      await engine.sessions.get(bob.session_id).pages.get(bob.page_id).waitForURL('**/private?page=1');
      assert.match((await observe(bob)).text, /Signed in as bob/);
      assert.match((await observe(alice)).text, /Signed in as alice/);
    });
    await t.test('pagination reads authenticated content from both pages', async () => {
      assert.match((await observe(alice)).text, /order-1/);
      await act(alice, 'click', 'Next page');
      await engine.sessions.get(alice.session_id).pages.get(alice.page_id).waitForURL('**page=2');
      assert.match((await observe(alice)).text, /order-2/);
    });
    await t.test('popups remain in the same account context and have explicit page handles', async () => {
      const page = engine.sessions.get(alice.session_id).pages.get(alice.page_id);
      const popup = page.waitForEvent('popup');
      await act(alice, 'click', 'Open details'); await popup;
      const pages = await engine.execute({ session_id: alice.session_id, operation: 'pages' });
      assert.equal(pages.pages.length, 2);
      const details = pages.pages.find(item => item.page_id !== alice.page_id);
      assert.match((await engine.execute({ session_id: alice.session_id, page_id: details.page_id, operation: 'observe' })).text,
        /Details in a new tab/);
    });
    await t.test('stale observations reject actions without guessing controls', async () => {
      await engine.execute({ ...scope(bob), operation: 'navigate', url: `${base}/stale` });
      const view = await observe(bob);
      await engine.sessions.get(bob.session_id).pages.get(bob.page_id).evaluate(() => {
        document.querySelector('button').textContent = 'Changed';
      });
      await assert.rejects(engine.execute({ ...scope(bob), operation: 'click', revision: view.revision,
        node_id: view.controls[0].node_id }), { code: 'page_observation_stale' });
      assert.match((await observe(bob)).text, /Changed/);
    });
    await t.test('iframe controls require their own fresh observation', async () => {
      await engine.execute({ ...scope(bob), operation: 'navigate', url: `${base}/frames` });
      const page = engine.sessions.get(bob.session_id).pages.get(bob.page_id);
      await page.frameLocator('iframe').getByRole('button').waitFor();
      const top = await observe(bob);
      const frame_id = top.frames[0].frame_id;
      const frame = await engine.execute({ ...scope(bob), operation: 'observe', frame_id });
      await engine.execute({ ...scope(bob), operation: 'click', frame_id, revision: frame.revision,
        node_id: frame.controls[0].node_id });
      assert.match((await engine.execute({ ...scope(bob), operation: 'observe', frame_id })).text, /Frame clicked/);
    });
    await t.test('cross-context page handles cannot be used by another session', async () => {
      await assert.rejects(engine.execute({ session_id: alice.session_id, page_id: bob.page_id, operation: 'observe' }),
        { code: 'page_not_found' });
    });
    await t.test('long text and large control sets remain reachable through explicit observation cursors', async () => {
      await engine.execute({ ...scope(bob), operation: 'navigate', url: `${base}/long` });
      const first = await observe(bob);
      assert.equal(first.next_text_offset, 16000);
      assert.equal(first.next_control_offset, 200);
      const remaining = await engine.execute({ ...scope(bob), operation: 'observe', text_offset: 32000, control_offset: 200 });
      assert.match(remaining.text, /END-OF-ARTICLE/);
      assert.equal(remaining.next_text_offset, null);
      assert.equal(remaining.controls.length, 5);
      assert.equal(remaining.next_control_offset, null);
    });
    await t.test('dialogs are surfaced as observations and never silently approved', async () => {
      await engine.execute({ ...scope(bob), operation: 'navigate', url: `${base}/dialog` });
      await act(bob, 'click', 'Confirm action');
      const pending = await observe(bob);
      assert.equal(pending.dialog.type, 'confirm');
      assert.equal(pending.action_dispatched, false);
      await engine.execute({ ...scope(bob), operation: 'dialog', accept: false });
      assert.match((await observe(bob)).text, /Confirm action/);
    });
    await t.test('screenshots are real JPEG data, not a successful-dispatch placeholder', async () => {
      const image = await engine.execute({ ...scope(bob), operation: 'screenshot' });
      const bytes = Buffer.from(image.data_b64, 'base64');
      assert.equal(bytes.readUInt16BE(0), 0xffd8); assert.ok(bytes.length > 1000);
    });
    await t.test('user control excludes model reads and writes without leaking its private lease', async () => {
      const before = await observe(bob);
      const lease = await engine.beginHumanControl(scope(bob));
      assert.equal(lease.business_success_verified, false);
      for (const operation of ['observe', 'pages', 'screenshot', 'fill', 'navigate', 'close']) {
        await assert.rejects(engine.execute({ ...scope(bob), operation, url: base }), error => {
          assert.equal(error.code, 'browser_user_control_active');
          assert.equal(error.details.executed, false);
          assert.ok(!JSON.stringify(error).includes(lease.control_token));
          return true;
        });
      }
      await assert.rejects(engine.beginHumanControl(scope(bob)), { code: 'browser_user_control_active' });
      const released = await engine.finishHumanControl(scope(bob), lease.control_token);
      assert.equal(released.next_action, 'observe');
      assert.equal(released.business_success_verified, false);
      assert.equal(released.authentication_verified, false);
      await assert.rejects(engine.execute({ ...scope(bob), operation: 'click', revision: before.revision,
        node_id: before.controls[0].node_id }), { code: 'page_observation_stale' });
      assert.match((await observe(bob)).text, /Confirm action/);
    });
    await t.test('host handoff cannot be invoked through the model operation dispatcher', async () => {
      await assert.rejects(engine.execute({ ...scope(bob), operation: 'human_control_begin' }), { code: 'unknown_operation' });
      assert.equal(engine.sessions.get(bob.session_id).humanControl, null);
    });
    await t.test('user authentication keeps the original context and agent must verify by observing', async () => {
      const login = await engine.execute({ operation: 'create', url: base });
      const context = engine.sessions.get(login.session_id).context;
      const lease = await engine.beginHumanControl(scope(login));
      const human = input => engine.executeHuman({ ...scope(login), ...input }, lease.control_token);
      async function userAction(operation, label, value) {
        const view = await human({ operation: 'observe' });
        const node = view.controls.find(item => item.label === label);
        return human({ operation, revision: view.revision, node_id: node.node_id, value });
      }
      await userAction('fill', 'Name', 'alice');
      await userAction('fill', 'Password', 'private-user-only-fixture');
      assert.ok(!JSON.stringify(await human({ operation: 'observe' })).includes('private-user-only-fixture'));
      await userAction('click', 'Sign in');
      await engine.sessions.get(login.session_id).pages.get(login.page_id).waitForURL('**/private?page=1');
      const released = await engine.finishHumanControl(scope(login), lease.control_token);
      assert.equal(released.authentication_verified, false);
      assert.equal(engine.sessions.get(login.session_id).context, context);
      assert.match((await observe(login)).text, /Signed in as alice/);
      await act(login, 'click', 'Next page');
      await engine.sessions.get(login.session_id).pages.get(login.page_id).waitForURL('**page=2');
      assert.match((await observe(login)).text, /order-2/);
      await engine.execute({ ...scope(login), operation: 'close' });
    });
    await t.test('leases are account-scoped, non-replayable and cannot release a later handoff', async () => {
      const lease = await engine.beginHumanControl(scope(bob));
      for (const token of [undefined, '', 'not-a-capability', '0'.repeat(64)]) {
        await assert.rejects(engine.executeHuman({ ...scope(bob), operation: 'observe' }, token),
          { code: 'browser_user_control_invalid' });
        await assert.rejects(engine.finishHumanControl(scope(bob), token), { code: 'browser_user_control_invalid' });
      }
      const other = await engine.beginHumanControl(scope(alice));
      await assert.rejects(engine.executeHuman({ ...scope(alice), operation: 'observe' }, lease.control_token),
        { code: 'browser_user_control_invalid' });
      await assert.rejects(engine.executeHuman({ session_id: bob.session_id, page_id: alice.page_id, operation: 'observe' },
        lease.control_token), { code: 'page_not_found' });
      await engine.finishHumanControl(scope(bob), lease.control_token);
      const next = await engine.beginHumanControl(scope(bob));
      assert.notEqual(next.control_token, lease.control_token);
      await assert.rejects(engine.finishHumanControl(scope(bob), lease.control_token), { code: 'browser_user_control_invalid' });
      await assert.rejects(observe(bob), { code: 'browser_user_control_active' });
      await engine.finishHumanControl(scope(bob), next.control_token);
      await engine.finishHumanControl(scope(alice), other.control_token);
    });
    await t.test('native user surface shows the actual viewport and types only into the user-selected field', async () => {
      const login = await engine.execute({ operation: 'create', url: base });
      const lease = await engine.beginHumanControl(scope(login));
      const human = input => engine.executeHuman({ ...scope(login), ...input }, lease.control_token);
      let view = await human({ operation: 'snapshot', width: 400, height: 600 });
      assert.deepEqual(view.viewport, { width: 400, height: 600 });
      assert.equal(view.mime_type, 'image/jpeg');
      assert.equal(Buffer.from(view.data_b64, 'base64').readUInt16BE(0), 0xffd8);
      await assert.rejects(human({ operation: 'insert_text', revision: view.revision, value: 'not-focused' }),
        { code: 'browser_text_target_missing' });
      await assert.rejects(human({ operation: 'pointer', revision: view.revision, x: 401, y: 20 }),
        { code: 'invalid_user_pointer' });
      const page = engine.sessions.get(login.session_id).pages.get(login.page_id);
      for (const [selector, value] of [['input[name=name]', 'alice'], ['input[type=password]', 'private-manual-input']]) {
        const box = await page.locator(selector).boundingBox();
        view = await human({ operation: 'snapshot' });
        await human({ operation: 'pointer', revision: view.revision, x: box.x + box.width / 2, y: box.y + box.height / 2 });
        view = await human({ operation: 'snapshot' });
        await human({ operation: 'insert_text', revision: view.revision, value });
      }
      view = await human({ operation: 'snapshot' });
      assert.ok(!view.text.includes('private-manual-input'));
      const submit = await page.locator('button').boundingBox();
      await human({ operation: 'pointer', revision: view.revision, x: submit.x + submit.width / 2, y: submit.y + submit.height / 2 });
      await page.waitForURL('**/private?page=1');
      await assert.rejects(human({ operation: 'pointer', revision: view.revision, x: 10, y: 10 }),
        { code: 'page_observation_stale' });
      await engine.finishHumanControl(scope(login), lease.control_token);
      assert.match((await observe(login)).text, /Signed in as alice/);
      for (const operation of ['snapshot', 'pointer', 'scroll', 'insert_text', 'press']) {
        await assert.rejects(engine.execute({ ...scope(login), operation }), { code: 'unknown_operation' });
      }
      await engine.execute({ ...scope(login), operation: 'close' });
    });
    await t.test('observations made during user control cannot be replayed after release', async () => {
      await engine.execute({ ...scope(bob), operation: 'navigate', url: `${base}/stale` });
      const lease = await engine.beginHumanControl(scope(bob));
      const view = await engine.executeHuman({ ...scope(bob), operation: 'observe' }, lease.control_token);
      await engine.finishHumanControl(scope(bob), lease.control_token);
      await assert.rejects(engine.execute({ ...scope(bob), operation: 'click', revision: view.revision,
        node_id: view.controls[0].node_id }), { code: 'page_observation_stale' });
      await act(bob, 'click', 'Action');
      assert.match((await observe(bob)).text, /Clicked/);
    });
    await t.test('closed handles fail explicitly instead of silently creating a new session', async () => {
      await engine.execute({ session_id: bob.session_id, operation: 'close' });
      await assert.rejects(observe(bob), { code: 'session_not_found' });
    });
    await t.test('browser process death marks previous sessions lost and never replays a mutation', async () => {
      const { BrowserUserControl } = require('./browser-user-control.cjs');
      const events = [];
      const control = new BrowserUserControl(engine, () => ({
        publish(state) { events.push({ session_id: state.session_id, handoff_id: state.id }); }, close() {}
      }));
      const lease = await control.executeHost({ ...scope(alice), operation: 'human_control_begin' });
      assert.equal(control.sessions.get(alice.session_id).waiters.size, 0);
      await engine.browser.close();
      assert.deepEqual(events, [{ session_id: alice.session_id, handoff_id: lease.handoff_id }]);
      assert.equal(control.sessions.size, 0);
      control.close();
      await assert.rejects(observe(alice), { code: 'session_lost' });
    });
  });
