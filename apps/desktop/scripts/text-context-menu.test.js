const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const crypto = require("node:crypto");
const { Readable } = require("node:stream");
const { pipeline } = require("node:stream/promises");
const { buildTextContextMenuTemplate, buildImageContextMenuItem, buildPeerAttachmentSaveMenuItem } = require("../src/text_context_menu.js");
const main = fs.readFileSync(path.join(__dirname, "../src/main.js"), "utf8");
const workspace = fs.readFileSync(path.join(__dirname, "../src/renderer/workspace.js"), "utf8");

test("selected desktop output exposes copy only", () => {
  assert.deepEqual(
    buildTextContextMenuTemplate({
      isEditable: false,
      selectionText: "selected output",
      editFlags: { canCopy: true }
    }),
    [{ role: "copy", enabled: true }]
  );
});

test("unselected desktop output does not open an empty menu", () => {
  assert.deepEqual(
    buildTextContextMenuTemplate({ isEditable: false, selectionText: "" }),
    []
  );
});

test("desktop input always exposes paste and standard editing roles", () => {
  const template = buildTextContextMenuTemplate({
    isEditable: true,
    selectionText: "",
    editFlags: { canPaste: true, canSelectAll: true }
  });
  const roles = template.map((item) => item.role).filter(Boolean);

  assert.deepEqual(roles, ["undo", "redo", "cut", "copy", "paste", "delete", "selectAll"]);
  assert.equal(template.find((item) => item.role === "paste").enabled, true);
  assert.equal(template.find((item) => item.role === "copy").enabled, false);
});

test("loaded images expose a real image-copy command instead of copying a file name", () => {
  let copies = 0;
  const menu = buildTextContextMenuTemplate({ mediaType: "image", hasImageContents: true },
    { copyImage: () => copies++, copyImageLabel: "Copy Image" });
  assert.equal(menu.length, 1); assert.equal(menu[0].label, "Copy Image");
  menu[0].click(); assert.equal(copies, 1);
});
test("unloaded images and editable controls do not get a broken image-copy item", () => {
  const actions = { copyImage: () => assert.fail("no image") };
  assert.deepEqual(buildTextContextMenuTemplate({ mediaType: "image", hasImageContents: false }, actions), []);
  assert.equal(buildTextContextMenuTemplate({ isEditable: true, mediaType: "image", hasImageContents: true }, actions)
    .some((item) => item.label === "Copy Image"), false);
});

test("attachment save targets the selected message and index, including index zero", async () => {
  for (const attachmentIndex of [0, 1, 4]) {
    const saved = [];
    const item = buildPeerAttachmentSaveMenuItem({ messageId: "message", attachmentIndex }, {
      saveAttachmentLabel: "Save as...", saveAttachment: (...args) => saved.push(args)
    });
    assert.equal(item.label, "Save as...");
    assert.equal(item.enabled, true);
    await item.click();
    assert.deepEqual(saved, [["message", attachmentIndex]]);
  }
});

test("message text and invalid attachment indexes do not expose save", () => {
  const actions = { saveAttachment: () => assert.fail("must not save") };
  for (const attachmentIndex of [undefined, null, "0", -1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.equal(buildPeerAttachmentSaveMenuItem({ messageId: "message", attachmentIndex }, actions), null);
  }
  assert.equal(buildPeerAttachmentSaveMenuItem({ attachmentIndex: 0 }, actions), null);
  assert.equal(buildPeerAttachmentSaveMenuItem({ messageId: "message", attachmentIndex: 0 }), null);
});

test("unavailable attachments expose a disabled save action", () => {
  const item = buildPeerAttachmentSaveMenuItem({ messageId: "message", attachmentIndex: 0, attachmentAvailable: false }, {
    saveAttachment: () => assert.fail("must not fetch unavailable attachment")
  });
  assert.equal(item.enabled, false);
  item.click();
});

function nativeMenu(peer, params = {}) {
  let callback, shown;
  const saved = [];
  const context = {
    mainWindow: { webContents: { on: (_event, listener) => { callback = listener; } }, isDestroyed: () => false },
    peerContextTarget: peer, workspaceLocale: {}, Date,
    buildImageContextMenuItem, buildTextContextMenuTemplate, buildPeerAttachmentSaveMenuItem,
    savePeerAttachmentWithFeedback: (...args) => saved.push(args),
    clipboard: { writeText() {} }, deletePeerMessage: async () => ({ deleted: false }),
    Menu: { buildFromTemplate: (items) => ({ popup: () => { shown = items; } }) }
  };
  vm.runInNewContext(main.slice(main.indexOf('mainWindow.webContents.on("context-menu"'),
    main.indexOf('  mainWindow.on("blur"')), context);
  callback({ preventDefault() {} }, { x: 10, y: 20, ...params });
  return { shown, saved, context };
}

test("native attachment menu retains copy and delete and adds save", async () => {
  const peer = { messageId: "message", routeId: "route", attachmentIndex: 1,
    copyText: "file.mp4", copyLabel: "Copy", deleteLabel: "Delete Message", at: Date.now(), x: 10, y: 20 };
  const result = nativeMenu(peer);
  assert.deepEqual(Array.from(result.shown, (item) => item.label), ["Copy", "Save attachment as...", "Delete Message"]);
  await result.shown[1].click();
  assert.deepEqual(result.saved, [["message", 1]]);
  assert.equal(result.context.peerContextTarget, null);
});

test("stale, displaced and editable native contexts cannot save the previous attachment", () => {
  const peer = { messageId: "message", attachmentIndex: 0, at: Date.now(), x: 10, y: 20 };
  for (const [target, params] of [[{ ...peer, at: Date.now() - 2000 }, {}],
    [peer, { x: 200 }], [peer, { isEditable: true }]]) {
    const result = nativeMenu(target, params);
    assert.equal((result.shown || []).some((item) => item.label === "Save attachment as..."), false);
  }
});

function rendererContext(attachmentIndex, files, button = 2, storedRoute = "route") {
  let handler, payload;
  const row = { dataset: { peerMessageId: "message" } };
  const attachment = attachmentIndex === null ? null : { dataset: { peerAttachmentIndex: String(attachmentIndex) } };
  const context = {
    state: { activePeerRouteId: "route" },
    elements: { messages: { addEventListener: (_name, listener) => { handler = listener; } } },
    peerMessagesFor: () => [{ message_id: "message", client_route_id: storedRoute, attachments: files }], t: (value) => value,
    window: { galaxyssi: { preparePeerMessageContext: (value) => { payload = value; } } }
  };
  const start = workspace.indexOf('elements.messages.addEventListener("pointerdown"');
  vm.runInNewContext(workspace.slice(start, workspace.indexOf('  window.galaxyssi.onPeerMessageDeleted', start)), context);
  handler({ button, clientX: 10, clientY: 20,
    target: { closest: (selector) => selector.startsWith(".peer-message-row") ? row : attachment } });
  return payload;
}

test("renderer forwards the clicked file rather than the first attachment", () => {
  const payload = rendererContext(1, [{ name: "first.pdf" }, { name: "second.mp4" }]);
  assert.equal(payload.attachmentIndex, 1);
  assert.equal(payload.attachmentAvailable, true);
  assert.equal(payload.messageId, "message");
  assert.equal(payload.routeId, "route");
  assert.equal(rendererContext(0, [{ name: "old.pdf" }], 2, "retired-route").routeId, "retired-route");
});

test("renderer handles message whitespace, missing files, unavailable files and left click", () => {
  const files = [{ name: "file.mp4", available: false }];
  assert.equal(rendererContext(null, files).attachmentIndex, null);
  assert.equal(rendererContext(4, files).attachmentIndex, null);
  assert.equal(rendererContext(0, files).attachmentAvailable, false);
  assert.equal(rendererContext(0, files, 0), undefined);
});

test("every attachment type renders a stable right-click index", () => {
  const context = { t: (value) => value, escapeHtml: (value) => String(value),
    formatBytes: () => "1 KB", formatDuration: () => "1s" };
  vm.runInNewContext(workspace.slice(workspace.indexOf("function renderPeerAttachments("),
    workspace.indexOf("function peerImagePreviewKey(")), context);
  const html = context.renderPeerAttachments({ message_id: "message", attachments: [
    { name: "report.pdf", mime_type: "application/pdf" }, { name: "video.mp4", mime_type: "video/mp4" },
    { name: "photo.jpg", mime_type: "image/jpeg" }, { name: "voice.ogg", mime_type: "audio/ogg" }
  ] });
  for (let index = 0; index < 4; index++) assert.equal(html.split(`data-peer-attachment-index="${index}"`).length, 2);
});

function saveHarness(t, { name = "report.pdf", canceled = false, body, error } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "galaxyssi-attachment-save-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const target = path.join(directory, name), calls = [], messages = [];
  const response = new Response(body || Uint8Array.from([0, 1, 2, 3, 255]), { headers: {
    "Content-Disposition": `attachment; filename*=UTF-8''${encodeURIComponent(name)}`
  } });
  let dialogOptions;
  const context = {
    path, fs, crypto, process, Readable, pipeline, workspaceLocale: { "Save attachment as...": "Save as" },
    app: { getPath: () => directory },
    mainWindow: { isDestroyed: () => false, webContents: { send: (...args) => messages.push(args) } },
    fetchPeerAttachment: async (...args) => { calls.push(args); if (error) throw error; return response; },
    dialog: { showSaveDialog: async (_window, options) => { dialogOptions = options; return { canceled, filePath: target }; } }
  };
  vm.runInNewContext(main.slice(main.indexOf("function peerAttachmentFilename("), main.indexOf("async function loadPeerVoice(")) +
    main.slice(main.indexOf("async function savePeerAttachment("), main.indexOf("async function openPeerAttachment(")), context);
  return { context, target, directory, response, calls, messages, options: () => dialogOptions };
}

for (const name of ["report.pdf", "video.mp4", "photo.jpg"]) test(`save menu streams original ${name} bytes and filename`, async (t) => {
  const bytes = Buffer.alloc(2 * 1024 * 1024, 73);
  const h = saveHarness(t, { name, body: bytes });
  await h.context.savePeerAttachmentWithFeedback("message", 1);
  assert.deepEqual(h.calls, [["message", 1]]);
  assert.deepEqual(fs.readFileSync(h.target), bytes);
  assert.deepEqual(fs.readdirSync(h.directory), [name]);
  assert.equal(h.options().defaultPath, h.target);
  assert.equal(h.options().title, "Save as");
  assert.equal(h.messages[0][0], "peer-attachment:save-result");
  assert.equal(h.messages[0][1].ok, true);
});

test("canceling Save As leaves no file or error notification", async (t) => {
  const h = saveHarness(t, { canceled: true });
  await h.context.savePeerAttachmentWithFeedback("message", 0);
  assert.deepEqual(fs.readdirSync(h.directory), []);
  assert.deepEqual(h.messages, []);
  assert.equal(h.response.bodyUsed, true);
});

test("download failure is reported without an unhandled menu promise", async (t) => {
  const h = saveHarness(t, { error: new Error("Attachment unavailable") });
  await h.context.savePeerAttachmentWithFeedback("message", 0);
  assert.equal(h.messages[0][1].ok, false);
  assert.equal(h.messages[0][1].error, "Attachment unavailable");
  assert.deepEqual(fs.readdirSync(h.directory), []);
});

test("interrupted transfer removes partial files and preserves an existing destination", async (t) => {
  const body = new ReadableStream({ pull(controller) { controller.error(new Error("Transfer interrupted")); } });
  const h = saveHarness(t, { body });
  fs.writeFileSync(h.target, "existing");
  await h.context.savePeerAttachmentWithFeedback("message", 0);
  assert.equal(h.messages[0][1].ok, false);
  assert.equal(fs.readFileSync(h.target, "utf8"), "existing");
  assert.deepEqual(fs.readdirSync(h.directory), ["report.pdf"]);
});

test("save feedback reaches the renderer through the preload bridge", () => {
  const source = fs.readFileSync(path.join(__dirname, "../src/preload.js"), "utf8");
  let bridge, listener, removed = false, received;
  vm.runInNewContext(source, { require: () => ({
    contextBridge: { exposeInMainWorld: (_key, value) => { bridge = value; } },
    ipcRenderer: { on: (channel, value) => { assert.equal(channel, "peer-attachment:save-result"); listener = value; },
      removeListener: (_channel, value) => { removed = value === listener; } }
  }) });
  const dispose = bridge.onPeerAttachmentSaveResult((result) => { received = result; });
  listener({}, { ok: true, name: "report.pdf" });
  assert.equal(received.name, "report.pdf");
  dispose(); assert.equal(removed, true);
});
