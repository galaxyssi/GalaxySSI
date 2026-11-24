// Source formula and analytic checks only; not native/Android rendering or XCTest.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMuscleSatelliteRenewalStoryView.kt"], {cwd: root, encoding: "utf8"});
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const geometry = read("SatelliteGeometry"), drawing = read("SatelliteDrawing");
const normalize = s => s.replace(/(\d)f\b/g, "$1").replace(/(^|[^\w])\.(\d)/g, (_, before, digit) => before + "0." + digit).replace(/\bCELL_X\b/g, "180").replace(/\s+/g, "");
const kotlinCurves = text => [...text.matchAll(/profile\.cubicTo\(([^)]+)\)/g)].map(m => m[1].split(",").map(normalize));
const swiftCurves = text => [...text.matchAll(/p\.addCurve\(to: CGPoint\(x: ([^,]+), y: ([^)]+)\), control1: CGPoint\(x: ([^,]+), y: ([^)]+)\), control2: CGPoint\(x: ([^,]+), y: ([^)]+)\)\)/g)]
  .map(m => [m[3], m[4], m[5], m[6], m[1], m[2]].map(normalize));
const profile = kotlinCurves(source.slice(source.indexOf("private fun cellProfile"), source.indexOf("private fun paintCell")));
assert.equal(profile.length, 4); assert.deepEqual(swiftCurves(geometry.slice(geometry.indexOf("static func cell"), geometry.indexOf("static func sarcolemma"))), profile);
const division = kotlinCurves(source.slice(source.indexOf("private fun division"), source.indexOf("private fun renewal"))).map(a => a.map(s => s.replace(/\brx\b/g, "30")));
assert.equal(division.length, 4); assert.deepEqual(swiftCurves(geometry.slice(geometry.indexOf("static func dividing"))), division);
for (const token of ["G.progress(t, 0.22, 0.88)", "G.progress(t, 0.12, 0.75)", "G.progress(t, 0.75, 0.97)",
  "G.progress(t, 0.06, 0.88)", "G.progress(t, 0.43, 0.93)", "clipped.clip(to: path)", "tail = max(0, head - 0.31)",
  "G.branchLamina", "G.lamina(107, 43, 247, 54 * (1 - merge), span: 54)", "202 - 0.45 * rise", "y + 7, 0x966237"]) assert.ok(drawing.includes(token), token);
for (const token of ["center - 0.67 * width", "center - 0.68 * width", "center + 0.68 * width", "center + 0.67 * width", "UInt32(Int(a + (b - a) * t))"]) assert.ok(geometry.includes(token), token);
const keys = [...new Set([...source.matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
const progress = (t, a, b) => { const p = Math.max(0, Math.min(1, (t - a) / (b - a))); return p * p * (3 - 2 * p); };
let samples = 0;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120, state = progress(t, .22, .88), pinch = progress(t, .12, .75), settle = progress(t, .06, .88), merge = progress(t, .43, .93);
  for (const [rx, ry] of [[36 + 3 * state, 13 + 11 * state], [30 - 3 * progress(t, .75, .97), 22 - progress(t, .75, .97)],
    [27 + 7 * settle, 21 - 8 * settle], [27 + 11 * settle, 21 - 7 * settle]]) { assert.ok(rx > 0 && ry > 0); samples++; }
  assert.ok((24 - 2 * pinch) * (1 - pinch) >= 0 && 54 * (1 - merge) >= 0);
  assert.ok(142 - 35 * settle < 218 + 29 * settle);
}
console.log("Source-only satellite audit: four profile/four division curve formulas, five-stage/membrane/lamina contracts and " + keys.length + " bilingual keys; " + samples + " analytic cell sizes. No native acceptance.");
