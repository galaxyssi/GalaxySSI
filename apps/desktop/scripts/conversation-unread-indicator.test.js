const assert = require("node:assert/strict");
const test = require("node:test");
const { createConversationUnreadIndicator } = require("../src/conversation_unread_indicator");
const { badgeLabel, BADGE_SCALES } = require("../src/conversation_unread");
const png = BADGE_SCALES.map(scaleFactor => ({ scaleFactor, dataURL: `data:image/png;base64,test-${16 * scaleFactor}` }));

function fixture(platform = "win32") {
  const calls = [];
  let window = { isDestroyed: () => false, setOverlayIcon: (...args) => calls.push(args) };
  const nativeImage = {
    createFromDataURL: (url) => ({ getSize: () => ({ width: Number(url.split("-").at(-1)), height: Number(url.split("-").at(-1)) }), isEmpty: () => false }),
    createEmpty: () => ({ representations: [], getSize: () => ({ width: 16, height: 16 }),
      addRepresentation(rep) { this.representations.push(rep); } })
  };
  return { calls, replace: (next) => { window = next; }, indicator:
    createConversationUnreadIndicator({ getWindow: () => window, nativeImage, platform }) };
}

test("unread produces a visible taskbar dot without showing or focusing the window", () => {
  const { indicator, calls } = fixture();
  assert.equal(indicator.update(3, png), true);
  const image = calls[0][0];
  assert.deepEqual(image.getSize(), { width: 16, height: 16 });
  assert.deepEqual(image.representations.map(rep => rep.scaleFactor), BADGE_SCALES);
  assert.equal(calls[0][1], "3 unread messages");
});

test("deduplicates repeated updates and clears only when the ledger becomes empty", () => {
  const { indicator, calls } = fixture();
  indicator.update(1, png);
  indicator.update(1, png);
  assert.equal(calls.length, 1);
  indicator.update(2, png);
  assert.equal(calls[1][1], "2 unread messages");
  indicator.update(0);
  assert.deepEqual(calls[2], [null, ""]);
});

test("ignores untrusted payloads and unavailable windows", () => {
  const f = fixture();
  for (const input of [null, {}, true, -1, 1.5, Infinity, "1"]) assert.equal(f.indicator.update(input, png), false);
  for (const input of [undefined, "https://example.com", "data:image/png;base64," + "x".repeat(16384)]) {
    assert.equal(f.indicator.update(1, input), false);
  }
  assert.equal(f.indicator.update(1, png.slice(1)), false);
  assert.equal(f.indicator.update(1, png.map(rep => ({ ...rep, scaleFactor: 1 }))), false);
  assert.equal(f.indicator.update(1, png.map(rep => ({ ...rep, dataURL: "data:image/png;base64,test-999" }))), false);
  f.replace({ isDestroyed: () => true });
  assert.equal(f.indicator.update(1, png), false);
  f.replace(null);
  assert.equal(f.indicator.update(1, png), false);
  assert.equal(f.calls.length, 0);
});

test("reapplies state after window recreation", () => {
  const f = fixture();
  f.indicator.update(1, png);
  const calls = [];
  f.replace({ isDestroyed: () => false, setOverlayIcon: (...args) => calls.push(args) });
  f.indicator.update(1, png);
  assert.equal(calls.length, 1);
});

test("does not call the Windows API on other platforms", () => {
  const f = fixture("linux");
  assert.equal(f.indicator.update(1), true);
  assert.equal(f.calls.length, 0);
});

test("failed native updates can be retried", () => {
  const f = fixture();
  let attempts = 0;
  f.replace({ isDestroyed: () => false, setOverlayIcon: () => {
    if (++attempts === 1) throw new Error("temporary failure");
  } });
  assert.throws(() => f.indicator.update(1, png), /temporary failure/);
  assert.equal(f.indicator.update(1, png), true);
  assert.equal(attempts, 2);
});

test("badge caps display at 99+ while keeping the true count", () => {
  assert.equal(badgeLabel(1), "1");
  assert.equal(badgeLabel(99), "99");
  assert.equal(badgeLabel(100), "99+");
  const f = fixture();
  f.indicator.update(100, png);
  assert.equal(f.calls[0][1], "100 unread messages");
});

test("Windows native delivery bypasses Electron's fixed 16px overlay conversion", async () => {
  const window = { isDestroyed: () => false,
    setOverlayIcon() { throw new Error("Must not use Electron's resizer"); } };
  const counts = [];
  const indicator = createConversationUnreadIndicator({ getWindow: () => window, platform: "win32",
    setNativeOverlay: async (target, count) => { assert.equal(target, window); counts.push(count); return true; } });
  assert.equal(await indicator.update(12), true);
  assert.equal(await indicator.update(12), true);
  assert.equal(await indicator.update(0), true);
  assert.deepEqual(counts, [12, 0]);
});

test("native helper failure permits a retry", async () => {
  let attempts = 0;
  const window = { isDestroyed: () => false };
  const indicator = createConversationUnreadIndicator({ getWindow: () => window, platform: "win32",
    setNativeOverlay: async () => { if (++attempts === 1) throw new Error("failed"); return true; } });
  await assert.rejects(indicator.update(1), /failed/);
  assert.equal(await indicator.update(1), true);
});
