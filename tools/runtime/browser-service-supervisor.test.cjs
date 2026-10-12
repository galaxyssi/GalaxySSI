'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { EventEmitter, once, on } = require('node:events');
const { randomUUID, createHash, createHmac, createDecipheriv } = require('node:crypto');
const { BrowserServiceExitMonitor, BrowserServiceMonitorClient, supervisedEventSink, superviseService, PROTOCOL } =
  require('./browser-service-supervisor.cjs');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'galaxyssi-exit-monitor-'));
  const binding = { key: 'b'.repeat(64), generation: randomUUID(), workspace_id: randomUUID() };
  const directory = path.join(root, binding.workspace_id, '.galaxyssi-browser-events');
  fs.mkdirSync(directory, { recursive: true });
  const token = 'a'.repeat(64);
  const state = { session_id: 'public-session', page_id: 'public-page', handoff_id: 'public-handoff' };
  const aad = Buffer.from(`galaxyssi-browser-handoff-event:v1:${binding.key}:${binding.generation}`);
  const file = path.join(directory, `${createHash('sha256').update(aad).digest('hex')}.enc`);
  t.after(() => {
    assert.equal(path.dirname(fs.realpathSync(root)), fs.realpathSync(os.tmpdir()));
    fs.rmSync(root, { recursive: true, force: true });
  });
  function decode() {
    const bytes = fs.readFileSync(file);
    assert.equal(bytes[0], 1);
    assert.ok(!bytes.includes(Buffer.from(state.handoff_id)));
    const key = createHmac('sha256', Buffer.from(token)).update(aad).digest();
    const cipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(1, 13));
    cipher.setAAD(aad); cipher.setAuthTag(bytes.subarray(-16));
    try { return JSON.parse(Buffer.concat([cipher.update(bytes.subarray(13, -16)), cipher.final()])); }
    finally { key.fill(0); bytes.fill(0); }
  }
  return { root, binding, directory, token, state, file, decode };
}

async function nextProbe(child) {
  for await (const [message] of on(child, 'message', { signal: AbortSignal.timeout(10_000) })) {
    if (message.public_probe) return message;
  }
}

test('actual exit publishes an encrypted observation once and never a successful business outcome', t => {
  const f = fixture(t), monitor = new BrowserServiceExitMonitor(f.token, f.root);
  monitor.arm(randomUUID(), f.binding, f.state);
  assert.equal(fs.existsSync(f.file), false);
  monitor.exited();
  const bytes = fs.readFileSync(f.file);
  monitor.exited();
  assert.deepEqual(fs.readFileSync(f.file), bytes);
  assert.deepEqual(f.decode(), { code: 'session_lost', session_id: f.state.session_id,
    page_id: f.state.page_id, handoff_id: f.state.handoff_id });
  assert.equal(monitor.entries.size, 0);
  assert.equal(monitor.hostToken, null);
});

test('returned or replaced handoffs cannot be retired by a late old message', t => {
  const f = fixture(t), monitor = new BrowserServiceExitMonitor(f.token, f.root);
  const old = randomUUID(), current = randomUUID();
  monitor.arm(old, f.binding, f.state);
  monitor.arm(current, f.binding, f.state);
  monitor.disarm(old);
  assert.equal(monitor.entries.size, 1);
  monitor.disarm(current);
  monitor.exited();
  assert.equal(fs.existsSync(f.file), false);
});

test('different generations remain separately encrypted and stale close cannot retire a new generation', t => {
  const f = fixture(t), monitor = new BrowserServiceExitMonitor(f.token, f.root);
  const old = randomUUID(), current = randomUUID();
  monitor.arm(old, f.binding, f.state);
  monitor.arm(current, { ...f.binding, generation: 'new-generation' }, { ...f.state, handoff_id: 'new-handoff' });
  monitor.disarm(old); monitor.exited();
  assert.equal(fs.existsSync(f.file), false);
  assert.equal(fs.readdirSync(f.directory).length, 1);
});

test('changed active handoff or workspace cannot reuse the original event binding', t => {
  const f = fixture(t), monitor = new BrowserServiceExitMonitor(f.token, f.root);
  monitor.arm(randomUUID(), f.binding, f.state);
  assert.throws(() => monitor.arm(randomUUID(), f.binding, { ...f.state, handoff_id: 'other' }),
    { code: 'browser_supervisor_binding_changed' });
  assert.throws(() => monitor.arm(randomUUID(), f.binding, { ...f.state, session_id: '' }),
    { code: 'browser_supervisor_binding_invalid' });
  monitor.exited();
  assert.equal(f.decode().handoff_id, f.state.handoff_id);
});

test('client requires a generation-bound acknowledgement rather than accepting send or timeout as success', async () => {
  const channel = new EventEmitter(); channel.connected = true;
  channel.send = (message, callback) => { callback(null); channel.last = message; };
  const client = new BrowserServiceMonitorClient(channel, 20);
  try {
    const pending = client.request('arm', { lease: randomUUID() });
    channel.emit('message', { protocol: PROTOCOL, request: 'unrelated', ok: true });
    await assert.rejects(pending, { code: 'browser_supervisor_unobserved' });
    assert.equal(client.pending.size, 0);
    const confirmed = client.request('disarm', { lease: randomUUID() });
    channel.emit('message', { protocol: PROTOCOL, request: channel.last.request, ok: true });
    await confirmed;
  } finally { client.close(); }
});

test('IPC disconnection is unknown monitoring state, not evidence that the child is dead', async () => {
  const channel = new EventEmitter(); channel.connected = true;
  channel.send = (_, callback) => callback(null);
  const client = new BrowserServiceMonitorClient(channel);
  const pending = client.request('arm', {});
  channel.emit('disconnect');
  await assert.rejects(pending, { code: 'browser_supervisor_unobserved' });
  assert.equal(channel.listenerCount('message'), 0);
});

test('wrapper retires exactly its own monitor and waits for retirement confirmation', async t => {
  const f = fixture(t), calls = [];
  let release;
  const monitor = { request(operation, payload) {
    calls.push({ operation, payload });
    return operation === 'arm' ? Promise.resolve() : new Promise(resolve => { release = resolve; });
  } };
  const sink = supervisedEventSink(f.binding, f.token, monitor, f.root);
  await sink.arm({ session_id: f.state.session_id, page_id: f.state.page_id, id: f.state.handoff_id });
  sink.close(); sink.close();
  let retired = false;
  const pending = sink.drained().then(() => { retired = true; });
  await Promise.resolve(); assert.equal(retired, false);
  release(); await pending;
  assert.equal(calls.length, 2);
  assert.equal(calls[0].payload.lease, calls[1].payload.lease);
  assert.equal(fs.existsSync(f.file), false);
});

test('real SIGKILL wakes from the independent parent with no RPC, heartbeat or model call', async t => {
  const f = fixture(t);
  const { child, monitor } = superviseService(process.execPath,
    [path.join(__dirname, '../testing/fixtures/browser-supervisor-child.cjs')], { env: { ...process.env,
      PUBLIC_MONITOR_MODULE: path.join(__dirname, 'browser-service-supervisor.cjs'),
      PUBLIC_MONITOR_BINDING: JSON.stringify(f.binding), PUBLIC_MONITOR_STATE: JSON.stringify(f.state),
      PUBLIC_MONITOR_LEASE: randomUUID() } }, f.token, f.root);
  t.after(() => { if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL'); });
  const message = await nextProbe(child);
  assert.equal(message.public_probe, 'armed');
  assert.equal(monitor.entries.size, 1);
  const exited = once(child, 'exit', { signal: AbortSignal.timeout(10_000) });
  child.kill('SIGKILL'); await exited;
  assert.deepEqual(f.decode(), { code: 'session_lost', ...f.state });
  assert.equal(monitor.entries.size, 0);
});

test('real child retirement precedes normal exit and cannot manufacture a later lost-session event', async t => {
  const f = fixture(t);
  const { child } = superviseService(process.execPath,
    [path.join(__dirname, '../testing/fixtures/browser-supervisor-child.cjs')], { env: { ...process.env,
      PUBLIC_MONITOR_MODULE: path.join(__dirname, 'browser-service-supervisor.cjs'),
      PUBLIC_MONITOR_BINDING: JSON.stringify(f.binding), PUBLIC_MONITOR_STATE: JSON.stringify(f.state),
      PUBLIC_MONITOR_LEASE: randomUUID() } }, f.token, f.root);
  t.after(() => { if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL'); });
  await nextProbe(child);
  const retired = nextProbe(child);
  const exited = once(child, 'exit', { signal: AbortSignal.timeout(10_000) });
  child.send({ public_probe: 'retire' }, () => {});
  assert.equal((await retired).public_probe, 'retired');
  await exited;
  assert.equal(fs.existsSync(f.file), false);
});
