const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const confirmation = require("../src/renderer/conversation-confirmation");

function element() {
  return { isConnected: true, disabled: false, focused: 0, listeners: {},
    getClientRects: () => [1], focus() { this.focused++; },
    addEventListener(type, fn) { this.listeners[type] = fn; },
    emit(type, event = {}) { this.listeners[type]?.(event); } };
}
function dialogHost() {
  const previous = element(), fallback = element(), dialog = element();
  const confirmButton = element(), cancelButton = element(), message = {};
  const document = { activeElement: previous, hasFocus: () => true };
  dialog.showModal = () => { dialog.open = true; };
  dialog.close = (value) => { dialog.open = false; dialog.returnValue = value; dialog.emit("close"); };
  const api = confirmation.create({ document, dialog, message, confirmButton, cancelButton, fallbackFocus: () => fallback });
  return { api, previous, fallback, document, dialog, message, confirmButton, cancelButton };
}

for (const action of ["confirm", "cancel", "escape"]) test(`${action} closes the dialog and restores focus without a timer`, async () => {
  const h = dialogHost(), pending = h.api.ask("Delete test conversation?");
  assert.equal(h.cancelButton.focused, 1);
  assert.equal(h.message.textContent, "Delete test conversation?");
  if (action === "escape") {
    let prevented = false;
    h.dialog.emit("cancel", { preventDefault() { prevented = true; } });
    assert.equal(prevented, true);
  } else h[action === "confirm" ? "confirmButton" : "cancelButton"].emit("click");
  assert.equal(await pending, action === "confirm");
  assert.equal(h.previous.focused, 1);
  assert.equal(h.dialog.open, false);
});

test("repeated dialogs reset acceptance and reject duplicate confirmation requests", async () => {
  const h = dialogHost();
  const first = h.api.ask("First");
  assert.equal(await h.api.ask("Duplicate"), false);
  assert.equal(h.message.textContent, "First");
  h.confirmButton.emit("click"); assert.equal(await first, true);
  const next = h.api.ask("Next");
  assert.equal(h.dialog.returnValue, "");
  h.cancelButton.emit("click"); assert.equal(await next, false);
});

for (const reason of ["removed", "hidden", "disabled"]) test(`focus falls back when the trigger is ${reason}`, async () => {
  const h = dialogHost(), pending = h.api.ask("Delete");
  if (reason === "removed") h.previous.isConnected = false;
  if (reason === "hidden") h.previous.getClientRects = () => [];
  if (reason === "disabled") h.previous.disabled = true;
  h.cancelButton.emit("click"); await pending;
  assert.equal(h.fallback.focused, 1);
});

test("closing a background dialog does not steal window focus", async () => {
  const h = dialogHost(), pending = h.api.ask("Delete");
  h.document.hasFocus = () => false;
  h.confirmButton.emit("click"); assert.equal(await pending, true);
  assert.equal(h.previous.focused + h.fallback.focused, 0);
});

test("a focus restoration error cannot keep confirmation pending", async () => {
  const h = dialogHost(), pending = h.api.ask("Delete");
  h.previous.focus = () => { throw new Error("Detached focus target"); };
  h.confirmButton.emit("click"); assert.equal(await pending, true);
  const next = h.api.ask("Again");
  h.cancelButton.emit("click"); assert.equal(await next, false);
});

test("a modal opening failure releases the pending request", async () => {
  const h = dialogHost(), show = h.dialog.showModal;
  h.dialog.showModal = () => { throw new Error("Unavailable dialog"); };
  await assert.rejects(h.api.ask("Delete"), /Unavailable/);
  h.dialog.showModal = show;
  const next = h.api.ask("Retry"); h.cancelButton.emit("click");
  assert.equal(await next, false);
});

const source = fs.readFileSync(path.join(__dirname, "../src/renderer/workspace.js"), "utf8");
const start = source.indexOf("async function deleteConversation() {");
const end = source.indexOf("\nfunction updatePeerVoiceHoldUi", start);
assert.ok(start > 0 && end > start);
function deletionHost(overrides = {}) {
  const state = { currentConversationId: "current", deletingConversationIds: new Set(),
    selectedConversationIds: new Set(), pinnedConversationIds: new Set(["current", "other", "peer"]),
    hiddenEvolutionConversationIds: new Set(), activePeerRouteId: "", peerMessages: [],
    attachments: ["draft-image"], conversationDeletionPromise: null };
  const input = { value: "Unsent draft" }, calls = [], errors = [];
  const api = {
    deleteDesktopConversation: async (id) => { calls.push(id); return { deleted_task_ids: [id] }; },
    deletePeerConversation: async (id) => { calls.push(id); return { deleted_messages: 1 }; }, ...overrides
  };
  const context = vm.createContext({ state, document: { querySelector: () => ({ classList: { remove() {} } }) },
    window: { galaxyssi: api, GalaxySSIConversationConfirmation: { create: () => ({ ask: async () => true }) } },
    $: () => ({}), elements: { prompt: input }, conversationTasks: () => [1],
    unifiedConversationGroups: () => [{ id: "current", kind: "agent" }, { id: "other", kind: "agent" },
      { id: "peer", kind: "device" }], renderConversationSelectionBar() {}, renderHistory() {},
    persistPinnedConversations() {}, persistHiddenEvolutionConversations() {}, refreshTasks: async () => {},
    refreshPeerMessages: async () => {}, t: (s) => s, showToast: (s) => errors.push(s),
    newTask: () => { state.currentConversationId = "new"; input.value = ""; state.attachments = []; } });
  vm.runInContext(source.slice(start, end), context);
  return { state, input, api, calls, errors, context };
}

test("deleting another conversation preserves the active draft and attachments", async () => {
  const h = deletionHost(); await h.context.requestConversationDeletion(["other"], "Delete");
  assert.deepEqual(h.calls, ["other"]);
  assert.equal(h.state.currentConversationId, "current");
  assert.equal(h.input.value, "Unsent draft");
  assert.deepEqual(h.state.attachments, ["draft-image"]);
  assert.equal(h.state.conversationDeletionPromise, null);
});

test("deleting the active conversation opens a usable new conversation", async () => {
  const h = deletionHost(); await h.context.deleteConversation();
  assert.deepEqual(h.calls, ["current"]);
  assert.equal(h.state.currentConversationId, "new");
  assert.equal(h.state.deletingConversationIds.size, 0);
});

for (const failure of ["rejected", "zero-deletions"]) test(`${failure} retains the current conversation and draft`, async () => {
  const h = deletionHost({ deleteDesktopConversation: async () => {
    if (failure === "rejected") throw new Error("Backend unavailable");
    return { deleted_task_ids: [] };
  } });
  await h.context.deleteConversation();
  assert.equal(h.state.currentConversationId, "current");
  assert.equal(h.input.value, "Unsent draft");
  assert.equal(h.state.pinnedConversationIds.has("current"), true);
  assert.deepEqual([...h.state.selectedConversationIds], ["current"]);
  assert.equal(h.state.conversationDeletionPromise, null);
});

test("partial bulk failure does not reset a failed active conversation", async () => {
  const h = deletionHost({ deleteDesktopConversation: async (id) => {
    if (id === "current") throw new Error("Busy");
    return { deleted_task_ids: [id] };
  } });
  await h.context.requestConversationDeletion(["current", "other"], "Delete");
  assert.equal(h.state.currentConversationId, "current");
  assert.equal(h.input.value, "Unsent draft");
  assert.equal(h.state.pinnedConversationIds.has("other"), false);
  assert.deepEqual([...h.state.selectedConversationIds], ["current"]);
});

for (const failingStep of ["persistPinnedConversations", "refreshPeerMessages"]) test(`${failingStep} failure releases deletion guards`, async () => {
  const h = deletionHost();
  h.context[failingStep] = () => { throw new Error("Synthetic failure"); };
  await h.context.requestConversationDeletion(["other"], "Delete");
  assert.equal(h.state.deletingConversationIds.size, 0);
  assert.equal(h.state.conversationDeletionPromise, null);
  assert.match(h.errors[0], /Synthetic failure/);
  assert.equal(h.input.value, "Unsent draft");
});

test("in-flight deletion ignores a duplicate request without freezing other input", async () => {
  let finish;
  const h = deletionHost({ deleteDesktopConversation: () => new Promise((resolve) => { finish = resolve; }) });
  const pending = h.context.requestConversationDeletion(["other"], "Delete");
  await new Promise(setImmediate);
  assert.equal(typeof finish, "function");
  await h.context.requestConversationDeletion(["current"], "Duplicate");
  h.input.value += " typed while deleting";
  finish({ deleted_task_ids: ["other"] }); await pending;
  assert.equal(h.input.value, "Unsent draft typed while deleting");
  assert.equal(h.state.currentConversationId, "current");
});

test("contact deletion resets only the matching active contact", async () => {
  const h = deletionHost(); h.state.activePeerRouteId = "peer";
  await h.context.requestConversationDeletion(["peer"], "Delete");
  assert.equal(h.state.activePeerRouteId, "");
  assert.equal(h.state.currentConversationId, "new");
});

test("all conversation deletion entry points avoid synchronous native confirmation", () => {
  assert.doesNotMatch(source, /window\.confirm\(t\("Delete (?:this conversation|the selected conversations)/);
  assert.match(source, /void requestConversationDeletion\(\[id\]/);
  assert.match(source, /await requestConversationDeletion\(\[\.\.\.state\.selectedConversationIds\]/);
  const html = fs.readFileSync(path.join(__dirname, "../src/renderer/index.html"), "utf8");
  assert.match(html, /<dialog id="conversationDeleteDialog"/);
  assert.ok(html.indexOf('src="./conversation-confirmation.js"') < html.indexOf('src="./workspace.js"'));
});
