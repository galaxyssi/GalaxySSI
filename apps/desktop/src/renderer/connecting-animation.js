(function exposeConnectingAnimation(root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (root && root.document) root.signalasiConnecting = api.mount(root.document, root);
})(typeof window !== "undefined" ? window : undefined, function createConnectingAnimation() {
  "use strict";

  const LABEL = "CONNECTING";
  const GLITCH_FRAMES = [
    "CONNEC<:_\\",
    "CONNECT:|<",
    "CONNECTI-~",
    "CONNEC|_>\\",
    "CONNECT/|"
  ];

  function frameAt(tick, reduceMotion = false) {
    if (reduceMotion) return { characters: LABEL, cursorVisible: false };
    const safeTick = Math.max(0, Math.trunc(Number(tick) || 0));
    const phase = safeTick % 24;
    const cycle = Math.trunc(safeTick / 24);
    const glitchIndex = phase >= 7 && phase <= 11
      ? phase - 7
      : phase >= 17 && phase <= 20
        ? phase - 16
        : -1;
    const characters = glitchIndex >= 0
      ? GLITCH_FRAMES[(glitchIndex + cycle) % GLITCH_FRAMES.length].padEnd(LABEL.length).slice(0, LABEL.length)
      : LABEL;
    return {
      characters,
      cursorVisible: (phase >= 2 && phase <= 6) || (phase >= 12 && phase <= 16) || phase >= 21
    };
  }

  function mount(documentRef, windowRef) {
    const overlay = documentRef.querySelector("#startupConnecting");
    const cells = documentRef.querySelector("#startupConnectingCells");
    const cursor = documentRef.querySelector("#startupConnectingCursor");
    const app = documentRef.querySelector("#agentApp");
    if (!overlay || !cells || !cursor || !app) return { finish() {} };

    const reduceMotion = Boolean(windowRef.matchMedia?.("(prefers-reduced-motion: reduce)").matches);
    const startedAt = windowRef.performance?.now?.() || Date.now();
    let tick = 0;
    let timer = 0;
    let finishTimer = 0;
    let finished = false;

    const render = () => {
      const frame = frameAt(tick, reduceMotion);
      const existing = [...cells.children];
      frame.characters.split("").forEach((character, index) => {
        const cell = existing[index] || documentRef.createElement("span");
        cell.className = "startup-connecting-cell";
        cell.textContent = character;
        if (!cell.parentNode) cells.appendChild(cell);
      });
      cursor.classList.toggle("visible", frame.cursorVisible);
    };

    const stop = () => {
      if (timer) windowRef.clearInterval(timer);
      if (finishTimer) windowRef.clearTimeout(finishTimer);
      timer = 0;
      finishTimer = 0;
    };

    const dismiss = () => {
      if (finished) return;
      finished = true;
      stop();
      overlay.classList.add("finished");
      app.removeAttribute("aria-hidden");
      windowRef.setTimeout(() => { overlay.hidden = true; }, reduceMotion ? 0 : 180);
    };

    render();
    if (!reduceMotion) {
      timer = windowRef.setInterval(() => {
        tick += 1;
        render();
      }, 75);
    }

    return {
      finish() {
        const minimum = reduceMotion ? 250 : 1_250;
        const elapsed = (windowRef.performance?.now?.() || Date.now()) - startedAt;
        finishTimer = windowRef.setTimeout(dismiss, Math.max(0, minimum - elapsed));
      }
    };
  }

  return { frameAt, mount };
});
