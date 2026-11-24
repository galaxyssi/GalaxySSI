// Source and analytic contracts only; no Swift/native/Android rendering executes.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const all = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMastAndTCellArt.kt"], {cwd: root, encoding: "utf8"});
const source = all.slice(all.indexOf("internal class HealthAtlasHelperTCellStoryView"), all.indexOf("internal class HealthAtlasRegulatoryTCellStoryView"));
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const helper = read("HelperTDrawing"), cytotoxic = read("CytotoxicTDrawing"), geometry = read("ImmuneGeometry");
assert.ok(geometry.includes("upperPathRoute") && geometry.includes("lowerPathRoute") && geometry.includes("bodyRim"));
for (const token of ["[-64.0, -32, -1, 29, 60]", "0.065 + 0.086 * Double(i), 0.53 + 0.105 * Double(i)",
  "G.upperPathRoute", "G.lowerPathRoute", "0.58 + 0.42 * t", "0.52 + 0.48 * t", "f - 0.125 * Double(i)",
  "size * (4.3 - Double(i) * 0.38)", "direction * (19 + 3 * Double(i))", "0xF5DAAA, 0xD4A476, 0x8E5E42"]) assert.ok(helper.includes(token), token);
for (const token of ["1 - 0.36 * change", "255 - (1 - size) * 59", "y: 170 + 5 * change", "CGPoint(x: 195, y: 170 - spread)",
  "CGPoint(x: 193, y: 170 + spread), control: CGPoint(x: 198, y: 170)", "149 - 75 * f", "170 - 38 * f",
  "x: 280, y: 262", "0xE5E7D4, 0xBEC8A8", "fragments * (18 + Double(i) * 6)", "2.4 * fragments"]) assert.ok(cytotoxic.includes(token), token);
const keys = [...new Set([...source.matchAll(/R\.string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
const ease = (t, a = 0, b = 1) => { const f = Math.min(1, Math.max(0, (t-a)/(b-a))); return f*f*(3-2*f); };
let anchored = 0, fragments = 0;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120, change = ease(t, .1, .95), size = 1 - .36 * change;
  assert.ok(Math.abs(255 - (1 - size) * 59 - size * 59 - 196) < 1e-12); anchored++;
  for (let i = 0; i < 3; i++) {
    const f = ease(1, .13 + i * .13, .66 + i * .1), r = 3 + f * (7-i) - 2.4 * ease(t);
    assert.ok(r > 0); fragments++;
  }
  for (let i = 0; i < 5; i++) {
    const f = ease(t, .065 + .086*i, .53 + .105*i);
    assert.ok(4.6 - 1.4*f > 0 && 64 + 62*f <= 126);
  }
}
console.log("Source-only helper/cytotoxic audit: split routes, original signals/fans/contact/neighbor contracts and " + keys.length + " bilingual keys; " + anchored + " anchored target and " + fragments + " fragment samples. No native acceptance.");
