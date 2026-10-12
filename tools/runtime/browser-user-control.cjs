'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { randomUUID, randomBytes, createHash, createHmac, createCipheriv } = require('node:crypto');
const { BrowserOperationError } = require('./browser-session-engine.cjs');

// Only the host RPC may register this sink. No page data or credentials enter the event.
function sessionEventSink(input, hostToken, workspaceRoot = '/workspace') {
  if (!input) return null;
  if (!/^[a-f0-9]{64}$/.test(hostToken || '') || !/^[a-f0-9]{64}$/.test(input.key || '') ||
      !/^[A-Za-z0-9_-]{1,80}$/.test(input.generation || '') ||
      !/^[a-f0-9-]{36}$/.test(input.workspace_id || '')) {
    throw new BrowserOperationError('browser_event_sink_invalid', 'The host event binding is invalid.', { executed: false });
  }
  const directory = path.join(workspaceRoot, input.workspace_id, '.galaxyssi-browser-events');
  // The App creates the directory before takeover; never create or follow a guest-supplied link.
  for (const entry of [workspaceRoot, path.dirname(directory), directory]) {
    const info = fs.lstatSync(entry);
    if (!info.isDirectory() || info.isSymbolicLink()) throw new BrowserOperationError('browser_event_sink_invalid',
      'The host event directory is unavailable.', { executed: false });
  }
  const aad = Buffer.from(`galaxyssi-browser-handoff-event:v1:${input.key}:${input.generation}`, 'utf8');
  const key = createHmac('sha256', Buffer.from(hostToken, 'utf8')).update(aad).digest();
  const file = path.join(directory, `${createHash('sha256').update(aad).digest('hex')}.enc`);
  let closed = false;
  return {
    publish(state) {
      if (closed || state.finished) return;
      const iv = randomBytes(12);
      const cipher = createCipheriv('aes-256-gcm', key, iv);
      cipher.setAAD(aad);
      const plain = Buffer.from(JSON.stringify({ code: 'session_lost', session_id: state.session_id,
        page_id: state.page_id, handoff_id: state.id }), 'utf8');
      let envelope;
      const temporary = `${file}.${randomUUID()}.tmp`;
      try {
        envelope = Buffer.concat([Buffer.from([1]), iv, cipher.update(plain), cipher.final(), cipher.getAuthTag()]);
        const fd = fs.openSync(temporary, 'wx', 0o600);
        try { fs.writeFileSync(fd, envelope); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
        fs.renameSync(temporary, file);
        if (process.platform !== 'win32') {
          const directoryFd = fs.openSync(directory, 'r');
          try { fs.fsyncSync(directoryFd); } finally { fs.closeSync(directoryFd); }
        }
      } finally {
        plain.fill(0); envelope?.fill(0);
        try { fs.unlinkSync(temporary); } catch {}
        this.close();
      }
    },
    close() { closed = true; key.fill(0); }
  };
}

/** Host capabilities stay in this process; completion is a wakeup, not evidence of login. */
class BrowserUserControl {
  constructor(engine, createEventSink = () => null) {
    this.engine = engine;
    this.createEventSink = createEventSink;
    this.sessions = new Map();
    this.closed = false;
    this.unsubscribe = engine.subscribeSessionLoss?.(id => this.lost(id));
  }

  lost(id) {
    const state = this.sessions.get(id);
    if (!state) return;
    try { if (!state.finished) state.eventSink?.publish(state); } catch { /* A host observation can still reconcile the lost session. */ }
    state.eventSink?.close();
    state.token = null;
    for (const waiter of [...state.waiters]) waiter.reject(new BrowserOperationError('session_lost',
      'The browser session was lost during user control. Inspect external state before repeating an action.',
      { executed: false, goal_terminal: false }));
    this.sessions.delete(id);
  }

  invalid() {
    return new BrowserOperationError('browser_user_handoff_invalid',
      'Choose the current user handoff for this browser session.', { executed: false, goal_terminal: false });
  }

  publicState(state) {
    return { session_id: state.session_id, page_id: state.page_id, handoff_id: state.id,
      control_owner: state.finished ? 'agent' : 'user', next_action: state.finished ? 'observe' : 'wait_for_user',
      authentication_verified: false, business_success_verified: false };
  }

  current(input) {
    if (this.engine.isSessionLive?.(input.session_id) === false) throw new BrowserOperationError('session_lost',
      'The browser session is no longer live. Inspect external state before repeating an action.',
      { executed: false, goal_terminal: false });
    const state = this.sessions.get(input.session_id);
    if (!state || state.id !== input.handoff_id) throw this.invalid();
    return state;
  }

  async executeHost(input, signal) {
    if (this.closed) throw new BrowserOperationError('browser_closed', 'Browser service is stopping.');
    if (input.operation === 'human_control_begin') {
      const eventSink = this.createEventSink(input.event_sink);
      let lease;
      try { lease = await this.engine.beginHumanControl(input, signal); }
      catch (error) { eventSink?.close(); throw error; }
      if (this.closed) {
        eventSink?.close();
        throw new BrowserOperationError('browser_closed', 'Browser service stopped during user takeover.');
      }
      if (this.engine.isSessionLive?.(lease.session_id) === false) {
        eventSink?.close();
        throw new BrowserOperationError('session_lost',
          'The browser session was lost during user takeover.', { executed: false, goal_terminal: false });
      }
      const state = { id: randomUUID(), session_id: lease.session_id, page_id: lease.page_id,
        token: lease.control_token, finished: false, waiters: new Set(), eventSink };
      this.sessions.get(state.session_id)?.eventSink?.close();
      this.sessions.set(state.session_id, state);
      await state.eventSink?.arm?.(state);
      if (this.closed || this.sessions.get(state.session_id) !== state) throw new BrowserOperationError('session_lost',
        'The browser session was lost while exit monitoring was being confirmed.', { goal_terminal: false });
      return this.publicState(state);
    }
    if (input.operation === 'human_control_state' && input.handoff_id === undefined) {
      const state = this.sessions.get(input.session_id);
      if (!state) throw this.invalid();
      await this.attachEventSink(state, input);
      return this.publicState(state);
    }
    const state = this.current(input);
    if (input.operation === 'human_control_state') await this.attachEventSink(state, input);
    if (input.operation === 'human_control_state') return this.publicState(state);
    if (input.operation === 'human_control_finish') {
      if (state.finished) return this.publicState(state);
      await this.engine.finishHumanControl(input, state.token, signal);
      state.token = null;
      state.finished = true;
      state.eventSink?.close();
      try { await state.eventSink?.drained?.(); }
      catch (error) {
        for (const waiter of [...state.waiters]) waiter.reject(error);
        throw error;
      }
      for (const waiter of [...state.waiters]) waiter.resolve(this.publicState(state));
      return this.publicState(state);
    }
    if (state.finished) throw this.invalid();
    if (input.operation !== 'human_control_execute' || !input.action ||
        typeof input.action !== 'object' || Array.isArray(input.action)) throw this.invalid();
    // The envelope, not a nested page request, owns the account and session binding.
    if (input.action.session_id !== undefined && input.action.session_id !== state.session_id) throw this.invalid();
    return this.engine.executeHuman({ ...input.action, session_id: state.session_id }, state.token, signal);
  }

  wait(input, signal) {
    if (this.closed) return Promise.reject(new BrowserOperationError('browser_closed', 'Browser service is stopping.'));
    let state;
    try { state = this.current(input); } catch (error) { return Promise.reject(error); }
    if (signal?.aborted) return Promise.reject(new BrowserOperationError('browser_operation_cancelled',
      'Browser control observation was cancelled.', { executed: false }));
    if (state.finished) return Promise.resolve(this.publicState(state));
    return new Promise((resolve, reject) => {
      const cleanup = () => { state.waiters.delete(waiter); signal?.removeEventListener('abort', abort); };
      const waiter = {
        resolve: value => { cleanup(); resolve(value); },
        reject: error => { cleanup(); reject(error); }
      };
      const abort = () => waiter.reject(new BrowserOperationError('browser_operation_cancelled',
        'Browser control observation was cancelled.', { executed: false }));
      state.waiters.add(waiter);
      signal?.addEventListener('abort', abort, { once: true });
    });
  }

  stateForModel(sessionId) {
    const state = this.sessions.get(sessionId);
    return state ? this.publicState(state) : {};
  }

  async attachEventSink(state, input) {
    if (!input.event_sink || state.finished) return;
    const next = this.createEventSink(input.event_sink);
    try { await next?.arm?.(state); } catch (error) { next?.close(); throw error; }
    if (this.closed || this.sessions.get(state.session_id) !== state || state.finished) {
      next?.close();
      throw new BrowserOperationError('session_lost',
        'The browser handoff changed while exit monitoring was being confirmed.', { goal_terminal: false });
    }
    state.eventSink?.close();
    state.eventSink = next;
  }

  close() {
    this.closed = true;
    this.unsubscribe?.();
    for (const state of this.sessions.values()) {
      try { if (!state.finished) state.eventSink?.publish(state); } catch {}
      state.eventSink?.close();
      state.token = null;
      for (const waiter of [...state.waiters]) waiter.reject(new BrowserOperationError('session_lost',
        'Browser control service stopped. Inspect external state before repeating an action.',
        { executed: false, goal_terminal: false }));
    }
    this.sessions.clear();
  }
}

module.exports = { BrowserUserControl, sessionEventSink };
