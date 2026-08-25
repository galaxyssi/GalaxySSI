const test = require("node:test");
const assert = require("node:assert/strict");
const { frameAt } = require("../src/renderer/connecting-animation.js");

test("connecting animation preserves a fixed ten-cell readout", () => {
  const frames = Array.from({ length: 72 }, (_, tick) => frameAt(tick));
  assert.ok(frames.some((frame) => frame.characters !== "CONNECTING"));
  assert.ok(frames.some((frame) => frame.cursorVisible));
  assert.ok(frames.every((frame) => frame.characters.length === 10));
});

test("reduced motion keeps the connecting readout static", () => {
  assert.deepEqual(frameAt(19, true), { characters: "CONNECTING", cursorVisible: false });
});
