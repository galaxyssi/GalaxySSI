(() => {
  const pending = new Map();
  const seen = new Map();
  const terminal = new Set(["acknowledged", "dismissed", "cancelled", "expired"]);
  let panel = null;
  let timer = null;
  let activeId = "";
  const label = key => window.t?.(key) || key;

  function render() {
    clearTimeout(timer);
    const now = Date.now();
    for (const [id, value] of pending) if (value.expires_at <= now || terminal.has(value.status)) pending.delete(id);
    for (const [id, value] of seen) if (value.expires_at <= now) seen.delete(id);
    const value = [...pending.values()].sort((a, b) => a.created_at - b.created_at)[0];
    if (!value) { panel?.remove(); panel = null; activeId = ""; return; }
    if (!panel) {
      panel = document.createElement("section");
      panel.className = "peer-reminder-panel";
      panel.setAttribute("role", "dialog");
      panel.setAttribute("aria-modal", "false");
      panel.setAttribute("aria-live", "polite");
      document.body.append(panel);
    }
    panel.replaceChildren();
    activeId = value.id;
    const heading = document.createElement("strong");
    heading.textContent = value.sender_name || "GalaxySSI";
    const text = document.createElement("p");
    text.textContent = value.status === "muted" ? label("Reminder silenced") : label("Your contact is reminding you");
    const buttons = document.createElement("div");
    buttons.className = "peer-reminder-actions";
    const error = document.createElement("span");
    error.className = "peer-reminder-error";
    for (const [action, text] of [["muted", "Mute"], ["dismissed", "Ignore"], ["acknowledged", "Got it"]]) {
      const button = document.createElement("button");
      button.textContent = label(text);
      button.className = action === "acknowledged" ? "primary" : "";
      button.addEventListener("click", async () => {
        for (const item of buttons.children) item.disabled = true;
        try {
          const result = await window.galaxyssi.respondPeerReminder(value.id, action);
          if (!result.queued) throw new Error(label("Receipt was not queued. Please retry."));
          receive(result.reminder);
        } catch (exception) {
          error.textContent = String(exception.message || exception);
          for (const item of buttons.children) item.disabled = false;
        }
      });
      buttons.append(button);
    }
    panel.append(heading, text, buttons, error);
    panel.setAttribute("aria-label", label("Contact reminder"));
    timer = setTimeout(render, Math.max(1, value.expires_at - now));
  }

  function receive(value) {
    if (!value?.id || !Number.isFinite(value.expires_at)) return;
    const previous = seen.get(value.id);
    if (previous && previous.client_route_id !== value.client_route_id) return;
    if (previous && (terminal.has(previous.status) || previous.revision >= value.revision)) return;
    seen.set(value.id, value);
    pending.set(value.id, value);
    window.galaxyssi.updateReminderNotification?.({ id: value.id, expires_at: value.expires_at,
      status: value.status, language: document.documentElement.lang });
    render();
  }

  function restore(values) {
    pending.clear();
    for (const value of values || []) if (value?.id && Number.isFinite(value.expires_at)) {
      const previous = seen.get(value.id);
      if (previous && terminal.has(previous.status)) continue;
      const current = previous?.revision > value.revision ? previous : value;
      seen.set(value.id, current);
      pending.set(value.id, current);
    }
    render();
  }
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && activeId) {
      const button = panel?.querySelector("button");
      if (button && !button.disabled) button.click();
    }
  });
  window.GalaxySSIPeerReminders = { receive, restore };
})();
