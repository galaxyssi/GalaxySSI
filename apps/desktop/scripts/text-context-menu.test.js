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

test("loaded images expose a real image-copy command instead of copying a file name", () => {
  let copies = 0;
  const menu = buildTextContextMenuTemplate({ mediaType: "image", hasImageContents: true },
    { copyImage: () => copies++, copyImageLabel: "Copy Image" });
  assert.equal(menu.length, 1); assert.equal(menu[0].label, "Copy Image");
  menu[0].click(); assert.equal(copies, 1);
});
test("unloaded images and editable controls do not get a broken image-copy item", () => {
  const actions = { copyImage: () => assert.fail("no image") };
  assert.deepEqual(buildTextContextMenuTemplate({ mediaType: "image", hasImageContents: false }, actions), []);
  assert.equal(buildTextContextMenuTemplate({ isEditable: true, mediaType: "image", hasImageContents: true }, actions)
    .some((item) => item.label === "Copy Image"), false);
});
