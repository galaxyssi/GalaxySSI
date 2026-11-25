// Source and analytic contracts only; no native/Swift/Android scenes execute.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const all = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMastAndTCellArt.kt"], {cwd: root, encoding: "utf8"});
const source = all.slice(all.indexOf("internal class HealthAtlasRegulatoryTCellStoryView"), all.indexOf("internal class HealthAtlasMastCellStoryView"));
const read = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const drawing = read("RegulatoryTDrawing"), shared = read("ImmuneDrawing");
for (const token of ["regulatoryResponse(t + 1, settling: 0", "regulatoryResponse(t + 2, settling: Self.ease(t, 0.05, 0.95)",
  "regulatoryResponse(t + 3, settling: 1", "23 - 18 * settling", "9 - 6 * settling", "5.5 - 3.5 * settling",
  "0...40", "stride(from: 40, through: 0, by: -1)", "f * 2.25 - 0.48 * phase", "1 - abs(2 * f - 1) * 0.48",
  "274 - 92 * entering", "296 - 19 * entering", "settling < 0.5", "0xD1E3B7, 0x87AA7C, 0x4C6F55"]) assert.ok(drawing.includes(token), token);
for (const token of ["lymphocyteRim", "cell.gradient(rim, -43, 43", "cell.stroke(rim, edge, 1.6)", "207, 43"]) assert.ok(shared.includes(token), token);
assert.ok(source.includes("A moving thread of activity, not a chart or a measured signal."));
const keys = [...new Set([...source.matchAll(/R\.string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", locale + ".lproj/AtlasComplete.strings"), "utf8");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
const ease = t => { const p = Math.min(1, Math.max(0, (t - .05) / .9)); return p * p * (3 - 2 * p); };
let points = 0;
for (let step = 0; step < 4; step++) for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120, phase = t + step, settling = step < 2 ? 0 : step === 2 ? ease(t) : 1;
  const spread = 23 - 18 * settling, half = 9 - 6 * settling;
  assert.ok(spread >= 5 && spread <= 23 && half >= 3 && half <= 9);
  for (let i = 0; i <= 40; i++) {
    const f = i / 40, y = 179 + spread * Math.sin((f * 2.25 - .48 * phase) * 2 * Math.PI) * (1 - Math.abs(2 * f - 1) * .48);
    assert.ok(y - half > 0 && y + half < 360); points++;
  }
}
assert.equal(ease(0), 0); assert.equal(ease(1), 1);
console.log("Source-only regulatory-T audit: exact phase/damping/entry contracts, shared lymphocyte and " + keys.length + " bilingual keys; " + points + " analytic ribbon points. No native/pixel acceptance.");
