(function (root) {
  function create({ document, dialog, message, confirmButton, cancelButton, fallbackFocus }) {
    let pending = null;
    let previousFocus = null;
    function finish() {
      if (!pending) return;
      const resolve = pending;
      pending = null;
      const accepted = dialog.returnValue === "confirm";
      try {
        if (document.hasFocus()) {
          const target = previousFocus?.isConnected && !previousFocus.disabled
            && previousFocus.getClientRects().length ? previousFocus : fallbackFocus();
          target?.focus({ preventScroll: true });
        }
      } catch {
        // A disappearing focus target must not leave deletion waiting on the dialog.
      }
      previousFocus = null;
      resolve(accepted);
    }
    confirmButton.addEventListener("click", () => dialog.close("confirm"));
    cancelButton.addEventListener("click", () => dialog.close("cancel"));
    dialog.addEventListener("cancel", (event) => {
      event.preventDefault();
      dialog.close("cancel");
    });
    dialog.addEventListener("close", finish);
    return {
      ask(text) {
        if (pending) return Promise.resolve(false);
        previousFocus = document.activeElement;
        message.textContent = text;
        dialog.returnValue = "";
        return new Promise((resolve, reject) => {
          pending = resolve;
          try {
            dialog.showModal();
            cancelButton.focus({ preventScroll: true });
          } catch (error) {
            pending = null;
            previousFocus = null;
            reject(error);
          }
        });
      }
    };
  }
  const api = { create };
  if (typeof module === "object" && module.exports) module.exports = api;
  root.GalaxySSIConversationConfirmation = api;
})(typeof window === "object" ? window : globalThis);
