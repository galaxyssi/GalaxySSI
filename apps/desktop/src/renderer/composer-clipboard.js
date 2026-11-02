(function (root) {
  function plan(data) {
    let files = Array.from(data?.files || []);
    if (!files.length) files = Array.from(data?.items || [])
      .filter((item) => item.kind === "file").map((item) => item.getAsFile()).filter(Boolean);
    const types = [...Array.from(data?.types || []), ...Array.from(data?.items || []).map((item) => item.type)]
      .filter(Boolean).map((type) => String(type).toLowerCase());
    return { files: files.slice(0, 12), nativeImage: !files.length &&
      (!types.length || types.every((type) => type === "files") || types.some((type) => type.startsWith("image/"))) };
  }
  const api = { plan };
  if (typeof module === "object" && module.exports) module.exports = api;
  root.GalaxySSIComposerClipboard = api;
})(typeof window === "object" ? window : globalThis);
