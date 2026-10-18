const { test } = require("node:test");
const assert = require("node:assert/strict");
const { createReminderNotifications } = require("../src/peer_reminder_notifications");

function fixture(focused = false) {
  const notices = [];
  class Notification {
    static isSupported() { return true; }
    constructor(options) { this.options = options; notices.push(this); }
    on() {}
    show() { this.shown = true; }
    close() { this.closed = true; }
  }
  const locale = require("../src/renderer/locales/zh-CN.json");
  const update = createReminderNotifications({ Notification, getWindow: () => ({ isFocused: () => focused }),
    translate: key => locale[key] || key });
  const value = { id: "ab123456-1234-1234-1234-123456abcdef", status: "received", expires_at: Date.now() + 120000, language: "zh-Hans" };
  return { notices, update, value };
}
test("background reminder notifies once with generic text", () => {
  const { notices, update, value } = fixture();
  update(value); update(value);
  assert.equal(notices.length, 1);
  assert.equal(notices[0].options.body, "收到联系人提醒");
  assert.equal(notices[0].shown, true);
});
test("foreground panel does not create another system alert", () => {
  const { notices, update, value } = fixture(true);
  update(value); assert.equal(notices.length, 0);
});
test("mute and cancellation dismiss the system notification", () => {
  for (const status of ["muted", "cancelled", "acknowledged", "expired"]) {
    const { notices, update, value } = fixture();
    update(value); update({ ...value, status }); update(value);
    assert.equal(notices.length, 1);
    assert.equal(notices[0].closed, true);
  }
});
test("expired or unbounded requests never notify", () => {
  const { notices, update, value } = fixture();
  for (const expires_at of [Date.now() - 1, Date.now() + 900000, NaN, "later"]) update({ ...value, expires_at });
  assert.equal(notices.length, 0);
});
