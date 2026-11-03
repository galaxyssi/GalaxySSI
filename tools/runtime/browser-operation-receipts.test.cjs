'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { BrowserOperationReceipts } = require('./browser-operation-receipts.cjs');

test('running and completed receipts are observations, not proof of business success', () => {
  const receipts = new BrowserOperationReceipts();
  receipts.begin('request-1', { operation: 'click', session_id: 's', page_id: 'p' });
  assert.equal(receipts.status('request-1').state, 'running');
  receipts.finish('request-1', { ok: true, result: { business_success_verified: true } });
  const status = receipts.status('request-1');
  assert.equal(status.state, 'completed');
  assert.equal(status.executed, true);
  assert.equal(status.business_success_verified, false);
  assert.equal(status.verification_required, true);
  assert.equal(status.next_action, 'observe');
});

test('request IDs cannot redispatch either running or completed operations', () => {
  const receipts = new BrowserOperationReceipts();
  receipts.begin('request-1', { operation: 'click' });
  const duplicate = () => receipts.begin('request-1', { operation: 'fill', value: 'changed-arguments' });
  assert.throws(duplicate, { code: 'browser_request_id_reused' });
  receipts.finish('request-1', { ok: true, result: {} });
  assert.throws(duplicate, { code: 'browser_request_id_reused' });
  assert.equal(receipts.status('request-1').operation, 'click');
});

test('failure receipts distinguish rejected dispatch from unknown side effects', () => {
  const receipts = new BrowserOperationReceipts();
  for (const [id, details, unknown] of [['rejected', { executed: false }, false],
    ['timeout', { outcome_unknown: true }, true], ['lost', {}, true]]) {
    receipts.begin(id, { operation: 'click' });
    receipts.finish(id, { ok: false, error: { code: id, details } });
    const status = receipts.status(id);
    assert.equal(status.state, 'failed');
    assert.equal(status.error_code, id);
    assert.equal(status.outcome_unknown, unknown);
    assert.equal(status.executed, id === 'rejected' ? false : null);
  }
});

test('create completion preserves live identifiers without storing sensitive result bodies', () => {
  const receipts = new BrowserOperationReceipts();
  receipts.begin('create-1', { operation: 'create', url: 'https://example.test/?secret=private-url' });
  receipts.finish('create-1', { ok: true, result: { session_id: 's', page_id: 'p',
    text: 'private-dom', cookies: 'private-cookie', control_token: 'private-token' } });
  assert.equal(receipts.status('create-1').session_id, 's');
  assert.equal(receipts.status('create-1').page_id, 'p');
  assert.ok(!JSON.stringify([...receipts.records]).includes('private-'));
});

test('error messages and form inputs never enter receipt storage', () => {
  const receipts = new BrowserOperationReceipts();
  receipts.begin('fill-1', { operation: 'fill', value: 'private-password', node_id: 'private-node' });
  receipts.finish('fill-1', { ok: false, error: { code: 'browser_action_timeout', message: 'private-password',
    details: { value: 'private-password', html: 'private-html' } } });
  assert.ok(!JSON.stringify([...receipts.records]).includes('private-'));
});

test('retention bounds completed metadata without evicting running operations', () => {
  let now = 0;
  const receipts = new BrowserOperationReceipts({ now: () => now, ttl: 10, capacity: 2 });
  receipts.begin('running', { operation: 'click' });
  for (const id of ['one', 'two', 'three']) {
    receipts.begin(id, { operation: 'observe' });
    receipts.finish(id, { ok: true, result: {} });
  }
  assert.equal(receipts.records.size, 3);
  assert.equal(receipts.status('one').state, 'unknown');
  now = 10;
  assert.equal(receipts.status('three').state, 'unknown');
  assert.equal(receipts.status('running').state, 'running');
  assert.throws(() => receipts.begin('running', { operation: 'click' }), { code: 'browser_request_id_reused' });
});

test('restart, eviction and unknown IDs never imply a safe retry', () => {
  const status = new BrowserOperationReceipts().status('previous-process');
  assert.equal(status.state, 'unknown');
  assert.equal(status.outcome_unknown, true);
  assert.equal(status.missing_receipt_means_not_executed, false);
  assert.equal(status.verification_required, true);
});

test('invalid operation IDs are rejected before recording or querying', () => {
  const receipts = new BrowserOperationReceipts();
  for (const id of ['', undefined, '../private', 'a'.repeat(161), {}]) {
    assert.throws(() => receipts.begin(id, { operation: 'click' }), { code: 'invalid_browser_request_id' });
    assert.throws(() => receipts.status(id), { code: 'invalid_browser_request_id' });
  }
  assert.equal(receipts.records.size, 0);
});
