function buildImageContextMenuItem(params = {}, actions = {}) {
  if (params.mediaType !== "image" || !params.hasImageContents || typeof actions.copyImage !== "function") return null;
  return { label: actions.copyImageLabel || "Copy Image", click: actions.copyImage };
}

function buildTextContextMenuTemplate(params = {}, actions = {}) {
  const flags = params.editFlags || {};
  const hasSelection = String(params.selectionText || "").length > 0;

  if (!params.isEditable) {
    const image = buildImageContextMenuItem(params, actions);
    return [...(image ? [image] : []), ...(hasSelection ? [{ role: "copy", enabled: flags.canCopy !== false }] : [])];
  }

  return [
    { role: "undo", enabled: Boolean(flags.canUndo) },
    { role: "redo", enabled: Boolean(flags.canRedo) },
    { type: "separator" },
    { role: "cut", enabled: hasSelection && flags.canCut !== false },
    { role: "copy", enabled: hasSelection && flags.canCopy !== false },
    { role: "paste", enabled: flags.canPaste !== false },
    { role: "delete", enabled: hasSelection && flags.canDelete !== false },
    { type: "separator" },
    { role: "selectAll", enabled: flags.canSelectAll !== false }
  ];
}

module.exports = { buildTextContextMenuTemplate, buildImageContextMenuItem };
