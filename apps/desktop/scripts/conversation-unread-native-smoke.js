const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { app, BrowserWindow, nativeImage } = require("electron");
const { BADGE_SCALES } = require("../src/conversation_unread");
const { createConversationUnreadIndicator } = require("../src/conversation_unread_indicator");
const { WindowsTaskbarBadge } = require("../src/windows_taskbar_badge");

app.whenReady().then(async () => {
  const window = new BrowserWindow({ show: false, webPreferences: { contextIsolation: true, nodeIntegration: false } });
  await window.loadURL("about:blank");
  const source = fs.readFileSync(path.join(__dirname, "../src/conversation_unread.js"), "utf8");
  await window.webContents.executeJavaScript(source);
  let image;
  const indicator = createConversationUnreadIndicator({ getWindow: () => window,
    nativeImage: { createFromDataURL: url => nativeImage.createFromDataURL(url),
      createEmpty: () => (image = nativeImage.createEmpty()) } });
  for (const count of [1, 12, 100]) {
    const reps = await window.webContents.executeJavaScript(`galaxyssiConversationUnread.badgeRepresentations(${count}, document)`);
    assert.equal(indicator.update(count, reps), true);
    assert.deepEqual(image.getScaleFactors(), BADGE_SCALES);
    assert.deepEqual(image.getSize(), { width: 16, height: 16 });
    for (const scaleFactor of BADGE_SCALES) {
      const decoded = nativeImage.createFromBuffer(image.toPNG({ scaleFactor }));
      assert.deepEqual(decoded.getSize(), { width: 16 * scaleFactor, height: 16 * scaleFactor });
    }
  }
  assert.equal(indicator.update(0, []), true);
  if (process.platform === "win32") {
    const helper = new WindowsTaskbarBadge();
    try {
      for (const count of [1, 12, 100, 0]) assert.equal(await helper.update(window, count), true);
      const updates = Array.from({ length: 100 }, (_, i) => helper.update(window, i + 1));
      assert.ok(helper.active && helper.queued);
      await Promise.all(updates);
      assert.equal(helper.lastCount, 100);
      assert.equal(await helper.update(window, 0), true);
      assert.ok(helper.lastPixelSize >= 16);
      console.log(`PASS: Windows COM overlay at ${helper.lastPixelSize}px, bypassing Electron 16px resizer`);
    } finally { helper.dispose(); }
  }
  console.log("PASS: native multi-DPI taskbar badge, 3 counts, 8 scales, clear");
  window.destroy();
  app.exit(0);
}).catch(error => { console.error(error); app.exit(1); });
