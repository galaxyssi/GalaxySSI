// A taskbar count, not a toast: no message text leaves the renderer.
const { BADGE_SCALES } = require("./conversation_unread");
function createConversationUnreadIndicator({ getWindow, nativeImage, platform = process.platform, setNativeOverlay }) {
  let previousWindow;
  let previousCount;

  return {
    update(count, representations) {
      if (!Number.isSafeInteger(count) || count < 0) return false;
      const window = getWindow();
      if (!window || window.isDestroyed()) return false;
      if (window === previousWindow && count === previousCount) return true;
      if (platform === "win32") {
        if (setNativeOverlay) {
          previousWindow = window;
          previousCount = count;
          return Promise.resolve().then(() => setNativeOverlay(window, count)).catch(error => {
            if (previousWindow === window && previousCount === count) previousCount = undefined;
            throw error;
          });
        }
        let badge = null;
        if (count > 0) {
          if (!Array.isArray(representations) || representations.length !== BADGE_SCALES.length) return false;
          badge = nativeImage.createEmpty();
          for (let i = 0; i < BADGE_SCALES.length; i += 1) {
            const rep = representations[i];
            const scaleFactor = BADGE_SCALES[i];
            if (!rep || rep.scaleFactor !== scaleFactor || typeof rep.dataURL !== "string"
              || rep.dataURL.length > 16384 || !rep.dataURL.startsWith("data:image/png;base64,")) return false;
            const image = nativeImage.createFromDataURL(rep.dataURL);
            const size = image.getSize();
            if (image.isEmpty() || size.width !== 16 * scaleFactor || size.height !== 16 * scaleFactor) return false;
            badge.addRepresentation({ scaleFactor, dataURL: rep.dataURL });
          }
        }
        window.setOverlayIcon(badge, count > 0 ? `${count} unread messages` : "");
      }
      previousWindow = window;
      previousCount = count;
      return true;
    }
  };
}

module.exports = { createConversationUnreadIndicator };
