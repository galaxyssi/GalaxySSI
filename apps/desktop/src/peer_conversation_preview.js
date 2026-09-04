(function initPeerConversationPreview(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.galaxyssiPeerConversationPreview = api;
})(typeof window !== "undefined" ? window : globalThis, () => {
  const AUDIO_EXTENSIONS = new Set(["aac", "flac", "m4a", "mp3", "ogg", "opus", "wav", "webm"]);
  const IMAGE_EXTENSIONS = new Set(["avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "webp"]);

  function extension(name) {
    const match = String(name || "").trim().toLowerCase().match(/\.([a-z0-9]+)$/);
    return match?.[1] || "";
  }

  function attachmentKind(attachment = {}) {
    const name = String(attachment.name || "").trim().toLowerCase();
    const mimeType = String(attachment.mime_type || attachment.mimeType || "").trim().toLowerCase();
    const suffix = extension(name);
    if (mimeType.startsWith("audio/") || /^voice(?:[-_.]|$)/.test(name) || AUDIO_EXTENSIONS.has(suffix)) {
      return "voice";
    }
    if (mimeType.startsWith("image/") || IMAGE_EXTENSIONS.has(suffix)) return "image";
    return "file";
  }

  function messagePreview(message = {}, labels = {}) {
    const attachments = Array.isArray(message.attachments) ? message.attachments.filter(Boolean) : [];
    if (attachments.length) {
      const kinds = attachments.map(attachmentKind);
      if (kinds.every((kind) => kind === "voice")) return labels.voice || "Voice";
      if (kinds.every((kind) => kind === "image")) return labels.image || "Image";
      return labels.file || "File";
    }
    return String(message.content || labels.fallback || "");
  }

  return Object.freeze({ attachmentKind, messagePreview });
});
