/** Opt-in native clipboard regression. Only test images enter the isolated smoke workspace. */
async function verifyNativeClipboard(window, clipboard, nativeImage, assetPath, screenshotPath) {
  const saved = { text: clipboard.readText(), html: clipboard.readHTML(), rtf: clipboard.readRTF(), image: clipboard.readImage() };
  const evaluate = (code) => window.webContents.executeJavaScript(code);
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  try {
    const point = await evaluate(`(() => {
      const image = document.querySelector("#peerImageViewerImage");
      const rect = image.getBoundingClientRect();
      return { x: Math.round(rect.x + rect.width / 2), y: Math.round(rect.y + rect.height / 2), width: image.naturalWidth };
    })()`);
    clipboard.clear();
    window.webContents.copyImageAt(point.x, point.y);
    const copyDeadline = Date.now() + 3_000;
    while (clipboard.readImage().isEmpty() && Date.now() < copyDeadline) await wait(50);
    if (clipboard.readImage().isEmpty()) throw new Error("Native image copy did not populate the clipboard");
    await evaluate(`closePeerImageViewer(); elements.prompt.focus();`);
    window.webContents.paste();
    const pasteDeadline = Date.now() + 5_000;
    while (Date.now() < pasteDeadline && await evaluate("state.attachments.length") !== 1) await wait(50);
    if (await evaluate("state.attachments.length") !== 1) throw new Error("Copied peer image could not be pasted");
    await evaluate("newTask();");
    clipboard.writeImage(nativeImage.createFromPath(assetPath));
    const fallback = await evaluate(`(async () => {
      elements.prompt.value = "\u622a\u56fe\u6d4b\u8bd5";
      const paste = new Event("paste", { bubbles: true, cancelable: true });
      Object.defineProperty(paste, "clipboardData", { value: new DataTransfer() });
      elements.prompt.dispatchEvent(paste);
      const end = Date.now() + 5_000;
      while (state.attachments.length !== 1 && Date.now() < end) await new Promise((resolve) => setTimeout(resolve, 50));
      const image = document.querySelector(".composer-image-attachment img");
      try { await image?.decode(); } catch {}
      return { count: state.attachments.length, loaded: Boolean(image?.naturalWidth), text: elements.prompt.value,
        prevented: paste.defaultPrevented, peer: state.activePeerRouteId };
    })()`);
    if (fallback.count !== 1 || !fallback.loaded || !fallback.prevented || fallback.peer || fallback.text !== "\u622a\u56fe\u6d4b\u8bd5")
      throw new Error(`Native bitmap fallback failed: ${JSON.stringify(fallback)}`);
    const image = await window.webContents.capturePage();
    require("node:fs").writeFileSync(screenshotPath, image.toPNG());
    await evaluate("newTask();");
    clipboard.writeText("https://example.org/photo.png");
    window.webContents.paste();
    await wait(150);
    const text = await evaluate("({ text: elements.prompt.value, count: state.attachments.length })");
    if (text.text !== "https://example.org/photo.png" || text.count !== 0) throw new Error("Image URL was mistaken for an image");
    await evaluate("newTask();");
    return { nativeCopy: true, peerPaste: true, nativeFallback: true, textPaste: true };
  } finally { clipboard.write(saved); }
}
module.exports = { verifyNativeClipboard };
