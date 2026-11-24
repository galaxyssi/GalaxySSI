// Source/analytic audit only; no Android/Swift renderer or native tests execute.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const original = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"], {cwd: root, encoding: "utf8"});
const native = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const source = original("DistalTubularStoryView"), distal = native("DistalTubularDrawing"), uro = native("UrothelialDrawing");
const shell = source.slice(source.indexOf("private val shell"), source.indexOf("private val basalFolds")).replaceAll("APICAL_Y", "124f").replaceAll("BASAL_Y", "242f");
const expected = [...shell.matchAll(/quadTo\(([^)]+)\)/g)].map(m => m[1].split(",").map(s => Number(s.trim().replace(/f$/, ""))));
const actual = [...distal.slice(distal.indexOf("var shell"), distal.indexOf("gradient(shell")).matchAll(/addQuadCurve\(to: CGPoint\(x: ([^,]+), y: ([^)]+)\), control: CGPoint\(x: ([^,]+), y: ([^)]+)\)\)/g)].map(m => [Number(m[3]), Number(m[4]), Number(m[1]), Number(m[2])]);
assert.equal(expected.length, 4); assert.deepEqual(actual, expected);
for (const token of ["distalGate(187, 124, 54", "distalGate(145, 242, 66", "distalGate(248, 242, 36",
  "distalTransit(205, 270, t)", "distalTransit(268, 211, t)", "distalTransit(210, 271, t)",
  "t * 1.35 - 0.30", "to > from ? to - 7 : to + 7", "y + 3.5 - UIFont.systemFont(ofSize: 10).ascender"]) assert.ok(distal.includes(token), token);
const uroSource = original("UrothelialStoryView");
for (const token of ["const val SAMPLES = 48", "const val UMBRELLA_SPAN = 8", "27f * (1f - stretch)", "13f - 10f * stretch", "67f - 51f * approach"]) assert.ok(uroSource.includes(token), token);
for (const token of ["0.12 * s", "0.12 + 0.68 * s", "0.80 + 0.20 * s", "1 - s", "252 + 62 * stretch",
  "Double($0) * 4 * .pi / 48", "Double($0 % 8) * .pi / 8", "top == 0 ? g.surface : g.fold",
  "stride(from: 0, to: 48, by: 4)", "stride(from: 0, to: 48, by: 6)", "stride(from: 0, to: 48, by: 8)",
  "gap = 67 - 51 * approach", "0x287565"]) assert.ok(uro.includes(token), token);
function stretch(step, t) { const s = t * t * (3 - 2 * t); return step === 0 ? .12 * s : step === 1 ? .12 + .68 * s : step === 2 ? .8 + .2 * s : 1 - s; }
for (let step = 0; step < 3; step++) assert.ok(Math.abs(stretch(step, 1) - stretch(step + 1, 0)) < 1e-12);
assert.equal(stretch(3, 1), stretch(0, 0));
let vertices = 0, tracers = 0;
for (let step = 0; step < 4; step++) for (let sample = 0; sample <= 120; sample++) {
  const t = sample / 120, s = stretch(step, t), width = 252 + 62 * s;
  const top = 34 - 17 * s, middle = top + 30 - 12 * s, basal = middle + 18 - 6 * s;
  const xs = [], ys = [];
  for (let i = 0; i <= 48; i++) {
    const x = 180 + width * (i / 48 - .5), fold = 174 + 19 * s + 27 * (1 - s) * Math.cos(i * 4 * Math.PI / 48);
    const surface = fold - (13 - 10 * s) * Math.sin((i % 8) * Math.PI / 8);
    assert.ok(x >= 0 && x <= 360 && surface < fold + top && top < middle && middle < basal && fold + basal + 23 < 360);
    xs.push(x); ys.push(surface); vertices++;
  }
  if (step === 2) for (let i = 5; i < 48; i += 7) {
    const approach = Math.max(0, Math.min(1, t * 1.36 - (i % 3) * .1)), gap = 67 - 51 * approach;
    const cx = Math.min(xs[48] - 12, Math.max(xs[0] + 5, xs[i] + 3 * Math.sin((t + i / 11) * 2 * Math.PI)));
    const index = Math.min(47, Math.floor((cx - xs[0]) / (width / 48))), p = (cx - xs[index]) / (xs[index + 1] - xs[index]);
    const atX = ys[index] + (ys[index + 1] - ys[index]) * p;
    assert.ok(ys[i] - gap + 3.5 < atX, "Tracer must remain lumen-side"); tracers++;
  }
}
console.log("Source-only renal-cell audit: four shell quadratics, distinct directional gates, continuous shared layer contours; " + vertices + " analytic vertices and " + tracers + " lumen-side tracer samples. No native/UI acceptance.");
