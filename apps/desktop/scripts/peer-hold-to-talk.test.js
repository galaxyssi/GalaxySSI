const test = require("node:test");
const assert = require("node:assert/strict");

const holdToTalk = require("../src/peer_hold_to_talk");

test("uses the Android-equivalent upward cancel threshold", () => {
  assert.equal(holdToTalk.isCancelPending(300, 245), false);
  assert.equal(holdToTalk.isCancelPending(300, 244), true);
});

test("only sends recordings that are long enough and not cancelled", () => {
  assert.deepEqual(
    holdToTalk.completion({ durationMs: 799, sendRequested: true, cancelPending: false }),
    { send: false, reason: "too_short" }
  );
  assert.deepEqual(
    holdToTalk.completion({ durationMs: 800, sendRequested: true, cancelPending: false }),
    { send: true, reason: "send" }
  );
  assert.deepEqual(
    holdToTalk.completion({ durationMs: 2_000, sendRequested: true, cancelPending: true }),
    { send: false, reason: "cancelled" }
  );
});

test("formats the visible recording timer", () => {
  assert.equal(holdToTalk.formatElapsed(0), "00:00");
  assert.equal(holdToTalk.formatElapsed(65_900), "01:05");
});
