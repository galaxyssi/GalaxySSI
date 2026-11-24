// Source/analytic checks only, not execution of native or Android lessons.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const original = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"], {cwd: root, encoding: "utf8"});
const native = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const delta = native("DeltaSignalDrawing"), pp = native("PPSignalDrawing"), source = original("PancreaticPpStoryView");
const numbers = s => [...s.matchAll(/-?(?:\d+\.?\d*|\.\d+)f?/g)].map(m => Number(m[0].replace(/f$/, "")));
const tuples = text => [...text.matchAll(/\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+), (-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)/g)].map(m => m.slice(1).map(Number));
const cubics = text => [...text.matchAll(/cubicTo\(([^)]+)\)/g)].map(m => numbers(m[1]));
const deltaSource = original("PancreaticDeltaStoryView");
assert.equal(cubics(deltaSource).length, 5); assert.deepEqual(tuples(delta), cubics(deltaSource));
const ppSource = cubics(source); assert.equal(ppSource.length, 12);
assert.deepEqual(tuples(pp), ppSource.slice(0, 7));
const direct = [...pp.matchAll(/addCurve\(to: CGPoint\(x: (-?[\d.]+), y: (-?[\d.]+)\), control1: CGPoint\(x: (-?[\d.]+), y: (-?[\d.]+)\), control2: CGPoint\(x: (-?[\d.]+), y: (-?[\d.]+)\)\)/g)]
  .map(m => [Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]), Number(m[1]), Number(m[2])]);
assert.deepEqual(direct, ppSource.slice(7, 9));
const routes = [...pp.matchAll(/kind: \.cubic, points: \[([^\]]+)\]/g)].map(m => numbers(m[1]));
assert.deepEqual(routes, ppSource.slice(9));
const quads = [...source.matchAll(/quadTo\(([^)]+)\)/g)].map(m => numbers(m[1]));
const nativeQuads = [...pp.matchAll(/addQuadCurve\(to: CGPoint\(x: ([^,]+), y: ([^)]+)\), control: CGPoint\(x: ([^,]+), y: ([^)]+)\)\)/g)]
  .map(m => [Number(m[3]), Number(m[4]), Number(m[1]), Number(m[2])]);
assert.equal(quads.length, 9); assert.deepEqual(nativeQuads, quads);
for (const token of ["70 + 264 * t", "0.65 + 0.20 * t", "24 - 12 * t", "0...56", "15 - 10 * x", "wave(x * 4 - 0.6 * t)", "delta_local_art_lower"]) assert.ok(delta.includes(token), token);
for (const token of ["clipped.clip(to: stomach)", "t * 0.83 + Double(i) * 0.16", "t * 0.69 + 0.17 * Double(i)",
  "t * 0.64 + 0.23 * Double(i)", "pp_signal_art_uncinate", "pp_signal_art_regulators", "pp_signal_art_exocrine"]) assert.ok(pp.includes(token), token);
const labels = [...(delta + pp).matchAll(/label\("([^"]+)"/g)].map(m => "health_atlas_" + m[1]);
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of labels) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
let samples = 0;
for (let step = 0; step <= 120; step++) {
  const t = step / 120;
  for (let i = 0; i <= 56; i++) {
    const x = i / 56, amplitude = 15 - 10 * x;
    assert.ok(amplitude >= 5 && amplitude <= 15);
    assert.ok(Number.isFinite(amplitude * Math.sin((x * 4 - .6 * t) * 2 * Math.PI))); samples++;
  }
  for (let i = 0; i <= 2; i++) {
    const f = (t * .8 + i * .31) % 1;
    assert.ok(2.7 - f > 0 && (24 - 12 * t) * f >= 0);
  }
}
console.log("Source-only islet audit: 17 original cubics, nine quadratics, bilingual callouts, clipping/transport contracts and " + samples + " analytic waveform points. No native/pixel acceptance.");
