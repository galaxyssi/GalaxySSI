'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { BrowserUserControl, sessionEventSink } = require('./browser-user-control.cjs');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createHash, createHmac, createDecipheriv } = require('node:crypto');

function fixture() {
  const actions = [];
  let sequence = 0;
  const engine = {
    async beginHumanControl(input) {
      return { session_id: input.session_id, page_id: input.page_id, control_token: `private-${++sequence}` };
    },
    async executeHuman(input, token) { actions.push({ input, token }); return { action_dispatched: true }; },
    async finishHumanControl(input, token) { actions.push({ input, token }); return {}; }
  };
  const control = new BrowserUserControl(engine);
  const begin = (session_id = 's') => control.executeHost({ operation: 'human_control_begin', session_id, page_id: 'p' });
  return { control, engine, actions, begin };
}

test('host begin keeps engine credentials in memory, never in public handoff state', async () => {
  const { control, begin } = fixture();
  const lease = await begin();
  assert.equal(lease.control_owner, 'user');
  assert.equal(lease.authentication_verified, false);
  assert.ok(!JSON.stringify(lease).includes('private-'));
  assert.ok(!JSON.stringify(control.stateForModel('s')).includes('control_token'));
});

test('completion wakes every subscriber once without a timer or a business success claim', async () => {
  const { control, begin } = fixture();
  const lease = await begin();
  const first = control.wait(lease);
  const second = control.wait(lease);
  assert.equal(control.sessions.get('s').waiters.size, 2);
  const finished = await control.executeHost({ ...lease, operation: 'human_control_finish' });
  assert.deepEqual(await first, finished);
  assert.deepEqual(await second, finished);
  assert.equal(control.sessions.get('s').waiters.size, 0);
  assert.equal(control.sessions.get('s').token, null);
  assert.equal(finished.next_action, 'observe');
  assert.equal(finished.authentication_verified, false);
});

test('a completion preceding subscription is observed immediately rather than lost', async () => {
  const { control, begin } = fixture();
  const lease = await begin();
  await control.executeHost({ ...lease, operation: 'human_control_finish' });
  assert.equal((await control.wait(lease)).control_owner, 'agent');
});

test('failed exit-monitor retirement rejects all waiting observers without repeating user release', async () => {
  const { control, begin, actions } = fixture();
  const failure = Object.assign(new Error('Public monitor acknowledgement failed.'), { code: 'browser_monitor_unavailable' });
  control.createEventSink = () => ({ close() {}, async drained() { throw failure; } });
  const lease = await begin();
  const first = assert.rejects(control.wait(lease), failure);
  const second = assert.rejects(control.wait(lease), failure);
  const finish = { ...lease, operation: 'human_control_finish' };
  await assert.rejects(control.executeHost(finish), failure);
  await first;
  await second;
  assert.equal(control.sessions.get('s').waiters.size, 0);
  assert.equal(control.sessions.get('s').token, null);
  assert.equal((await control.executeHost(finish)).next_action, 'observe');
  assert.equal(actions.length, 1);
});

test('session loss during monitor reattachment closes the new sink rather than retaining a stale binding', async () => {
  const { control, begin } = fixture();
  const lease = await begin();
  let acknowledge;
  let closed = 0;
  control.createEventSink = () => ({ arm: () => new Promise(resolve => { acknowledge = resolve; }),
    close() { closed++; } });
  const waiting = assert.rejects(control.wait(lease), { code: 'session_lost' });
  const attaching = control.executeHost({ ...lease, operation: 'human_control_state', event_sink: {} });
  control.lost('s');
  acknowledge();
  await assert.rejects(attaching, { code: 'session_lost' });
  await waiting;
  assert.equal(closed, 1);
  assert.equal(control.sessions.size, 0);
});

test('a cancelled observation unsubscribes without closing or releasing user control', async () => {
  const { control, begin, actions } = fixture();
  const lease = await begin();
  const abort = new AbortController();
  const pending = control.wait(lease, abort.signal);
  abort.abort();
  await assert.rejects(pending, { code: 'browser_operation_cancelled', details: { executed: false } });
  assert.equal(actions.length, 0);
  assert.equal(control.sessions.get('s').waiters.size, 0);
  assert.equal(control.stateForModel('s').control_owner, 'user');
});

test('pre-cancelled observations allocate no subscriber', async () => {
  const { control, begin } = fixture();
  const lease = await begin();
  const abort = new AbortController(); abort.abort();
  await assert.rejects(control.wait(lease, abort.signal), { code: 'browser_operation_cancelled' });
  assert.equal(control.sessions.get('s').waiters.size, 0);
});

test('session and current handoff identity cannot be substituted or replayed', async () => {
  const { control, begin } = fixture();
  const lease = await begin();
  const other = await begin('other');
  await assert.rejects(control.wait({ ...other, handoff_id: lease.handoff_id }), { code: 'browser_user_handoff_invalid' });
  await control.executeHost({ ...lease, operation: 'human_control_finish' });
  const next = await begin();
  assert.notEqual(next.handoff_id, lease.handoff_id);
  await assert.rejects(control.wait(lease), { code: 'browser_user_handoff_invalid' });
  await assert.rejects(control.executeHost({ ...lease, operation: 'human_control_finish' }), { code: 'browser_user_handoff_invalid' });
});

test('nested user actions cannot override the host-bound browser account', async () => {
  const { control, begin, actions } = fixture();
  const lease = await begin();
  await assert.rejects(control.executeHost({ ...lease, operation: 'human_control_execute',
    action: { operation: 'fill', session_id: 'other', value: 'private-value' } }), { code: 'browser_user_handoff_invalid' });
  assert.equal(actions.length, 0);
  await control.executeHost({ ...lease, operation: 'human_control_execute', action: { operation: 'observe', page_id: 'p' } });
  assert.equal(actions[0].input.session_id, 's');
  assert.equal(actions[0].token, 'private-1');
});

test('duplicate finish is idempotent and cannot repeat an engine operation', async () => {
  const { control, begin, actions } = fixture();
  const lease = await begin();
  const input = { ...lease, operation: 'human_control_finish' };
  assert.deepEqual(await control.executeHost(input), await control.executeHost(input));
  assert.equal(actions.length, 1);
  await assert.rejects(control.executeHost({ ...lease, operation: 'human_control_execute', action: { operation: 'click' } }),
    { code: 'browser_user_handoff_invalid' });
});

test('service death rejects pending observers instead of inventing a successful login', async () => {
  const { control, begin } = fixture();
  const lease = await begin();
  const pending = control.wait(lease);
  control.close();
  await assert.rejects(pending, { code: 'session_lost' });
  assert.equal(control.sessions.size, 0);
  await assert.rejects(control.wait(lease), { code: 'browser_closed' });
});

test('shutdown during takeover never retains an orphan host capability', async () => {
  const { control, engine, begin } = fixture();
  let complete;
  engine.beginHumanControl = () => new Promise(resolve => { complete = resolve; });
  const pending = begin();
  control.close();
  complete({ session_id: 's', page_id: 'p', control_token: 'private' });
  await assert.rejects(pending, { code: 'browser_closed' });
  assert.equal(control.sessions.size, 0);
});

test('session loss wakes only the affected account and never completes its login', async () => {
  const { control, begin } = fixture();
  const first = await begin();
  const second = await begin('other');
  const failed = assert.rejects(control.wait(first), { code: 'session_lost' });
  const pending = control.wait(second);
  control.lost(first.session_id);
  await failed;
  assert.equal(control.sessions.get('other').waiters.size, 1);
  assert.equal(control.stateForModel('other').control_owner, 'user');
  await control.executeHost({ ...second, operation: 'human_control_finish' });
  assert.equal((await pending).next_action, 'observe');
});

test('context loss between engine takeover and host acknowledgement cannot strand a waiter', async () => {
  const { control, engine, begin } = fixture();
  engine.isSessionLive = () => false;
  await assert.rejects(begin(), { code: 'session_lost' });
  assert.equal(control.sessions.size, 0);
});

test('host can recover an unobserved begin without acquiring another lease or returning its secret', async () => {
  const { control, begin } = fixture();
  const lease = await begin();
  const recovered = await control.executeHost({ operation: 'human_control_state', session_id: 's' });
  assert.deepEqual(recovered, lease);
  assert.ok(!JSON.stringify(recovered).includes('private-'));
});

test('a failed user release is not a completion event and cannot unblock the model', async () => {
  const { control, engine, begin } = fixture();
  const lease = await begin();
  engine.finishHumanControl = async () => { throw new Error('unobserved release'); };
  await assert.rejects(control.executeHost({ ...lease, operation: 'human_control_finish' }));
  assert.equal(control.stateForModel('s').control_owner, 'user');
  assert.equal(control.sessions.get('s').finished, false);
  assert.equal(control.sessions.get('s').token, 'private-1');
});

test('passive session loss atomically publishes one encrypted generation-bound event without a waiter', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'browser-events-'));
  const binding = { workspace_id: '12345678-1234-1234-1234-123456789abc', key: 'b'.repeat(64), generation: 'first' };
  const directory = path.join(root, binding.workspace_id, '.galaxyssi-browser-events');
  fs.mkdirSync(directory, { recursive: true });
  const capability = 'a'.repeat(64);
  const { engine } = fixture();
  const control = new BrowserUserControl(engine, input => sessionEventSink(input, capability, root));
  try {
    const lease = await control.executeHost({ operation: 'human_control_begin', session_id: 's', page_id: 'p', event_sink: binding });
    control.lost('s'); control.lost('s'); control.close();
    const aad = Buffer.from(`galaxyssi-browser-handoff-event:v1:${binding.key}:${binding.generation}`);
    const key = createHmac('sha256', Buffer.from(capability)).update(aad).digest();
    const files = fs.readdirSync(directory);
    assert.deepEqual(files, [`${createHash('sha256').update(aad).digest('hex')}.enc`]);
    const bytes = fs.readFileSync(path.join(directory, files[0]));
    assert.equal(bytes[0], 1);
    assert.ok(!bytes.includes(Buffer.from(lease.handoff_id)));
    const decipher = createDecipheriv('aes-256-gcm', key, bytes.subarray(1, 13));
    decipher.setAAD(aad); decipher.setAuthTag(bytes.subarray(-16));
    const value = JSON.parse(Buffer.concat([decipher.update(bytes.subarray(13, -16)), decipher.final()]).toString());
    assert.deepEqual(value, { code: 'session_lost', session_id: 's', page_id: 'p', handoff_id: lease.handoff_id });
    assert.equal(control.sessions.size, 0);
  } finally { control.close(); fs.rmSync(root, { recursive: true, force: true }); }
});

test('a failed event sink never acquires a user-control lease', async () => {
  const { engine } = fixture();
  let starts = 0;
  engine.beginHumanControl = async () => { starts++; throw new Error('unexpected'); };
  const control = new BrowserUserControl(engine, input => sessionEventSink(input, 'a'.repeat(64)));
  await assert.rejects(control.executeHost({ operation: 'human_control_begin', session_id: 's', page_id: 'p',
    event_sink: { key: 'b'.repeat(64), generation: '../../other', workspace_id: 'x' } }), { code: 'browser_event_sink_invalid' });
  assert.equal(starts, 0);
  control.close();
});

test('returned control closes its event sink without later reporting session loss', async () => {
  const { engine } = fixture();
  let publishes = 0, closes = 0;
  const control = new BrowserUserControl(engine, () => ({ publish() { publishes++; }, close() { closes++; } }));
  const lease = await control.executeHost({ operation: 'human_control_begin', session_id: 's', page_id: 'p' });
  await control.executeHost({ ...lease, operation: 'human_control_finish' });
  control.lost('s'); control.close();
  assert.equal(publishes, 0);
  assert.ok(closes >= 1);
});
