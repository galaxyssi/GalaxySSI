(function (root) {
  function taskEvents(tasks) {
    return tasks.filter(task => task.status === "completed" && task.task_id && task.conversation_id)
      .map(task => ({ id: `task:${task.conversation_id}:${task.task_id}`, conversation: `agent:${task.conversation_id}` }));
  }

  function messageEvents(messages) {
    return messages.filter(message => message.direction === "inbound" && message.message_id && message.client_route_id)
      .map(message => ({ id: `message:${message.client_route_id}:${message.message_id}`, conversation: `device:${message.client_route_id}` }));
  }

  class ConversationUnread {
    constructor(saved = {}) {
      if (!saved || typeof saved !== "object") saved = {};
      this.known = new Set(Array.isArray(saved.known) ? saved.known : []);
      this.pending = new Map(Array.isArray(saved.pending)
        ? saved.pending.filter(pair => Array.isArray(pair) && pair.length === 2
          && pair.every(value => typeof value === "string")) : []);
      this.initialized = new Set(Array.isArray(saved.initialized) ? saved.initialized : []);
    }

    observe(scope, events, snapshot = true) {
      let changed = false;
      const baseline = snapshot && !this.initialized.has(scope);
      for (const event of events) {
        if (this.known.has(event.id)) continue;
        this.known.add(event.id);
        if (!baseline) this.pending.set(event.id, event.conversation);
        changed = true;
      }
      if (snapshot && !this.initialized.has(scope)) {
        this.initialized.add(scope);
        changed = true;
      }
      return changed;
    }

    read(conversation, visibleEvents) {
      let changed = false;
      for (const event of visibleEvents) {
        if (event.conversation === conversation && this.pending.get(event.id) === conversation) {
          this.pending.delete(event.id);
          changed = true;
        }
      }
      return changed;
    }

    has(conversation) { return [...this.pending.values()].includes(conversation); }

    serialize() {
      return { known: [...this.known], pending: [...this.pending], initialized: [...this.initialized] };
    }
  }

  function badgeLabel(count) { return count > 99 ? "99+" : String(count); }
  const BADGE_SCALES = Object.freeze([1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4]);

  function badgeDataUrl(count, document, size = 32) {
    if (count <= 0) return "";
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = size;
    const ctx = canvas.getContext("2d");
    const center = size / 2;
    const diameter = size * 0.7;
    ctx.fillStyle = "#000000";
    ctx.beginPath();
    ctx.arc(center, center, diameter / 2, 0, Math.PI * 2);
    ctx.fill();
    const label = badgeLabel(count);
    ctx.fillStyle = "#ffffff";
    const fontRatio = label.length === 1 ? 0.75 : label.length === 2 ? 0.65625 : 0.5;
    ctx.font = `bold ${Math.round(diameter * fontRatio)}px "Segoe UI", sans-serif`;
    ctx.textAlign = "center";
    ctx.textBaseline = "alphabetic";
    const metrics = ctx.measureText(label);
    const baseline = Math.round(center + (metrics.actualBoundingBoxAscent - metrics.actualBoundingBoxDescent) / 2);
    ctx.fillText(label, center, baseline);
    return canvas.toDataURL("image/png");
  }

  function badgeRepresentations(count, document) {
    if (count <= 0) return [];
    // Rasterize at each physical size instead of stretching a single bitmap.
    return BADGE_SCALES.map(scaleFactor => ({ scaleFactor,
      dataURL: badgeDataUrl(count, document, 16 * scaleFactor) }));
  }

  const api = { ConversationUnread, taskEvents, messageEvents, badgeLabel, badgeDataUrl, badgeRepresentations, BADGE_SCALES };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.galaxyssiConversationUnread = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
