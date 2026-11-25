// Source/analytic audit only; no Swift, Android or native scene execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const original = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + "StoryView.kt"], {cwd: root, encoding: "utf8"});
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const source = original("LeydigEndocrine"), leydig = read("LeydigDrawing"), theca = read("ThecaDrawing"), thecaSource = original("ThecaCooperation");
const numbers = s => [...s.matchAll(/-?(?:\d+\.?\d*|\.\d+)f?/g)].map(m => Number(m[0].replace(/f$/, "")));
const expected = [...source.matchAll(/cubicTo\(([^)]+)\)/g)].map(m => numbers(m[1]));
const cell = [...leydig.matchAll(/addCurve\(to: CGPoint\(x: (-?[\d.]+), y: (-?[\d.]+)\), control1: CGPoint\(x: (-?[\d.]+), y: (-?[\d.]+)\), control2: CGPoint\(x: (-?[\d.]+), y: (-?[\d.]+)\)\)/g)]
  .map(m => [Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]), Number(m[1]), Number(m[2])]);
const routes = [...leydig.matchAll(/kind: \.cubic, points: \[([^\]]+)\]/g)].map(m => numbers(m[1]));
assert.equal(expected.length, 9); assert.deepEqual([...cell, ...routes], expected);
const local = [...leydig.matchAll(/kind: \.quad, points: \[([^\]]+)\]/g)].map(m => numbers(m[1]));
assert.deepEqual(local, [[155, 180, 132, 172]]);
for (const token of ["leydigRoute(G.lh, t, input: true)", "leydigRoute(G.blood, t, input: false)", "leydigRoute(G.local, t, input: false)",
  "Double(i) * .pi / 8", "gx * 0.73, gy * 0.75", "205 * (1 - t)", "12 + 10 * t", "x + 10 + 8 * t", "gonadal_story_art_educational"]) assert.ok(leydig.includes(token), token);
for (const token of ["arcTo(vascularArc, -146f, 124f, true)", "quadTo(219f, 135f, 221f, 149f)", "ring(85f, 25)", "ring(63f, 32)"]) assert.ok(thecaSource.includes(token), token);
for (const token of ["radius: 85, startAngle: .degrees(-146), endAngle: .degrees(-22)", "CGPoint(x: 221, y: 149), control: CGPoint(x: 219, y: 135)",
  "0..<25", "0..<32", "min(1, t / 0.72)", "0.35 + 0.65 * reveal", "221 - 24 * t * t * (3 - 2 * t)", "(t - 0.22) / 0.56",
  "200 * (1 - crossing)", "0x135669", "0x965412", "gonadal_story_art_educational"]) assert.ok(theca.includes(token), token);
const keys = [...new Set([...(source + thecaSource).matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
let samples = 0;
for (let i = 0; i <= 120; i++) {
  const t = i / 120, eased = t * t * (3 - 2 * t), x = 221 - 24 * eased;
  const crossing = Math.max(0, Math.min(1, (t - .22) / .56));
  assert.ok(x >= 197 && x <= 221 && crossing >= 0 && crossing <= 1 && 1 - crossing >= 0);
  assert.ok(Math.floor(205 * (1 - t)) >= 0 && Math.floor(200 * (1 - crossing)) >= 0); samples++;
}
assert.equal(221 - 24, 197);
console.log("Source-only gonadal audit: nine cubics, local quadratic, arc/quadratic source track, distinct symbols/routes, " + keys.length + " bilingual labels and " + samples + " analytic handoff/fade samples. No native acceptance.");
