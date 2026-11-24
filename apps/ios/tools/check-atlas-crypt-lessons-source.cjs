// Source/analytic contracts only; neither Swift nor Android scenes are executed.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const original = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"], {cwd: root, encoding: "utf8"});
const native = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const source = original("EnteroendocrineSignalStoryView"), signal = native("CryptSignalDrawing"), stem = native("CryptStemDrawing");
const numbers = s => [...s.matchAll(/-?(?:\d+\.?\d*|\.\d+)f?/g)].map(m => Number(m[0].replace(/f$/, "")));
const sourceRoutes = [...source.matchAll(/cubicTo\(([^)]+)\)/g)].map(m => numbers(m[1]));
const nativeRoutes = [...signal.matchAll(/kind: \.cubic, points: \[([^\]]+)\]/g)].map(m => numbers(m[1]).map((v, i) => i % 2 ? v : v - 100));
assert.equal(sourceRoutes.length, 3); assert.deepEqual(nativeRoutes, sourceRoutes);
assert.ok(signal.includes("draw($0 - 100, $1)")); assert.ok(signal.includes("local.translateBy(x: -100, y: 0)"));
const sourceQuads = [...source.matchAll(/quadTo\(([^)]+)\)/g)].map(m => numbers(m[1]));
const shape = signal.slice(signal.indexOf("for (cx, cy, x, y) in"), signal.indexOf("body.closeSubpath()"));
const swiftQuads = [...shape.matchAll(/\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)/g)].map(m => m.slice(1).map(Number));
assert.equal(sourceQuads.length, 5); assert.deepEqual(swiftQuads, sourceQuads);
for (const token of ["Self.centers[21]", "Double(i) * 0.19 + 0.43 * t", "0.49 + 0.48 * p", "0.66 + 0.16 * Double(i)",
  "0.76 + 0.11 * Double(i)", "0.07, 0.97", "enteroendocrine_signal_basal", "enteroendocrine_signal_hormone"]) assert.ok(signal.includes(token), token);
for (const token of ["Self.centers[14]", "Self.centers[13]", "panethBody(active: false)", "Self.cellSpan * 0.46",
  "Self.ease(t, 0.08, 0.65)", "Self.ease(t, 0.61, 0.94)", "15.5 - 0.52 * (1 - p)",
  "26.5 - Double(i) + Self.ease(t) * 0.65", "p > 0.52 ? 0xCFDF9F : 0xB5D5AA", "Double(i & 1)",
  "local.translateBy(x: 0, y: 10)", "local.translateBy(x: 0, y: -10)"]) assert.ok(stem.includes(token), token);
const stemSource = original("IntestinalStemRenewalStoryView");
for (const token of ["val stemSlot = 14", "val endocrineSlot = 21"]) assert.ok(original("CryptWallArt").includes(token));
assert.ok(stemSource.includes("26.5f - i + ease(t) * .65f"));
const ease = (t, a = 0, b = 1) => { const p = Math.max(0, Math.min(1, (t - a) / (b - a))); return p * p * (3 - 2 * p); };
let samples = 0;
for (let step = 0; step <= 120; step++) {
  const t = step / 120;
  for (let i = 0; i <= 2; i++) {
    const migration = 15.5 + (26.5 - i - 15.5) * ease(t, i * 0.085, 0.86 + i * 0.07);
    const mature = 26.5 - i + ease(t) * 0.65;
    assert.ok(migration >= 15.5 && migration <= 26.5 && mature >= 24.5 && mature <= 27.15 + 1e-12);
    const blood = 0.49 + 0.48 * ease(t, i * 0.12, 0.76 + 0.12 * i);
    assert.ok(blood >= 0.49 && blood <= 0.97 + 1e-12); samples++;
  }
}
const view = native("CryptLessonView");
for (const token of ["atlas-function-enteroendocrine-lumen-signal-art", "atlas-function-intestinal-stem-renewal-art", "kind == .endocrine ? 21 : 14"]) assert.ok(view.includes(token));
console.log("Source-only crypt lessons: three local cubics, five cell quadratics, original niche/signal/stage contracts and " + samples + " analytic migration/blood samples. No Swift/native acceptance.");
