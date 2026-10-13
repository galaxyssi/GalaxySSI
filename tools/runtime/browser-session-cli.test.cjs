'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const http = require('node:http');
const { randomUUID, randomBytes, createHash, createHmac, createDecipheriv } = require('node:crypto');
const { spawn } = require('node:child_process');
const { rpc, equalToken, safeFailure, consumeRequestEnvironment, consumeHostCapability, existingEndpoint, DRIVER_VERSION } = require('./browser-session-cli.cjs');

test('App host authority is consumed before normal client execution and never written as an endpoint', () => {
  const token = randomBytes(32).toString('hex');
  const environment = { GALAXYSSI_BROWSER_HOST_TOKEN: token, KEEP: 'present' };
  assert.equal(consumeHostCapability(environment), token);
  assert.deepEqual(environment, { KEEP: 'present' });
  assert.throws(() => consumeHostCapability({ GALAXYSSI_BROWSER_HOST_TOKEN: 'invalid' }),
    { code: 'browser_host_capability_invalid' });
});

test('ephemeral Unicode request chunks are reconstructed and removed before daemon creation', () => {
  const raw = JSON.stringify({ operation: 'fill', value: '\u4f60\u597d'.repeat(5000) });
  const encoded = Buffer.from(raw).toString('base64');
  const parts = encoded.match(/.{1,4096}/g);
  const environment = { GALAXYSSI_BROWSER_REQUEST_COUNT: String(parts.length), UNRELATED: 'preserved' };
  parts.forEach((part, i) => { environment[`GALAXYSSI_BROWSER_REQUEST_${i}`] = part; });
  assert.equal(consumeRequestEnvironment(environment), raw);
  assert.deepEqual(environment, { UNRELATED: 'preserved' });
});

test('IPC capabilities reject malformed and non-ASCII tokens without throwing', () => {
  assert.equal(equalToken('a'.repeat(64), 'a'.repeat(64)), true);
  for (const value of ['b'.repeat(64), 'é'.repeat(64), '', null, 'a'.repeat(63)]) {
    assert.equal(equalToken(value, 'a'.repeat(64)), false);
  }
});

test('unexpected process errors do not disclose credentials or host paths', () => {
  const failure = safeFailure(new Error('password=private; /private/profile/path'));
  assert.equal(failure.error.details.goal_terminal, false);
  assert.ok(!JSON.stringify(failure).includes('private'));
});

test('an observation timeout sends one request and does not automatically restart or resubmit', async t => {
  const socketName = process.platform === 'win32' ? `\\\\.\\pipe\\galaxyssi-rpc-test-${randomUUID()}`
    : path.join(os.tmpdir(), `gssi-test-${randomUUID()}.sock`);
  let requests = 0;
  const sockets = new Set();
  const server = net.createServer(socket => {
    sockets.add(socket); socket.on('error', () => {}); socket.on('close', () => sockets.delete(socket));
    socket.on('data', () => { requests++; });
  });
  await new Promise(resolve => server.listen(socketName, resolve));
  t.after(async () => {
    for (const socket of sockets) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  });
  await assert.rejects(rpc({ socket: socketName, token: 'a'.repeat(64) }, { operation: 'click' }, 100),
    { code: 'browser_observation_timeout' });
  assert.equal(requests, 1);
});

test('driver changes cannot silently reuse a live daemon or force an automatic replacement', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'galaxyssi-browser-version-'));
  const socketName = process.platform === 'win32' ? `\\\\.\\pipe\\galaxyssi-version-${randomUUID()}`
    : path.join(directory, 'service.sock');
  let requests = 0;
  const server = net.createServer(socket => {
    socket.on('data', () => {
      requests++;
      socket.end(`${JSON.stringify({ ok: true, result: { alive: true, driver_version: 'old-driver' } })}\n`);
    });
  });
  await new Promise(resolve => server.listen(socketName, resolve));
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
    assert.equal(path.dirname(fs.realpathSync(directory)), fs.realpathSync(os.tmpdir()));
    fs.rmSync(directory, { recursive: true, force: true });
  });
  const endpoint = { socket: socketName, token: 'a'.repeat(64), pid: process.pid };
  fs.writeFileSync(path.join(directory, 'endpoint.json'), JSON.stringify(endpoint), { mode: 0o600 });
  await assert.rejects(existingEndpoint(directory), { code: 'browser_driver_changed' });
  assert.deepEqual(await existingEndpoint(directory, false, true), endpoint);
  assert.equal(requests, 2);
  assert.equal(fs.existsSync(path.join(directory, 'starting.json')), false);
  assert.match(DRIVER_VERSION, /^[a-f0-9]{64}$/);
});

test('CLI integration retains a live browser across independent tool processes and isolates scopes',
  { skip: process.env.GALAXYSSI_BROWSER_INTEGRATION !== '1' }, async t => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'galaxyssi-browser-cli-'));
    let navigationStarted;
    const started = new Promise(resolve => { navigationStarted = resolve; });
    const server = http.createServer((req, res) => {
      if (req.url === '/hang') { navigationStarted(); return; }
      res.setHeader('Content-Type', 'text/html');
      if (req.url === '/signin') {
        res.end('<form method="POST" action="/login"><label>Account<input name="account"></label>' +
          '<label>Password<input type="password" name="password"></label><button>Sign in</button></form>');
        return;
      }
      if (req.url === '/login' && req.method === 'POST') {
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
          const input = new URLSearchParams(body);
          if (input.get('account') !== 'public-fixture' || input.get('password') !== 'user-only-secret') {
            res.writeHead(401); res.end('Authentication failed'); return;
          }
          res.writeHead(303, { 'Set-Cookie': 'fixture_logged_in=yes; HttpOnly; SameSite=Strict; Path=/', Location: '/private' });
          res.end();
        });
        return;
      }
      if (req.url === '/private') {
        res.end(req.headers.cookie?.includes('fixture_logged_in=yes') ? '<h1>Authenticated fixture content</h1>' : '<h1>Not signed in</h1>');
        return;
      }
      res.end('<h1>Live browser fixture</h1><input aria-label="Draft"><button onclick="this.textContent=\'Saved\'">Save</button>');
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const hostToken = randomBytes(32).toString('hex');
    const workspaceRoot = path.join(root, 'workspaces');
    fs.mkdirSync(workspaceRoot, { mode: 0o700 });
    const env = { ...process.env, GALAXYSSI_BROWSER_STATE_ROOT: root, GALAXYSSI_BROWSER_HOST_TOKEN: hostToken,
      GALAXYSSI_BROWSER_EVENT_WORKSPACE_ROOT: workspaceRoot,
      GALAXYSSI_BROWSER_EXECUTABLE: process.env.GALAXYSSI_BROWSER_TEST_EXECUTABLE || '' };
    const scope = 'd'.repeat(64);
    async function command(input, selectedScope = scope, host = false) {
      return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(__dirname, 'browser-session-cli.cjs'), ...(host ? ['host'] : []), selectedScope],
          { env: { ...env, GALAXYSSI_BROWSER_REQUEST: JSON.stringify(input) }, windowsHide: true });
        let stdout = ''; let stderr = '';
        child.stdout.on('data', chunk => { stdout += chunk; });
        child.stderr.on('data', chunk => { stderr += chunk; });
        child.on('error', reject);
        child.on('exit', () => { try { resolve(JSON.parse(stdout)); } catch { reject(new Error(`No structured CLI result: ${stderr}`)); } });
      });
    }
    t.after(async () => {
      for (const entry of fs.readdirSync(root)) {
        try {
          const endpoint = JSON.parse(fs.readFileSync(path.join(root, entry, 'endpoint.json'), 'utf8'));
          await rpc(endpoint, { operation: 'service_shutdown' }, 10000);
        } catch {}
      }
      await new Promise(resolve => server.close(resolve));
      assert.equal(path.dirname(fs.realpathSync(root)), fs.realpathSync(os.tmpdir()));
      fs.rmSync(root, { recursive: true, force: true });
    });
    const created = await command({ operation: 'create', url: `http://127.0.0.1:${server.address().port}` });
    assert.equal(created.ok, true, JSON.stringify(created));
    const ids = { session_id: created.result.session_id, page_id: created.result.page_id };
    const first = await command({ ...ids, operation: 'observe' });
    assert.equal(first.ok, true);
    const draft = first.result.controls.find(node => node.label === 'Draft');
    assert.equal((await command({ ...ids, operation: 'fill', node_id: draft.node_id,
      revision: first.result.revision, value: 'kept in the same live page' })).ok, true);
    const endpoint = JSON.parse(fs.readFileSync(path.join(root, scope, 'endpoint.json'), 'utf8'));
    const hostEndpoint = await existingEndpoint(path.join(root, scope), true, false, hostToken);
    assert.notEqual(hostEndpoint.token, endpoint.token);
    assert.equal(hostEndpoint.driver_version, DRIVER_VERSION);
    assert.equal(fs.existsSync(path.join(root, scope, 'host-endpoint.json')), false);
    assert.ok(!fs.readFileSync(path.join(root, scope, 'endpoint.json'), 'utf8').includes(hostToken));
    await assert.rejects(existingEndpoint(path.join(root, scope), true), { code: 'browser_host_capability_missing' });

    await t.test('model IPC cannot acquire, operate or release host user control', async () => {
      for (const operation of ['human_control_begin', 'human_control_execute', 'human_control_finish']) {
        const result = await rpc(endpoint, { ...ids, operation });
        assert.equal(result.error.code, 'browser_host_control_required');
        assert.equal(result.error.details.executed, false);
      }
    });

    await t.test('host CLI authenticates in the same browser and wakes the original observer', async () => {
      const login = await command({ operation: 'create', url: `http://127.0.0.1:${server.address().port}/signin` });
      const page = { session_id: login.result.session_id, page_id: login.result.page_id };
      const begin = await command({ ...page, operation: 'human_control_begin' }, scope, true);
      assert.equal(begin.ok, true, JSON.stringify(begin));
      assert.equal(begin.result.control_token, undefined);
      const handoff = begin.result;
      const blocked = await command({ ...page, operation: 'observe' });
      assert.equal(blocked.error.code, 'browser_user_control_active');
      assert.equal(blocked.error.details.handoff_id, handoff.handoff_id);
      const pending = command({ session_id: page.session_id, handoff_id: handoff.handoff_id, operation: 'wait_for_user' });
      const human = action => command({ ...handoff, operation: 'human_control_execute', action: { ...action, page_id: page.page_id } }, scope, true);
      async function fill(label, value) {
        const view = await human({ operation: 'observe' });
        const node = view.result.controls.find(item => item.label === label);
        assert.ok(node);
        return human({ operation: 'fill', node_id: node.node_id, revision: view.result.revision, value });
      }
      assert.equal((await fill('Account', 'public-fixture')).ok, true);
      assert.equal((await fill('Password', 'user-only-secret')).ok, true);
      const view = await human({ operation: 'observe' });
      assert.ok(!JSON.stringify(view).includes('user-only-secret'));
      const submit = view.result.controls.find(item => item.label === 'Sign in');
      assert.equal((await human({ operation: 'click', node_id: submit.node_id, revision: view.result.revision })).ok, true);
      // A subsequent page operation waits for the login navigation on this same context.
      assert.equal((await human({ operation: 'navigate', url: `http://127.0.0.1:${server.address().port}/private` })).ok, true);
      const returned = await command({ ...handoff, operation: 'human_control_finish' }, scope, true);
      const resumed = await pending;
      assert.deepEqual(resumed, returned);
      assert.equal(resumed.result.authentication_verified, false);
      assert.equal(resumed.result.next_action, 'observe');
      const content = await command({ ...page, operation: 'observe' });
      assert.match(content.result.text, /Authenticated fixture content/);
      const anotherAccount = await command({ operation: 'create', url: `http://127.0.0.1:${server.address().port}/private` });
      const isolated = await command({ session_id: anotherAccount.result.session_id, page_id: anotherAccount.result.page_id, operation: 'observe' });
      assert.match(isolated.result.text, /Not signed in/);
    });
    const earlyCancelId = randomUUID();
    await rpc(endpoint, { operation: 'cancel_operation', request_id: earlyCancelId }, 2000);
    const prevented = await rpc(endpoint, { operation: 'create' }, 10000, earlyCancelId);
    assert.equal(prevented.error.code, 'browser_operation_cancelled');
    assert.equal(prevented.error.details.executed, false);
    assert.equal(prevented.error.details.outcome_unknown, undefined);
    const after = await command({ ...ids, operation: 'observe' });
    assert.equal(after.ok, true);
    assert.equal(JSON.parse(fs.readFileSync(path.join(root, scope, 'endpoint.json'), 'utf8')).pid, endpoint.pid);
    const otherScope = await command({ ...ids, operation: 'observe' }, 'e'.repeat(64));
    assert.equal(otherScope.error.code, 'session_lost');
    const before = fs.readFileSync(path.join(root, scope, 'endpoint.json'), 'utf8');
    assert.equal((await rpc(endpoint, { operation: 'ping' })).ok, true);
    assert.equal(fs.readFileSync(path.join(root, scope, 'endpoint.json'), 'utf8'), before);
    await command({ session_id: ids.session_id, operation: 'close' });
    const cancellable = await command({ operation: 'create' });
    assert.equal(cancellable.ok, true);
    const requestId = randomUUID();
    const navigation = rpc(endpoint, { operation: 'navigate', session_id: cancellable.result.session_id,
      page_id: cancellable.result.page_id, url: `http://127.0.0.1:${server.address().port}/hang` }, 10000, requestId);
    await Promise.race([started, new Promise((_, reject) => {
      const timer = setTimeout(() => reject(new Error('Navigation did not start')), 5000); timer.unref();
    })]);
    const cancellation = await rpc(endpoint, { operation: 'cancel_operation', request_id: requestId }, 2000);
    assert.equal(cancellation.result.cancellation_requested, true);
    const cancelled = await navigation;
    assert.equal(cancelled.error.code, 'browser_operation_cancelled');
    assert.equal(cancelled.error.details.outcome_unknown, true);
    assert.equal((await command({ operation: 'observe', session_id: cancellable.result.session_id,
      page_id: cancellable.result.page_id })).error.code, 'session_lost');

    await t.test('SIGKILL of the actual browser daemon passively publishes the exact active handoff', async () => {
      const live = await command({ operation: 'create', url: `http://127.0.0.1:${server.address().port}` });
      assert.equal(live.ok, true);
      const binding = { key: 'f'.repeat(64), generation: randomUUID(), workspace_id: randomUUID() };
      const directory = path.join(workspaceRoot, binding.workspace_id, '.galaxyssi-browser-events');
      fs.mkdirSync(directory, { recursive: true });
      const begun = await command({ operation: 'human_control_begin', session_id: live.result.session_id,
        page_id: live.result.page_id, event_sink: binding }, scope, true);
      assert.equal(begun.ok, true, JSON.stringify(begun));
      const aad = Buffer.from(`galaxyssi-browser-handoff-event:v1:${binding.key}:${binding.generation}`);
      const file = path.join(directory, `${createHash('sha256').update(aad).digest('hex')}.enc`);
      let watcher;
      const observed = new Promise((resolve, reject) => {
        const timeout = setTimeout(() => { watcher.close(); reject(new Error('No passive daemon exit event')); }, 10_000);
        watcher = fs.watch(directory, (_, name) => {
          if (name === path.basename(file) && fs.existsSync(file)) { clearTimeout(timeout); watcher.close(); resolve(); }
        });
      });
      process.kill(endpoint.pid, 'SIGKILL');
      await observed;
      const bytes = fs.readFileSync(file);
      const key = createHmac('sha256', Buffer.from(hostToken)).update(aad).digest();
      const cipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(1, 13));
      cipher.setAAD(aad); cipher.setAuthTag(bytes.subarray(-16));
      const event = JSON.parse(Buffer.concat([cipher.update(bytes.subarray(13, -16)), cipher.final()]));
      key.fill(0); bytes.fill(0);
      assert.deepEqual(event, { code: 'session_lost', session_id: live.result.session_id,
        page_id: live.result.page_id, handoff_id: begun.result.handoff_id });
      // There was no readiness request between the kill and the file notification.
      const lost = await command({ operation: 'observe', session_id: live.result.session_id, page_id: live.result.page_id });
      assert.equal(lost.error.code, 'session_lost');
      assert.equal(JSON.parse(fs.readFileSync(path.join(root, scope, 'endpoint.json'))).pid, endpoint.pid);
    });
  });
