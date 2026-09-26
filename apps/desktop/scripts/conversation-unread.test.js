const assert = require("node:assert/strict");
const test = require("node:test");
const { ConversationUnread, taskEvents, messageEvents } = require("../src/conversation_unread");
const task = (id, conversation = "a", status = "completed") => ({ task_id: id, conversation_id: conversation, status });
const message = (id, direction = "inbound") => ({ message_id: id, client_route_id: "phone", direction });

test("first install baselines history without lighting every old conversation", () => {
  const ledger = new ConversationUnread();
  ledger.observe("tasks", taskEvents([task("old")]));
  assert.equal(ledger.has("agent:a"), false);
  ledger.observe("tasks", taskEvents([task("old"), task("new")]));
  assert.equal(ledger.has("agent:a"), true);
});

test("live event before snapshot remains unread", () => {
  const ledger = new ConversationUnread();
  ledger.observe("tasks", taskEvents([task("live")]), false);
  ledger.observe("tasks", taskEvents([task("old"), task("live")]));
  assert.equal(ledger.pending.size, 1);
});

test("reconnect and duplicate delivery cannot relight a read answer", () => {
  const ledger = new ConversationUnread();
  const events = taskEvents([task("one")]);
  ledger.observe("tasks", events, false);
  ledger.read("agent:a", events);
  ledger.observe("tasks", events, false);
  ledger.observe("tasks", events);
  assert.equal(ledger.has("agent:a"), false);
});

test("read is scoped to displayed conversation and displayed reply", () => {
  const ledger = new ConversationUnread();
  ledger.observe("tasks", taskEvents([task("one"), task("two"), task("three", "b")]), false);
  ledger.read("agent:a", taskEvents([task("one")]));
  assert.equal(ledger.has("agent:a"), true);
  assert.equal(ledger.has("agent:b"), true);
  ledger.read("agent:a", taskEvents([task("two"), task("three", "b")]));
  assert.equal(ledger.has("agent:a"), false);
  assert.equal(ledger.has("agent:b"), true);
});

test("pending markers survive a restart and catch offline completion", () => {
  const ledger = new ConversationUnread();
  ledger.observe("tasks", []);
  ledger.observe("tasks", taskEvents([task("one")]), false);
  const restored = new ConversationUnread(JSON.parse(JSON.stringify(ledger.serialize())));
  restored.observe("tasks", taskEvents([task("two", "b")]));
  assert.equal(restored.has("agent:a"), true);
  assert.equal(restored.has("agent:b"), true);
});

test("only inbound contact messages and completed tasks produce dots", () => {
  assert.equal(taskEvents([task("running", "a", "running"), task("failed", "a", "failed")]).length, 0);
  assert.equal(messageEvents([message("out", "outbound")]).length, 0);
  const ledger = new ConversationUnread();
  ledger.observe("messages", messageEvents([message("in")]), false);
  assert.equal(ledger.has("device:phone"), true);
  assert.equal(ledger.has("agent:phone"), false);
});

test("malformed saved state is tolerated", () => {
  assert.doesNotThrow(() => new ConversationUnread(null));
  assert.doesNotThrow(() => new ConversationUnread({ pending: [null, 1, {}] }));
});

test("message identities are isolated by peer even when IDs match", () => {
  const ledger = new ConversationUnread();
  const first = message("same-id");
  const second = { ...first, client_route_id: "another-phone" };
  ledger.observe("messages", messageEvents([first, second]), false);
  ledger.read("device:phone", messageEvents([first]));
  assert.equal(ledger.has("device:phone"), false);
  assert.equal(ledger.has("device:another-phone"), true);
});
