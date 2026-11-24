// Source/analytic contracts only; no Swift/native/Android scenes execute.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGonadotrophStoryView.kt"], {cwd: root, encoding: "utf8"});
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const drawing = read("GonadotrophDrawing"), geometry = read("GonadotrophGeometry");
for (const route of ["input", "trunk", "ovarianBranch", "testisBranch", "ovarianFsh", "ovarianLh", "testisFsh", "testisLh"]) assert.ok(geometry.includes("static let " + route + "Route ="), route);
for (const token of ["f - 0.17, f", "f / 0.41", "(f - 0.41) / 0.59", "f + 0.04, Self.fshSignal", "f - 0.04, Self.lhSignal",
  "radius: 4.6, angular: true", "G.ovarianFshRoute, 0.62", "G.ovarianLhRoute, 0.70", "G.testisFshRoute, 0.66", "G.testisLhRoute, 0.82",
  "(t - 0.09 * Double(i)) / 0.56", "(t - 0.08 - 0.09 * Double(i)) / 0.54", "(t - 0.11 * Double(i)) / 0.49",
  "(t - 0.10 - 0.09 * Double(i)) / 0.53", "i != 9 && i != 10", "(t - 0.59 - 0.085 * Double(i)) / 0.38",
  "255 * (1 - 0.7 * f)", "122 * inner", "121 * outer"]) assert.ok(drawing.includes(token), token);
assert.ok(read("IsletLessonView").includes("sweep.isFinite, sweep != 0"));
const keys = [...new Set([...source.matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
let visible = 0, hidden = 0;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120;
  for (let i = 0; i < 3; i++) {
    const f = (t - i * .14) / .66;
    for (const p of [f / .41, (f - .41) / .59]) for (const marker of [p + .04, p - .04]) {
      assert.ok(Number.isFinite(marker)); if (marker >= 0 && marker <= 1) visible++; else hidden++;
    }
    for (const p of [(t - .09 * i) / .56, (t - .08 - .09 * i) / .54, (t - .11 * i) / .49, (t - .1 - .09 * i) / .53]) {
      assert.ok(Number.isFinite(p)); if (p >= 0 && p <= 1) visible++; else hidden++;
    }
  }
}
assert.ok(visible > 0 && hidden > 0);
console.log("Source-only gonadotroph audit: eight routes, paired shape/phase separation, target layers, zero-span guard and " + keys.length + " bilingual keys; " + visible + " visible / " + hidden + " hidden analytic markers. No native acceptance.");
