'use strict';

const { BrowserOperationError } = require('./browser-session-engine.cjs');

// Metadata only: never retain form values, DOM, cookies or exception messages.
class BrowserOperationReceipts {
  constructor({ now = Date.now, ttl = 600000, capacity = 1024 } = {}) {
    this.now = now;
    this.ttl = ttl;
    this.capacity = capacity;
    this.records = new Map();
  }

  prune() {
    const completed = [];
    for (const [id, record] of this.records) {
      if (record.state === 'running') continue;
      if (this.now() - record.finished_at_ms >= this.ttl) this.records.delete(id);
      else completed.push(id);
    }
    for (const id of completed.slice(0, Math.max(0, completed.length - this.capacity))) this.records.delete(id);
  }

  begin(id, input) {
    this.prune();
    if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,160}$/.test(id)) {
      throw new BrowserOperationError('invalid_browser_request_id', 'Provide a valid browser operation request ID.', { executed: false });
    }
    if (this.records.has(id)) throw new BrowserOperationError('browser_request_id_reused',
      'This request was already dispatched. Query operation_status, then observe the page before deciding what to do.',
      { request_id: id, outcome_unknown: true, repeated_dispatch: false });
    this.records.set(id, { request_id: id, operation: input.operation, state: 'running',
      session_id: input.session_id || null, page_id: input.page_id || null, started_at_ms: this.now() });
  }

  finish(id, envelope) {
    const record = this.records.get(id);
    if (!record || record.state !== 'running') return;
    record.state = envelope.ok ? 'completed' : 'failed';
    record.finished_at_ms = this.now();
    record.outcome_unknown = !envelope.ok && envelope.error?.details?.executed !== false &&
      envelope.error?.details?.outcome_unknown !== false;
    record.executed = envelope.ok ? true : envelope.error?.details?.executed === false ? false : null;
    if (!envelope.ok) record.error_code = envelope.error?.code || 'browser_service_failed';
    if (envelope.ok) {
      record.session_id = envelope.result?.session_id || record.session_id;
      record.page_id = envelope.result?.page_id || record.page_id;
    }
    this.prune();
  }

  status(id) {
    if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,160}$/.test(id)) {
      throw new BrowserOperationError('invalid_browser_request_id', 'Provide the browser operation request ID.', { executed: false });
    }
    this.prune();
    const record = this.records.get(id);
    return { ...(record || { request_id: id, state: 'unknown', outcome_unknown: true }),
      business_success_verified: false, verification_required: true,
      next_action: record?.state === 'running' ? 'observe_or_wait' : 'observe',
      receipt_retention_ms: this.ttl,
      missing_receipt_means_not_executed: false };
  }
}

module.exports = { BrowserOperationReceipts };
