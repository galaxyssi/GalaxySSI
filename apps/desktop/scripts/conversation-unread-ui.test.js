const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs/promises");
const http = require("node:http");
const path = require("node:path");
const { chromium } = require("playwright");

test("unread dots in the existing renderer: visibility, cross-chat, replay, and layout", async () => {
  const root = path.resolve(__dirname, "../src");
  const server = http.createServer(async (request, response) => {
    try {
      const file = path.resolve(root, `.${new URL(request.url, "http://localhost").pathname}`);
      if (!file.startsWith(root + path.sep)) { response.writeHead(403).end(); return; }
      let content = await fs.readFile(file);
      if (file.endsWith("workspace.js")) {
        // Exercise the real renderer without starting external services or Electron IPC.
        content = content.toString().replace(/init\(\)\.catch\([\s\S]*$/, "");
      }
      response.setHeader("Content-Type", file.endsWith(".js") ? "text/javascript"
        : file.endsWith(".css") ? "text/css" : file.endsWith(".html") ? "text/html" : "application/octet-stream");
      response.end(content);
    } catch { response.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  let browser;
  try {
    browser = await chromium.launch({ headless: true, channel: process.env.PLAYWRIGHT_CHANNEL || "chrome" });
    const page = await browser.newPage({ viewport: { width: 854, height: 571 } });
    await page.addInitScript(() => {
      window.nativeUnreadUpdates = [];
      window.galaxyssi = { onSensitiveStateClear() {}, onSensitiveStateResume() {},
        setConversationUnread(unread) { window.nativeUnreadUpdates.push(unread); return Promise.resolve(true); } };
    });
    await page.goto(`http://127.0.0.1:${server.address().port}/renderer/index.html`);
    const badgePixels = await page.evaluate(async () => {
      const results = [];
      for (const count of [1, 12, 100]) {
        for (const rep of unreadPolicy.badgeRepresentations(count, document)) {
        const size = 16 * rep.scaleFactor;
        const image = new Image();
        image.src = rep.dataURL;
        await image.decode();
        const canvas = document.createElement("canvas");
        canvas.width = canvas.height = size;
        const context = canvas.getContext("2d");
        context.drawImage(image, 0, 0);
        const pixels = context.getImageData(0, 0, size, size).data;
        const occupiedX = [];
        for (let y = 0; y < size; y += 1) for (let x = 0; x < size; x += 1) {
          if (pixels[(y * size + x) * 4 + 3] > 127) occupiedX.push(x);
        }
        results.push({
          size,
          occupiedWidth: Math.max(...occupiedX) - Math.min(...occupiedX) + 1,
          background: [...context.getImageData(size / 2, Math.ceil(size * 0.19), 1, 1).data],
          cornerAlpha: pixels[3],
          hasWhiteText: pixels.some((value, i) => i % 4 === 0 && value > 180
            && pixels[i + 1] > 180 && pixels[i + 2] > 180 && pixels[i + 3] === 255)
        });
        }
      }
      return results;
    });
    for (const badge of badgePixels) {
      assert.deepEqual(badge.background, [0, 0, 0, 255]);
      assert.equal(badge.cornerAlpha, 0);
      assert.equal(badge.hasWhiteText, true);
      assert.ok(Math.abs(badge.occupiedWidth - badge.size * 0.7) <= 1,
        `badge width ${badge.occupiedWidth} should be 70% of ${badge.size}`);
    }
    await page.evaluate(() => {
      window.galaxyssiConnecting?.finish();
      state.currentConversationId = "current";
      state.pairing = { clients: [{ client_route_id: "phone", display_name: "S26U" }] };
      observeConversationUnread("tasks", []);
      observeConversationUnread("messages", []);
      state.tasks = [{ task_id: "other-task", conversation_id: "other", status: "running",
        prompt: "Research task", created_at: Date.now(), updated_at: Date.now() }];
      renderHistory();
    });
    await page.locator("#startupConnecting").waitFor({ state: "hidden" });
    const before = await page.locator('[data-conversation-id="other"]').boundingBox();
    await page.evaluate(() => mergeTaskUpdate({ ...state.tasks[0], status: "completed", result: "Done" }));
    assert.equal(await page.locator(".conversation-unread-dot").count(), 1);
    assert.equal(await page.evaluate(() => nativeUnreadUpdates.at(-1)), 1);
    const after = await page.locator('[data-conversation-id="other"]').boundingBox();
    assert.equal(before.height, after.height);
    assert.equal(before.width, after.width);
    await page.evaluate(() => {
      Object.defineProperty(document, "hasFocus", { configurable: true, value: () => false });
      state.currentConversationId = "other";
      renderHistory();
    });
    assert.equal(await page.locator(".conversation-unread-dot").count(), 1, "background selection is not read");
    await page.evaluate(() => {
      Object.defineProperty(document, "hasFocus", { configurable: true, value: () => true });
      renderHistory();
    });
    assert.equal(await page.locator(".conversation-unread-dot").count(), 0);
    assert.equal(await page.evaluate(() => nativeUnreadUpdates.at(-1)), 0);
    await page.evaluate(() => {
      state.currentConversationId = "current";
      mergeTaskUpdate({ ...state.tasks[0], result: "Done with materialized output" });
    });
    assert.equal(await page.locator(".conversation-unread-dot").count(), 0, "replayed output is not new");
    await page.evaluate(() => {
      state.peerMessages = [{ message_id: "in", client_route_id: "phone", direction: "inbound",
        content: "Hello", created_at_ms: Date.now() }];
      observeConversationUnread("messages", state.peerMessages, false);
      renderHistory();
    });
    assert.equal(await page.locator('[data-peer-route="phone"] .conversation-unread-dot').count(), 1);
    for (const width of [854, 1280]) {
      await page.setViewportSize({ width, height: 800 });
      const dot = await page.locator('[data-peer-route="phone"] .conversation-unread-dot').boundingBox();
      assert.equal(dot.width, 6);
      assert.equal(dot.height, 6);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    }
    if (process.env.GALAXYSSI_UNREAD_SCREENSHOT) {
      await page.screenshot({ path: process.env.GALAXYSSI_UNREAD_SCREENSHOT });
    }
    await page.evaluate(() => {
      Object.defineProperty(document, "hasFocus", { configurable: true, value: () => false });
      state.activePeerRouteId = "phone";
      renderHistory();
    });
    assert.equal(await page.evaluate(() => nativeUnreadUpdates.at(-1)), 1,
      "background contact messages keep the native taskbar dot");
    await page.evaluate(() => {
      mergeTaskUpdate({ task_id: "new-task", conversation_id: "another", status: "completed", result: "Done" });
      Object.defineProperty(document, "hasFocus", { configurable: true, value: () => true });
      renderHistory();
    });
    assert.equal(await page.locator('[data-peer-route="phone"] .conversation-unread-dot').count(), 0);
    assert.equal(await page.evaluate(() => nativeUnreadUpdates.at(-1)), 1,
      "reading the phone conversation cannot clear another agent's dot");
    await page.evaluate(() => {
      state.activePeerRouteId = "";
      state.currentConversationId = "another";
      renderHistory();
    });
    assert.equal(await page.evaluate(() => nativeUnreadUpdates.at(-1)), 0);
    await page.evaluate(() => {
      observeConversationUnread("messages", state.peerMessages, false);
      renderHistory();
    });
    assert.equal(await page.evaluate(() => nativeUnreadUpdates.at(-1)), 0, "replay cannot relight taskbar");
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
});
