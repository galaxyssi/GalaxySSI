(function initPeerHoldToTalk(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.galaxyssiPeerHoldToTalk = api;
})(typeof window !== "undefined" ? window : globalThis, () => {
  const CANCEL_THRESHOLD_PX = 56;
  const MIN_DURATION_MS = 800;
  const MAX_DURATION_MS = 120_000;

  function isCancelPending(startY, currentY, threshold = CANCEL_THRESHOLD_PX) {
    if (!Number.isFinite(startY) || !Number.isFinite(currentY)) return false;
    return startY - currentY >= threshold;
  }

  function completion({ durationMs, sendRequested, cancelPending }) {
    const duration = Math.max(0, Number(durationMs || 0));
    if (cancelPending || !sendRequested) return { send: false, reason: "cancelled" };
    if (duration < MIN_DURATION_MS) return { send: false, reason: "too_short" };
    return { send: true, reason: "send" };
  }

  function formatElapsed(durationMs) {
    const seconds = Math.max(0, Math.floor(Number(durationMs || 0) / 1000));
    return `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  }

  return Object.freeze({
    CANCEL_THRESHOLD_PX,
    MIN_DURATION_MS,
    MAX_DURATION_MS,
    isCancelPending,
    completion,
    formatElapsed
  });
});
