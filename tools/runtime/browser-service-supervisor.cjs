'use strict';

const { randomUUID } = require('node:crypto');
const { spawn } = require('node:child_process');
const { BrowserOperationError } = require('./browser-session-engine.cjs');
const { sessionEventSink } = require('./browser-user-control.cjs');

const PROTOCOL = 'galaxyssi.browser.exit-monitor.v1';
const leasePattern = /^[a-f0-9-]{36}$/;
function failure(code = 'browser_supervisor_unobserved') {
  return new BrowserOperationError(code,
    'Browser exit monitoring was not confirmed. Inspect the existing handoff before retrying.',
    { outcome_unknown: true, goal_terminal: false });
}

/** The monitor owns no pages, model loop or business retry. Only actual child exit publishes loss. */
class BrowserServiceExitMonitor {
  constructor(hostToken, workspaceRoot = '/workspace') {
    this.hostToken = hostToken;
    this.workspaceRoot = workspaceRoot;
    this.entries = new Map();
    this.slots = new Map();
    this.stopped = false;
  }

  arm(lease, binding, state) {
    if (this.stopped || !leasePattern.test(lease || '') || !state ||
        ['session_id', 'page_id', 'handoff_id'].some(key => typeof state[key] !== 'string' ||
          !state[key] || state[key].length > 160)) throw failure('browser_supervisor_binding_invalid');
    const safe = { session_id: state.session_id, page_id: state.page_id, id: state.handoff_id, finished: false };
    const sink = sessionEventSink(binding, this.hostToken, this.workspaceRoot);
    if (!sink) throw failure('browser_supervisor_binding_invalid');
    const slot = `${binding.key}:${binding.generation}`;
    const previous = this.entries.get(this.slots.get(slot));
    if (this.entries.has(lease) || previous && (JSON.stringify(previous.state) !== JSON.stringify(safe) ||
        previous.binding.workspace_id !== binding.workspace_id)) {
      sink.close(); throw failure('browser_supervisor_binding_changed');
    }
    // A new authenticated attachment replaces only its exact binding; old close messages cannot retire it.
    if (previous) this.disarm(previous.lease);
    this.entries.set(lease, { lease, slot, sink, binding: { ...binding }, state: safe });
    this.slots.set(slot, lease);
  }

  disarm(lease) {
    const entry = this.entries.get(lease);
    if (!entry) return;
    this.entries.delete(lease);
    if (this.slots.get(entry.slot) === lease) this.slots.delete(entry.slot);
    entry.sink.close();
  }

  exited() {
    if (this.stopped) return;
    this.stopped = true;
    let failed = false;
    for (const entry of this.entries.values()) {
      try { entry.sink.publish(entry.state); } catch { failed = true; }
      finally { entry.sink.close(); }
    }
    this.entries.clear(); this.slots.clear(); this.hostToken = null;
    if (failed) throw failure('browser_supervisor_event_write_failed');
  }
}

class BrowserServiceMonitorClient {
  constructor(channel = process, timeoutMillis = 5000) {
    this.channel = channel;
    this.timeoutMillis = timeoutMillis;
    this.pending = new Map();
    this.closed = false;
    this.onMessage = message => {
      if (message?.protocol !== PROTOCOL) return;
      const pending = this.pending.get(message.request);
      if (!pending) return;
      this.pending.delete(message.request); clearTimeout(pending.timer);
      if (message.ok) pending.resolve(); else pending.reject(failure(message.code));
    };
    this.onDisconnect = () => this.close();
    channel.on('message', this.onMessage); channel.on('disconnect', this.onDisconnect);
  }

  request(operation, payload) {
    if (this.closed || !this.channel.connected || typeof this.channel.send !== 'function')
      return Promise.reject(failure());
    const request = randomUUID();
    return new Promise((resolve, reject) => {
      const finish = error => {
        const pending = this.pending.get(request);
        if (!pending) return;
        this.pending.delete(request); clearTimeout(pending.timer); reject(error);
      };
      const timer = setTimeout(() => finish(failure()), this.timeoutMillis);
      this.pending.set(request, { resolve, reject, timer });
      try {
        this.channel.send({ protocol: PROTOCOL, request, operation, ...payload }, error => {
          if (error) finish(failure());
        });
      } catch { finish(failure()); }
    });
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    this.channel.off('message', this.onMessage); this.channel.off('disconnect', this.onDisconnect);
    for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(failure()); }
    this.pending.clear();
  }
}

/** Retire is acknowledged before successful return; credentials/page bodies never cross this IPC. */
function supervisedEventSink(binding, hostToken, monitor, workspaceRoot = '/workspace') {
  const sink = sessionEventSink(binding, hostToken, workspaceRoot);
  if (!sink) return null;
  const lease = randomUUID();
  let closed = false;
  let retiring = Promise.resolve();
  return {
    async arm(state) {
      if (closed) throw failure();
      await monitor.request('arm', { lease, binding, state: {
        session_id: state.session_id, page_id: state.page_id, handoff_id: state.id } });
    },
    publish(state) { try { sink.publish(state); } finally { this.close(); } },
    close() {
      if (closed) return;
      closed = true; sink.close();
      retiring = monitor.request('disarm', { lease });
      // Shutdown/loss may not have a caller awaiting this acknowledgement.
      retiring.catch(() => {});
    },
    drained() { return retiring; }
  };
}

function superviseService(executable, args, options, hostToken, workspaceRoot = '/workspace') {
  const monitor = new BrowserServiceExitMonitor(hostToken, workspaceRoot);
  const child = spawn(executable, args, { ...options, detached: false, windowsHide: true,
    stdio: ['ignore', 'ignore', 'ignore', 'ipc'] });
  child.on('error', () => {});
  child.on('message', message => {
    if (message?.protocol !== PROTOCOL || !leasePattern.test(message.request || '')) return;
    let response;
    try {
      if (message.operation === 'arm') monitor.arm(message.lease, message.binding, message.state);
      else if (message.operation === 'disarm' && leasePattern.test(message.lease || '')) monitor.disarm(message.lease);
      else throw failure('browser_supervisor_binding_invalid');
      response = { ok: true };
    } catch (error) { response = { ok: false, code: error instanceof BrowserOperationError ? error.code : 'browser_supervisor_unobserved' }; }
    if (child.connected) child.send({ protocol: PROTOCOL, request: message.request, ...response }, () => {});
  });
  // Disconnect alone is not proof of process death. Keep the actual ChildProcess exit subscription.
  child.once('exit', () => { try { monitor.exited(); } catch { process.exitCode = 1; } });
  return { child, monitor };
}

module.exports = { BrowserServiceExitMonitor, BrowserServiceMonitorClient, supervisedEventSink, superviseService, PROTOCOL };
