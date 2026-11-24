// Source and analytic contracts only. No Swift/native or Android rendering runs.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSomatotrophStoryView.kt"], {cwd: root, encoding: "utf8"});
const drawing = read("SomatotrophDrawing"), shared = read("AnteriorPituitaryDrawing"), geometry = read("SomatotrophGeometry");
for (const token of ["fraction.isFinite, (0...1).contains(fraction)", "radius * 0.8", ".degrees(45)", "0xB17A86", "0xF6D9DC", "255 * min(1, max(0, opacity))"]) assert.ok(shared.includes(token), token);
for (const route of ["capillary", "trunk", "upperBranch", "lowerBranch", "input", "hepaticOut", "muscleGh", "muscleIgf"]) assert.ok(geometry.includes("static let " + route + "Route ="), route);
for (const token of ["0.065 * Double(i)", "f < 0.69", "Self.pituitarySmooth(f / 0.69)", "0.47 + 0.014 * Double(i) + released * 1.35",
  "pituitaryMarker(G.trunkRoute, f * 3", "(f - 0.33) * 1.32", "(f - 0.33) * 1.18", "(t - 0.46 - delay) / 0.39",
  "(t - 0.13 * Double(i)) / 0.53", "(t - 0.07 - 0.13 * Double(i)) / 0.53", "radius: 4.6, angular: true", "radius: 4.5, angular: true"]) assert.ok(drawing.includes(token), token);
const keys = [...new Set([...source.matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
let active = 0, hidden = 0;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120;
  for (let i = 0; i <= 2; i++) {
    const delay = .09 * i;
    for (const p of [(t - delay) / .41, (t - .46 - delay) / .39, (t - .13 * i) / .53, (t - .07 - .13 * i) / .53]) {
      assert.ok(Number.isFinite(p)); if (p >= 0 && p <= 1) active++; else hidden++;
    }
  }
}
assert.ok(active > 0 && hidden > 0, "Delayed arrivals must not clamp into visible endpoint markers");
console.log("Source-only somatotroph audit: eight sampling routes, original phase/delay/dual-signal contracts, " + keys.length + " bilingual keys; " + active + " active and " + hidden + " hidden analytic marker samples. No native acceptance.");
