// Source/analytic checks only; no native/Swift/Android renderer executes.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const all = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMastAndTCellArt.kt"], {cwd: root, encoding: "utf8"});
const source = all.slice(all.indexOf("internal class HealthAtlasMastCellStoryView"));
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const geometry = read("MastGeometry"), drawing = read("MastDrawing");
function sourceArray(name) { return source.match(new RegExp("private val " + name + " = floatArrayOf\\(([^)]+)\\)"))[1].split(",").map(s => s.trim()).filter(Boolean).map(s => Number(s.replace(/f$/, ""))); }
const originalPoints = sourceArray("granules"), nativePoints = [...geometry.matchAll(/\.init\(x: (-?[\d.]+), y: (-?[\d.]+)\)/g)].flatMap(m => m.slice(1).map(Number));
assert.equal(originalPoints.length, 44); assert.deepEqual(nativePoints, originalPoints);
for (const name of ["spokesX", "spokesY", "releaseRim"]) {
  const text = geometry.match(new RegExp(name + " = (\\[[^\\]]+\\])"))[1]; assert.deepEqual(JSON.parse(text), sourceArray(name));
}
const normalize = s => s.replace(/(\d)f\b/g, "$1").replace(/\s+/g, "");
const gut = source.slice(source.indexOf("private val gutTop"), source.indexOf("private val residentColors"));
const expected = [...gut.matchAll(/cubicTo\(([^)]+)\)/g)].map(m => m[1].split(",").map(normalize));
const actual = [...geometry.matchAll(/p\.addCurve\(to: CGPoint\(x: ([^,]+), y: ([^)]+)\), control1: CGPoint\(x: ([^,]+), y: ([^)]+)\), control2: CGPoint\(x: ([^,]+), y: ([^)]+)\)\)/g)].map(m => [m[3], m[4], m[5], m[6], m[1], m[2]].map(normalize));
assert.equal(expected.length, 2); assert.deepEqual(actual, expected);
for (const token of ["(4...9).contains(i)", "0.04 + 0.071 * Double(i - 4)", "G.fusionPhase(i - 4)", "0.62 + 0.073 * Double(i)",
  "0.02 + 0.034 * Double(i), 0.74 + 0.042 * Double(i)", "111 + 1.16 * G.releaseRim[i]", "G.granules[i + 4].y", "2 + 1.8 * out - 1.65 * f", "mastReleased(1, spread: t)"]) assert.ok(drawing.includes(token), token);
const keys = [...new Set([...source.matchAll(/R\.string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
const ease = (t, a, b) => { const f = Math.min(1, Math.max(0, (t-a)/(b-a))); return f*f*(3-2*f); };
let samples = 0;
for (let i = 0; i < 6; i++) {
  const fusion = .31 + .074*i;
  for (const t of [...Array.from({length:121}, (_, n) => n/120), fusion]) {
    const inside = ease(t, .04 + .071*i, fusion), outside = ease(t, fusion, .62 + .073*i);
    assert.ok(!(inside < 1 && outside > 0), "Internal and released granule must not duplicate");
    for (const spread of [0, 1]) assert.ok(2 + 1.8*outside - 1.65*spread > 0); samples++;
  }
}
console.log("Source-only mast audit: exact 22 granules/six release vectors, two parameterized gut curves, " + keys.length + " bilingual keys and " + samples + " analytic nonduplicating release samples. No native acceptance.");
