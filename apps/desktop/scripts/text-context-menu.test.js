const test = require("node:test");
const assert = require("node:assert/strict");
const { buildTextContextMenuTemplate } = require("../src/text_context_menu.js");

test("selected desktop output exposes copy only", () => {
  assert.deepEqual(
    buildTextContextMenuTemplate({
      isEditable: false,
      selectionText: "selected output",
      editFlags: { canCopy: true }
    }),
    [{ role: "copy", enabled: true }]
  );
});

test("unselected desktop output does not open an empty menu", () => {
  assert.deepEqual(
    buildTextContextMenuTemplate({ isEditable: false, selectionText: "" }),
    []
  );
});

test("desktop input always exposes paste and standard editing roles", () => {
  const template = buildTextContextMenuTemplate({
    isEditable: true,
    selectionText: "",
    editFlags: { canPaste: true, canSelectAll: true }
  });
  const roles = template.map((item) => item.role).filter(Boolean);

  assert.deepEqual(roles, ["undo", "redo", "cut", "copy", "paste", "delete", "selectAll"]);
  assert.equal(template.find((item) => item.role === "paste").enabled, true);
  assert.equal(template.find((item) => item.role === "copy").enabled, false);
});
