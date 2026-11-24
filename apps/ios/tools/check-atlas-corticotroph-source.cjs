// Source/analytic contract checks; no Swift/Android scene or native tests run.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCorticotrophStoryView.kt"], {cwd: root, encoding: "utf8"});
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const drawing = read("CorticotrophDrawing"), geometry = read("CorticotrophGeometry"), shared = read("AnteriorPituitaryDrawing");
assert.ok(source.includes("quadTo(253f, 198f, 289f, 224f)"));
assert.ok(geometry.includes("p.addQuadCurve(to: .init(x: 289, y: 224), control: .init(x: 253, y: 198))"));
const arc = geometry.slice(geometry.indexOf("static let cortexArcRoute"), geometry.indexOf("static let cortisolBlood"));
assert.ok(arc.includes("kind: .cubic") && arc.includes("kind: .quad"));
for (const token of ["clipped.clip(to: G.fasciculata)", "Int(255 * 0.34)", "f - 0.32, f, Self.cortisolSignal, 15",
  "0.19 + 0.077 * Double(i)", "(t - Double(i) * 0.095) / 0.56", "(t - Double(i) * 0.082) / 0.65",
  "radius: 4.1, angular: true", "(t - 0.64) / 0.31", "(t - 0.07 - 0.115 * Double(i)) / 0.36",
  "t - 0.43 - 0.115 * Double(i)", "exit * 1.25", "guard Self.cortisolTargets.count == 5"]) assert.ok(drawing.includes(token), token);
for (const token of ["let lower = min(1, max(0, start)), upper = min(1, max(0, end))", "guard upper > lower else { return }", "path.trimmedPath(from: lower, to: upper)"]) assert.ok(shared.includes(token));
const keys = [...new Set([...source.matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
const smooth = t => { const p = Math.max(0, Math.min(1, t)); return p * p * (3 - 2 * p); };
let segments = 0, injections = 0, transported = 0;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120, f = smooth((t - .07) / .84), start = Math.max(0, f - .32);
  assert.ok(start <= f && f <= 1 && f - start <= .32 + 1e-12); if (f > start) segments++;
  for (let i = 0; i <= 4; i++) {
    const entry = .19 + .077 * i, p = (t - .07 - .115 * i) / .36, exit = t - .43 - .115 * i;
    assert.ok(entry >= 0 && entry <= 1);
    if (p >= 0 && p <= 1) injections++;
    if (exit >= 0 && entry + exit * 1.25 <= 1) transported++;
    assert.ok(Math.abs((.07 + .115 * i + .36) - (.43 + .115 * i)) < 1e-12, "Injection/exit boundary must match");
  }
}
assert.ok(segments && injections && transported);
console.log("Source-only corticotroph audit: appended quadratic, four routes, exact clipped trace, five injection/exit contracts and " + keys.length + " bilingual keys; " + injections + " analytic injections. No native acceptance.");
