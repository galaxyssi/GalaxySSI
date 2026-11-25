// Source and independent analytic audit only. Does not execute Swift or native UI.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const native = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const original = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"], {cwd: root, encoding: "utf8"});
const model = native("Physiology"), text = native("PhysiologyText"), drawing = native("MaterialResponseDrawing"), view = native("MaterialResponseView");
for (const token of ["loadNewtons * (100 + positionPercent) / 200", "loadNewtons * (100 - positionPercent) / 200",
  "10 * loadNewtons / areaSquareCentimetres", "10 * loadNewtons / 40", "range: 0...800, initial: 400",
  "range: -100...100, initial: 0", "range: 0...80, initial: 40", "range: 10...90, initial: 40",
  'case "pelvis": return .pelvicSupport', 'case "subcutaneous-tissue": return .cushionContactPressure',
  "self == .pelvicSupport || self == .cushionContactPressure { return 1 }", "!.leftNewtons", "!.rightNewtons",
  "!.pressureKilopascals", "!.referenceKilopascals"]) assert(model.includes(token), token);
for (const token of ["load * (100.0 + positionPercent) / 200.0", "supportReaction(input(0), -input(1))",
  "10.0 * values[0] / values[1]", "10.0 * input(0) / 40.0"]) assert(original("Physiology").includes(token), token);
for (const token of ['"pelvis_model_left_value"', '"cushion_model_reference_value"', '"model_pelvicSupport_formula"',
  '"model_cushionContactPressure_formula"']) assert(text.includes(token));
assert(native("PhysiologyPanel").includes("model.kind.hasMaterialResponse"));
assert(native("State").includes("Physiology.restore(id, inputs: entries[id]?.physiologyInputs)"));
for (const token of ["art.pelvicSupport(model)", "art.cushionContact(model)", '"atlas-pelvic-support"', '"atlas-cushion-contact"']) assert(view.includes(token));
for (const token of ["170 + 87 * model.input(1) / 100", "121 - (8 + 23 * force / 800)", "10 + 49 * area / 90",
  "(60 + 190 * pressure / 80).rounded() / 255", "y2 >= y1 ? 1 : -1"]) assert(drawing.includes(token), token);
let samples = 0;
for (const load of [0, 40, 400, 800]) for (let position = -100; position <= 100; position++) {
  const right = load * (100 + position) / 200, left = load * (100 - position) / 200;
  assert(Math.abs(left + right - load) < 1e-10); assert(left >= 0 && right >= 0);
  const x = 170 + 87 * position / 100; assert(x >= 83 && x <= 257); samples++;
}
for (let load = 0; load <= 80; load++) for (let area = 10; area <= 90; area++) {
  const pressure = 10 * load / area, reference = 10 * load / 40;
  assert(pressure >= 0 && pressure <= 80); assert(reference >= 0 && reference <= 20);
  if (area === 40) assert.equal(pressure, reference);
  const alpha = Math.round(60 + 190 * pressure / 80); assert(alpha >= 60 && alpha <= 250); samples++;
}
console.log(`Load-transfer source contracts and ${samples} independent analytic input samples audited. Not Swift execution, type checking or native acceptance.`);
