function createReminderNotifications({ Notification, getWindow, translate = key => key }) {
  const entries = new Map();
  return function update(value) {
    const now = Date.now();
    if (!value || !/^[a-zA-Z0-9-]{16,64}$/.test(value.id) ||
        !Number.isFinite(value.expires_at) || value.expires_at > now + 150000) return;
    const old = entries.get(value.id);
    const active = value.status === "received" && value.expires_at > now;
    if (!active) { old?.notice?.close(); return; }
    if (old) return;
    const entry = { notice: null };
    entries.set(value.id, entry);
    setTimeout(() => { entry.notice?.close(); entries.delete(value.id); }, Math.max(1, value.expires_at - now)).unref();
    if (getWindow()?.isFocused() || !Notification.isSupported()) return;
    entry.notice = new Notification({ title: "GalaxySSI", body: translate("A contact is reminding you", value.language), silent: false });
    entry.notice.on("click", () => { const window = getWindow(); if (window?.isMinimized()) window.restore(); window?.show(); window?.focus(); });
    entry.notice.show();
  };
}
module.exports = { createReminderNotifications };
