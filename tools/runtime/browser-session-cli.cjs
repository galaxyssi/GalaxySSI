#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const net = require('node:net');
const { spawn } = require('node:child_process');
const { randomUUID, randomBytes, timingSafeEqual, createHash } = require('node:crypto');
const { BrowserSessions, BrowserOperationError } = require('./browser-session-engine.cjs');
const { BrowserUserControl } = require('./browser-user-control.cjs');
const { BrowserOperationReceipts } = require('./browser-operation-receipts.cjs');
const { BrowserServiceMonitorClient, supervisedEventSink, superviseService } = require('./browser-service-supervisor.cjs');

const MAX_REQUEST = 1024 * 1024;
const MAX_RESPONSE = 4 * 1024 * 1024;
const EVENT_WORKSPACE_ROOT = process.env.GALAXYSSI_BROWSER_EVENT_WORKSPACE_ROOT || '/workspace';
const DRIVER_VERSION = createHash('sha256').update(['browser-session-cli.cjs', 'browser-session-engine.cjs',
  'browser-user-control.cjs', 'browser-service-supervisor.cjs', 'browser-operation-receipts.cjs'].map(name => fs.readFileSync(path.join(__dirname, name))).reduce(
    (all, bytes) => Buffer.concat([all, bytes]), Buffer.alloc(0))).digest('hex');

function privateDirectory(directory) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const info = fs.lstatSync(directory);
  if (info.isSymbolicLink() || !info.isDirectory() ||
      (process.platform !== 'win32' && (info.uid !== process.getuid() || (info.mode & 0o077)))) {
    throw new BrowserOperationError('browser_state_not_private', 'Browser state directory must be private to the runtime account.');
  }
}

function equalToken(left, right) {
  return typeof left === 'string' && typeof right === 'string' && /^[a-f0-9]{64}$/.test(left) && /^[a-f0-9]{64}$/.test(right) &&
    timingSafeEqual(Buffer.from(left), Buffer.from(right));
}

function rpc(endpoint, input, timeout = 180000, requestId) {
  return new Promise((resolve, reject) => {
    let value = Buffer.alloc(0);
    let finished = false;
    const socket = net.createConnection(endpoint.socket);
    const finish = (error, result) => {
      if (finished) return;
      finished = true; socket.destroy();
      if (error) reject(error); else resolve(result);
    };
    socket.setTimeout(timeout, () => finish(new BrowserOperationError('browser_observation_timeout',
      'Browser response was not observed. The operation may still be running; inspect the live session before resubmitting.',
      { outcome_unknown: true, request_id: requestId })));
    socket.on('connect', () => socket.write(`${JSON.stringify({ token: endpoint.token, input,
      ...(requestId ? { request_id: requestId } : {}) })}\n`));
    socket.on('error', error => finish(error));
    socket.on('end', () => finish(new BrowserOperationError('browser_connection_lost',
      'Browser connection closed before the outcome was observed.', { outcome_unknown: true, request_id: requestId })));
    socket.on('data', chunk => {
      value = Buffer.concat([value, chunk]);
      if (value.length > MAX_RESPONSE) return finish(new BrowserOperationError('browser_response_too_large', 'Browser response exceeded its transport limit.'));
      const end = value.indexOf(10);
      if (end < 0) return;
      try { finish(null, JSON.parse(value.subarray(0, end).toString('utf8'))); }
      catch { finish(new BrowserOperationError('browser_response_invalid', 'Browser response could not be decoded.')); }
    });
  });
}

function safeFailure(error) {
  return { ok: false, error: { code: error instanceof BrowserOperationError ? error.code : 'browser_service_failed',
    message: error instanceof BrowserOperationError ? error.message : 'Browser service failed. Inspect runtime installation and the current session.',
    details: { ...(error instanceof BrowserOperationError ? error.details : {}), goal_terminal: false } } };
}

function consumeRequestEnvironment(environment) {
  const countValue = environment.GALAXYSSI_BROWSER_REQUEST_COUNT;
  let raw = environment.GALAXYSSI_BROWSER_REQUEST || '';
  try {
    if (countValue !== undefined) {
      if (!/^(?:[1-9]|[12][0-9]|3[01])$/.test(countValue)) {
        throw new BrowserOperationError('invalid_request_parts', 'Browser request part count is invalid.');
      }
      let encoded = '';
      for (let i = 0; i < Number(countValue); i++) {
        const part = environment[`GALAXYSSI_BROWSER_REQUEST_${i}`];
        if (typeof part !== 'string' || part.length > 4096 || !/^[A-Za-z0-9+/]*={0,2}$/.test(part)) {
          throw new BrowserOperationError('invalid_request_parts', 'Browser request part is missing or invalid.');
        }
        encoded += part;
      }
      raw = Buffer.from(encoded, 'base64').toString('utf8');
    }
    return raw;
  } finally {
    for (const key of Object.keys(environment)) {
      if (key === 'GALAXYSSI_BROWSER_REQUEST' || key.startsWith('GALAXYSSI_BROWSER_REQUEST_')) delete environment[key];
    }
  }
}

function consumeHostCapability(environment) {
  const value = environment.GALAXYSSI_BROWSER_HOST_TOKEN;
  delete environment.GALAXYSSI_BROWSER_HOST_TOKEN;
  if (value !== undefined && !/^[a-f0-9]{64}$/.test(value)) throw new BrowserOperationError('browser_host_capability_invalid',
    'Host browser capability is invalid.', { executed: false });
  return value;
}

function consumeOperationId(environment) {
  const id = environment.GALAXYSSI_BROWSER_OPERATION_ID;
  delete environment.GALAXYSSI_BROWSER_OPERATION_ID;
  if (id !== undefined && !/^[a-zA-Z0-9_-]{1,160}$/.test(id)) throw new BrowserOperationError(
    'invalid_browser_request_id', 'Browser operation request ID is invalid.', { executed: false });
  return id;
}

async function serve(directory, socketName, token, configuredHostToken) {
  const { chromium } = require('playwright');
  const engine = new BrowserSessions(chromium, { launchOptions: process.env.GALAXYSSI_BROWSER_EXECUTABLE
    ? { executablePath: process.env.GALAXYSSI_BROWSER_EXECUTABLE } : {} });
  const hostToken = configuredHostToken || randomBytes(32).toString('hex');
  const monitor = new BrowserServiceMonitorClient();
  const userControl = new BrowserUserControl(engine, input => supervisedEventSink(input, hostToken, monitor, EVENT_WORKSPACE_ROOT));
  const sockets = new Set();
  const operations = new Map();
  const receipts = new BrowserOperationReceipts();
  const cancelledRequests = new Map();
  let active = 0;
  let usedAt = Date.now();
  const server = net.createServer(socket => {
    sockets.add(socket); socket.on('close', () => sockets.delete(socket));
    socket.setTimeout(10000, () => socket.destroy());
    let bytes = Buffer.alloc(0);
    let received = false;
    socket.on('error', () => {});
    socket.on('data', async chunk => {
      if (received) return;
      bytes = Buffer.concat([bytes, chunk]);
      if (bytes.length > MAX_REQUEST) { received = true; socket.destroy(); return; }
      const end = bytes.indexOf(10);
      if (end < 0) return;
      received = true; socket.setTimeout(0);
      active++; usedAt = Date.now();
      try {
        const request = JSON.parse(bytes.subarray(0, end).toString('utf8'));
        bytes.fill(0); bytes = Buffer.alloc(0);
        const host = equalToken(request.token, hostToken);
        if (!host && !equalToken(request.token, token)) { socket.destroy(); return; }
        if (request.input?.operation?.startsWith('human_control_') && !host) {
          throw new BrowserOperationError('browser_host_control_required', 'User control is available only through the host channel.',
            { executed: false, goal_terminal: false });
        }
        for (const [id, expiry] of cancelledRequests) if (expiry < Date.now()) cancelledRequests.delete(id);
        if (request.input.operation === 'operation_status') {
          socket.end(`${JSON.stringify({ ok: true, result: receipts.status(request.input.request_id) })}\n`);
        } else if (request.input.operation === 'cancel_operation') {
          if (typeof request.input.request_id !== 'string' || request.input.request_id.length > 160 || !request.input.request_id) {
            throw new BrowserOperationError('invalid_cancellation_id', 'Provide the browser operation request ID.');
          }
          // The cancellation socket may arrive before the operation socket.
          cancelledRequests.set(request.input.request_id, Date.now() + 10 * 60000);
          const operation = operations.get(request.input.request_id);
          operation?.abort();
          socket.end(`${JSON.stringify({ ok: true, result: { cancellation_requested: !!operation, outcome_unknown: true } })}\n`);
        } else if (request.input.operation === 'service_shutdown') {
          userControl.close();
          await engine.close();
          socket.end(`${JSON.stringify({ ok: true, result: { stopped: true } })}\n`, () => void stop());
        } else {
          const controller = new AbortController();
          const requestId = request.request_id;
          if (requestId && cancelledRequests.has(requestId)) throw new BrowserOperationError('browser_operation_cancelled',
            'Browser operation was cancelled before dispatch.', { executed: false });
          if (requestId) receipts.begin(requestId, request.input);
          if (requestId) operations.set(requestId, controller);
          const waiting = request.input.operation === 'wait_for_user';
          const disconnected = () => controller.abort();
          if (waiting) socket.once('close', disconnected);
          try {
            let result;
            if (request.input.operation === 'ping') result = { alive: true, pid: process.pid, driver_version: DRIVER_VERSION };
            else if (request.input.operation.startsWith('human_control_')) result = await userControl.executeHost(request.input, controller.signal);
            else if (waiting) result = await userControl.wait(request.input, controller.signal);
            else result = await engine.execute(request.input, controller.signal);
            const envelope = { ok: true, result };
            if (requestId) receipts.finish(requestId, envelope);
            socket.end(`${JSON.stringify(envelope)}\n`);
          } catch (error) {
            if (error.code === 'browser_user_control_active') error.details = {
              ...error.details, ...userControl.stateForModel(request.input.session_id) };
            if (requestId) {
              const failure = safeFailure(error);
              receipts.finish(requestId, failure);
              failure.error.details.request_id = requestId;
              socket.end(`${JSON.stringify(failure)}\n`);
              return;
            }
            throw error;
          } finally {
            if (waiting) socket.off('close', disconnected);
            if (requestId) operations.delete(requestId);
          }
        }
      } catch (error) { socket.end(`${JSON.stringify(safeFailure(error))}\n`); }
      finally { active--; usedAt = Date.now(); }
    });
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(socketName, resolve); });
  if (process.platform !== 'win32') fs.chmodSync(socketName, 0o600);
  const endpoint = { socket: socketName, token, pid: process.pid, version: 2, driver_version: DRIVER_VERSION };
  const temporary = path.join(directory, `endpoint-${randomUUID()}.json`);
  fs.writeFileSync(temporary, JSON.stringify(endpoint), { mode: 0o600 });
  fs.renameSync(temporary, path.join(directory, 'endpoint.json'));
  let stopping = false;
  async function stop() {
    if (stopping) return;
    stopping = true; clearInterval(idle);
    userControl.close();
    server.close(); for (const socket of sockets) socket.destroy();
    await engine.close();
    try {
      const current = JSON.parse(fs.readFileSync(path.join(directory, 'endpoint.json'), 'utf8'));
      if (current.token === token) fs.unlinkSync(path.join(directory, 'endpoint.json'));
    } catch {}
    if (process.platform !== 'win32') { try { fs.unlinkSync(socketName); } catch {} }
    monitor.close();
    if (process.connected) process.disconnect();
  }
  // Release an abandoned browser, not the Agent goal or its checkpoints.
  const idle = setInterval(() => { if (!active && Date.now() - usedAt > 30 * 60000) void stop(); }, 30000);
  process.on('SIGTERM', () => void stop()); process.on('SIGINT', () => void stop());
}

async function existingEndpoint(directory, host = false, allowStaleShutdown = false, hostToken) {
  try {
    const file = path.join(directory, 'endpoint.json');
    const info = fs.lstatSync(file);
    if (!info.isFile() || info.isSymbolicLink() || info.size > 4096 ||
        (process.platform !== 'win32' && (info.mode & 0o077))) {
      throw new BrowserOperationError('browser_endpoint_invalid', 'The browser endpoint file is not a private regular file.');
    }
    const endpoint = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (typeof endpoint.socket !== 'string' || !/^[a-f0-9]{64}$/.test(endpoint.token)) {
      throw new BrowserOperationError('browser_endpoint_invalid', 'The browser endpoint is malformed.');
    }
    if (host) {
      if (!/^[a-f0-9]{64}$/.test(hostToken || '')) throw new BrowserOperationError('browser_host_capability_missing',
        'The App host capability is required for user browser control.', { executed: false });
      endpoint.token = hostToken;
    }
    const ping = await rpc(endpoint, { operation: 'ping' }, 1500);
    if (!ping.ok || !ping.result.alive) throw new BrowserOperationError('browser_readiness_unobserved', 'The existing browser has not confirmed readiness.');
    if (ping.result.driver_version !== DRIVER_VERSION && !allowStaleShutdown) throw new BrowserOperationError('browser_driver_changed',
      'A live browser uses a different driver. Inspect and explicitly close it before creating a replacement; do not repeat an uncertain submission.',
      { executed: false, outcome_unknown: true, goal_terminal: false });
    return endpoint;
  } catch (error) {
    if (['ENOENT', 'ECONNREFUSED'].includes(error.code)) return null;
    if (error instanceof BrowserOperationError) throw error;
    throw new BrowserOperationError('browser_readiness_unobserved', 'Cannot inspect the existing browser endpoint. Do not start another browser until its state is known.');
  }
}

async function startService(directory, hostToken) {
  const lockFile = path.join(directory, 'starting.json');
  const owner = { pid: process.pid, token: randomUUID() };
  try { fs.writeFileSync(lockFile, JSON.stringify(owner), { flag: 'wx', mode: 0o600 }); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    try {
      const previous = JSON.parse(fs.readFileSync(lockFile, 'utf8'));
      try { process.kill(previous.pid, 0); }
      catch (probe) { if (probe.code === 'ESRCH') { fs.unlinkSync(lockFile); return startService(directory, hostToken); } }
    } catch {}
    throw new BrowserOperationError('browser_start_pending', 'A browser startup is already in progress. Inspect readiness rather than launching another service.');
  }
  let preserveLock = false;
  try {
    const existing = await existingEndpoint(directory);
    if (existing) return existing;
    let socketName;
    if (process.platform === 'win32') socketName = `\\\\.\\pipe\\galaxyssi-browser-${randomUUID()}`;
    else {
      const socketRoot = path.join(os.tmpdir(), `galaxyssi-browser-${process.getuid()}`);
      privateDirectory(socketRoot);
      socketName = path.join(socketRoot, `${randomUUID()}.sock`);
    }
    const env = { ...process.env, GALAXYSSI_BROWSER_RPC_TOKEN: randomBytes(32).toString('hex') };
    if (hostToken) env.GALAXYSSI_BROWSER_HOST_TOKEN = hostToken;
    consumeRequestEnvironment(env);
    consumeOperationId(env);
    const child = spawn(process.execPath, [__filename, 'supervise', directory, socketName],
      { detached: true, stdio: 'ignore', windowsHide: true, env });
    let spawnError;
    child.on('error', error => { spawnError = error; }); child.unref();
    if (child.pid) fs.writeFileSync(lockFile, JSON.stringify({ ...owner, pid: child.pid }), { mode: 0o600 });
    for (let i = 0; i < 100; i++) {
      const ready = await existingEndpoint(directory);
      if (ready) return ready;
      if (spawnError || child.exitCode !== null) throw new BrowserOperationError('browser_start_failed',
        'Browser service did not start. Check that the browser-automation and node-js runtime packs are installed.');
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    preserveLock = true;
    throw new BrowserOperationError('browser_start_pending', 'Browser readiness has not been observed. Do not restart a live service solely because startup observation expired.');
  } finally {
    try {
      if (!preserveLock && JSON.parse(fs.readFileSync(lockFile, 'utf8')).token === owner.token) fs.unlinkSync(lockFile);
    } catch {}
  }
}

async function main() {
  if (process.argv[2] === 'supervise') {
    const token = process.env.GALAXYSSI_BROWSER_RPC_TOKEN;
    delete process.env.GALAXYSSI_BROWSER_RPC_TOKEN;
    if (!/^[a-f0-9]{64}$/.test(token || '')) throw new BrowserOperationError('invalid_service_token', 'Missing browser service capability.');
    const hostToken = consumeHostCapability(process.env) || randomBytes(32).toString('hex');
    const env = { ...process.env, GALAXYSSI_BROWSER_RPC_TOKEN: token, GALAXYSSI_BROWSER_HOST_TOKEN: hostToken };
    consumeRequestEnvironment(env);
    const { child } = superviseService(process.execPath, [__filename, 'serve', process.argv[3], process.argv[4]], { env }, hostToken, EVENT_WORKSPACE_ROOT);
    process.on('SIGTERM', () => child.kill('SIGTERM')); process.on('SIGINT', () => child.kill('SIGINT'));
    return;
  }
  if (process.argv[2] === 'serve') {
    const token = process.env.GALAXYSSI_BROWSER_RPC_TOKEN;
    delete process.env.GALAXYSSI_BROWSER_RPC_TOKEN;
    if (!/^[a-f0-9]{64}$/.test(token || '')) throw new BrowserOperationError('invalid_service_token', 'Missing browser service capability.');
    await serve(process.argv[3], process.argv[4], token, consumeHostCapability(process.env));
    return;
  }
  const host = process.argv[2] === 'host';
  const hostToken = consumeHostCapability(process.env);
  const scope = process.argv[host ? 3 : 2];
  if (!/^[a-f0-9]{64}$/.test(scope || '')) throw new BrowserOperationError('invalid_scope', 'Browser scope must be a host-bound SHA-256 identifier.');
  const raw = consumeRequestEnvironment(process.env);
  const requestId = consumeOperationId(process.env) || randomUUID();
  if (Buffer.byteLength(raw) > MAX_REQUEST) throw new BrowserOperationError('request_too_large', 'Browser operation exceeds its transport limit.');
  const input = JSON.parse(raw);
  const root = process.env.GALAXYSSI_BROWSER_STATE_ROOT || path.join(os.homedir(), '.local', 'state', 'galaxyssi-browser');
  privateDirectory(root);
  const directory = path.join(root, scope); privateDirectory(directory);
  let endpoint = await existingEndpoint(directory, host, input.operation === 'service_shutdown', hostToken);
  if (!endpoint) {
    if (host || input.operation !== 'create') throw new BrowserOperationError('session_lost',
      'The browser service is not live. Observe external state before repeating a prior submission; explicitly create a new session if needed.');
    endpoint = await startService(directory, hostToken);
  }
  // Explicit execution cancellation differs from losing an observation socket.
  const cancel = () => { void rpc(endpoint, { operation: 'cancel_operation', request_id: requestId }, 2000)
    .catch(() => {}).finally(() => { process.exitCode = 143; }); };
  process.once('SIGTERM', cancel); process.once('SIGINT', cancel);
  try {
    process.stdout.write(`${JSON.stringify(await rpc(endpoint, input, 180000, requestId))}\n`);
  } finally { process.off('SIGTERM', cancel); process.off('SIGINT', cancel); }
}

if (require.main === module) void main().catch(error => {
  process.stdout.write(`${JSON.stringify(safeFailure(error))}\n`); process.exitCode = 1;
});
module.exports = { rpc, equalToken, safeFailure, privateDirectory, consumeRequestEnvironment, consumeHostCapability,
  consumeOperationId, existingEndpoint, DRIVER_VERSION };
