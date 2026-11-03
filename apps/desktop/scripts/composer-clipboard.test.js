const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const clipboard = require("../src/renderer/composer-clipboard");

test("file-list images are not duplicated through the item list", () => {
  const file = { name: "photo.png" };
  const plan = clipboard.plan({ files: [file], items: [{ kind: "file", type: "image/png", getAsFile: () => file }] });
  assert.deepEqual(plan.files, [file]); assert.equal(plan.nativeImage, false);
});
test("item-only screenshot paste and Windows native bitmap metadata are supported", () => {
  const file = { name: "screen.png" };
  assert.deepEqual(clipboard.plan({ items: [{ kind: "file", getAsFile: () => file }] }).files, [file]);
  assert.equal(clipboard.plan({ types: ["Files"], items: [{ kind: "file", type: "image/png", getAsFile: () => null }] }).nativeImage, true);
  assert.equal(clipboard.plan({ types: ["Files"] }).nativeImage, true);
  assert.equal(clipboard.plan({ types: [] }).nativeImage, true);
});
test("image URLs and HTML text never read a stale native clipboard image", () => {
  for (const types of [["text/plain"], ["text/html", "text/plain"], ["text/uri-list"]])
    assert.equal(clipboard.plan({ types }).nativeImage, false);
});
test("paste retains the existing attachment count bound", () => {
  assert.equal(clipboard.plan({ files: Array.from({ length: 20 }, (_, i) => ({ name: String(i) })) }).files.length, 12);
});

const source = fs.readFileSync(path.join(__dirname, "../src/renderer/workspace.js"), "utf8");
const start = source.indexOf("async function pasteAttachments(event) {");
const end = source.indexOf("\nfunction requirePeerSendSuccess", start);
assert.ok(start > 0 && end > start);
function host(overrides = {}) {
  const additions = [], releases = [], errors = [];
  const state = { activePeerRouteId: "phone", currentConversationId: "agent-conversation", composerPasteEpoch: 1 };
  const api = { clipboardFilePath: () => "", stageClipboardAttachments: async () => [{ path: "staged-image" }],
    pasteClipboardImage: async () => [{ path: "native-image", mimeType: "image/png" }], ...overrides };
  const context = vm.createContext({ state, Uint8Array, window: { GalaxySSIComposerClipboard: clipboard, galaxyssi: api },
    addAttachmentPaths: async (...args) => additions.push(args), releaseStagedAttachments: (paths) => releases.push(paths),
    showToast: (error) => errors.push(error) });
  vm.runInContext(source.slice(start, end), context);
  return { state, api, context, additions, releases, errors };
}
function event(data) { return { clipboardData: data, prevented: false, preventDefault() { this.prevented = true; } }; }

test("native screenshots enter the same preview tray without sending", async () => {
  const h = host(), e = event({ types: ["image/png"] });
  await h.context.pasteAttachments(e);
  assert.equal(e.prevented, true);
  assert.deepEqual(Array.from(h.additions[0][0]), ["native-image"]);
  assert.equal(h.errors.length, 0);
});
test("copied file images use their paths and memory images are staged", async () => {
  const disk = host({ clipboardFilePath: () => "C:\\photo.png", pasteClipboardImage: () => assert.fail("not native") });
  await disk.context.pasteAttachments(event({ files: [{ name: "photo.png" }] }));
  assert.deepEqual(Array.from(disk.additions[0][0]), ["C:\\photo.png"]);
  const memory = host();
  await memory.context.pasteAttachments(event({ items: [{ kind: "file", getAsFile: () =>
    ({ name: "screen.png", type: "image/png", arrayBuffer: async () => new ArrayBuffer(4) }) }] }));
  assert.deepEqual(Array.from(memory.additions[0][0]), ["staged-image"]);
});
test("text-only paste remains native text editing", async () => {
  const h = host({ pasteClipboardImage: () => assert.fail("must not read native image") });
  const e = event({ types: ["text/plain"] });
  await h.context.pasteAttachments(e);
  assert.equal(e.prevented, false); assert.equal(h.additions.length, 0);
});
for (const change of ["peer", "conversation", "privacy-clear"]) test(`late paste cannot attach after ${change}`, async () => {
  let finish;
  const h = host({ pasteClipboardImage: () => new Promise((resolve) => { finish = resolve; }) });
  const pending = h.context.pasteAttachments(event({ types: ["image/png"] }));
  if (change === "peer") h.state.activePeerRouteId = "other-phone";
  else if (change === "conversation") h.state.currentConversationId = "other-conversation";
  else h.state.composerPasteEpoch++;
  finish([{ path: "late-image" }]); await pending;
  assert.equal(h.additions.length, 0);
  assert.deepEqual(Array.from(h.releases[0]), ["late-image"]);
});
test("unavailable native images and errors do not invent attachments", async () => {
  const empty = host({ pasteClipboardImage: async () => [] });
  await empty.context.pasteAttachments(event({ types: [] }));
  assert.equal(empty.additions[0][0].length, 0);
  const broken = host({ pasteClipboardImage: async () => { throw new Error("Clipboard unavailable"); } });
  await broken.context.pasteAttachments(event({ types: [] }));
  assert.deepEqual(broken.errors, ["Clipboard unavailable"]); assert.equal(broken.additions.length, 0);
});

test("late file metadata does not refill preview caches after switching conversations", async () => {
  const from = source.indexOf("async function addAttachmentPaths(");
  const to = source.indexOf("\nasync function addAttachments()", from);
  let finish;
  const details = [];
  const state = { activePeerRouteId: "phone", currentConversationId: "a", composerPasteEpoch: 0,
    attachments: [], attachmentDetails: new Map() };
  const context = vm.createContext({ state, window: { galaxyssi: { describeAttachments: () => new Promise((resolve) => { finish = resolve; }) } },
    rememberAttachmentDetails: (rows) => details.push(...rows), renderAttachmentTray() {}, releaseStagedAttachments() {} });
  vm.runInContext(source.slice(from, to), context);
  const pending = context.addAttachmentPaths(["old-image"]);
  state.currentConversationId = "b"; state.attachments = [];
  finish([{ path: "old-image", previewDataUrl: "sensitive-preview" }]); await pending;
  assert.equal(details.length, 0);
});
