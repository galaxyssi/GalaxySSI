// Source/analytic audit only; no Swift/Android scenes or native tests execute.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasLangerhansSentinelStoryView.kt"], {cwd: root, encoding: "utf8"});
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const drawing = read("LangerhansDrawing"), geometry = read("LangerhansGeometry");
const normalize = s => s.replace(/f\b/g, "").replace(/\s+/g, "");
const expected = [...source.matchAll(/callout\(c, string\.health_atlas_langerhans_sentinel_art_(\w+), ([^)]+)\)/g)].map(m => [m[1], ...m[2].split(",").map(normalize)]);
const actual = [...drawing.matchAll(/langerhansCallout\("(\w+)", ([^)]+)\)/g)].map(m => [m[1], ...m[2].split(",").map(normalize)]);
assert.equal(expected.length, 11); assert.deepEqual(actual, expected);
for (const name of ["diamond", "body", "tissueBranches", "detailBranches", "displayBranches", "keratinocyte"]) assert.ok(geometry.includes("static let " + name + " = Path"));
for (const token of ["portrait == .tissue", "inTissue ? 74.0 : 52.0", "-length - 15 * reach", "15 - length - 7 * reach",
  "CGPoint(x: -47, y: -59 - 6 * reach)", "CGPoint(x: -58, y: -39 - 6 * reach)", "portrait == .display",
  "row == 2 && col == 3", ".degrees(-24)", "0.40 + 0.14 * wave(t)", "0.5 + 0.5 * wave(t - 0.25)",
  "reach > 0.68", "close >= 0.86", "241 - 19 * close * close * (3 - 2 * close)", "1.2 / rx", "1.15 / size"]) assert.ok(drawing.includes(token), token);
const keys = [...new Set([...source.matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
let samples = 0, previous = 241;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120, reach = .5 + .5 * Math.sin((t - .25) * 2 * Math.PI), close = Math.min(1, t / .58);
  const x = 241 - 19 * close * close * (3 - 2 * close);
  assert.ok(reach >= -1e-12 && reach <= 1 + 1e-12 && x <= previous + 1e-12 && x >= 222 - 1e-12); previous = x;
  for (const length of [74, 52]) {
    assert.ok(Number.isFinite(-length - 15 * reach) && 15 - length - 7 * reach < 0); samples++;
  }
}
console.log("Source-only Langerhans audit: six path groups, eleven original callouts, portrait/layering/reach contracts and " + keys.length + " bilingual keys; " + samples + " analytic tip samples. No native/pixel acceptance.");
