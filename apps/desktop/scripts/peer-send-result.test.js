const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../src/renderer/workspace.js"), "utf8");
const start = source.indexOf("function requirePeerSendSuccess(result) {");
const end = source.indexOf("\nasync function sendTask()", start);
assert.ok(start >= 0 && end > start);
const locale = JSON.parse(fs.readFileSync(path.join(__dirname, "../src/renderer/locales/zh-CN.json"), "utf8"));
const context = vm.createContext({ t: (key) => locale[key] || key });
vm.runInContext(source.slice(start, end), context);
const requireSuccess = context.requirePeerSendSuccess;

test("keeps successful peer messages unchanged", () => {
  const result = { ok: true, message: { message_id: "test-id" } };
  assert.equal(requireSuccess(result), result);
});

test("localizes broker failure without an Electron IPC exception prefix", () => {
  const message = "Message server is busy or unavailable. Wait for reconnection and send again.";
  assert.throws(() => requireSuccess({ ok: false, code: "mqtt_not_connected", message }),
    (error) => error.message === locale[message] && !error.message.includes("remote method"));
});

test("rejects empty or failed results instead of clearing the draft as sent", () => {
  for (const result of [null, {}, { ok: false }, { ok: false, peer_message: { delivery_status: "failed" } }]) {
    assert.throws(() => requireSuccess(result));
  }
});

test("both text and voice sends validate the structured result", () => {
  assert.equal((source.match(/requirePeerSendSuccess\(result\);/g) || []).length, 2);
});

test("offline text and attachment send restores the composer without adding a sent message", async () => {
  const sendStart = source.indexOf("async function sendTask() {");
  const nextFunction = /\n(?:async )?function /.exec(source.slice(sendStart + 1));
  assert.ok(nextFunction);
  const message = "Message server is busy or unavailable. Wait for reconnection and send again.";
  const state = {
    activePeerRouteId: "test-phone", peerSendPending: false,
    attachments: ["test-image.png"], attachmentDetails: new Map(), peerMessages: []
  };
  const elements = { prompt: { value: "unsent text" } };
  const notices = [];
  let releases = 0;
  const sendContext = vm.createContext({
    state, elements, requirePeerSendSuccess: requireSuccess,
    t: (key) => locale[key] || key,
    window: { galaxyssi: { sendPeerMessage: async () => ({ ok: false, message }) } },
    renderAttachmentTray() {}, updateSendState() {},
    renderHistory() {}, renderPeerConversation() {},
    releaseStagedAttachments() { releases += 1; },
    showToast(text) { notices.push(text); }
  });
  vm.runInContext(source.slice(sendStart, sendStart + 1 + nextFunction.index), sendContext);
  await sendContext.sendTask();
  assert.equal(elements.prompt.value, "unsent text");
  assert.deepEqual(Array.from(state.attachments), ["test-image.png"]);
  assert.equal(state.peerMessages.length, 0);
  assert.equal(state.peerSendPending, false);
  assert.equal(releases, 0);
  assert.ok(notices[0].includes(locale[message]));
});
