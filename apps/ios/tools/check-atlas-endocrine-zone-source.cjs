// Source/analytic contracts, not native execution, physiology validation or UI acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const original = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + "StoryView.kt"], {cwd: root, encoding: "utf8"});
const read = file => fs.readFileSync(path.join(root, "apps/ios", file), "utf8");
const cortexSource = original("AdrenalCortex"), cSource = original("ThyroidCalcitonin");
const cortex = read("GalaxySSI/GalaxySSIHealthAtlasAdrenalCortexDrawing.swift"), c = read("GalaxySSI/GalaxySSIHealthAtlasCalcitoninDrawing.swift");
for (const [key, expected] of [["top", [102, 145, 216]], ["bottom", [145, 216, 261]]]) {
  const match = cortexSource.match(new RegExp("private val " + key + " = floatArrayOf\\(([^)]+)\\)"));
  assert.ok(match); assert.deepEqual(match[1].split(",").map(s => Number(s.trim().replace(/f$/, ""))), expected);
  assert.ok(cortex.includes("[" + expected.map(n => n + ".0").join(", ") + "]"));
}
for (const [name, text] of [["zoneFill", "[0xEBCA8B, 0xE9AA8C, 0xD6A0AE]"], ["zoneInk", "[0x856121, 0xA5553F, 0x834A6F]"], ["zoneMuted", "[0xEFDFBE, 0xEAD1C1, 0xE5CDD6]"]]) {
  assert.ok(cortex.includes(name + ": [UInt32] = " + text));
  const values = [...cortexSource.match(new RegExp("private val " + name + " = longArrayOf\\(([^)]+)\\)"))[1].matchAll(/0xff([a-f0-9]{6})/g)].map(m => m[1].toUpperCase());
  assert.deepEqual(values, [...text.matchAll(/0x([A-F0-9]+)/g)].map(m => m[1]));
}
for (const token of ["step == 4", "0.03 + 0.36 * t", "0.51 + 0.08 * Double(i) + 0.63 * t", "local.translateBy(x: 180, y: 226)",
  'zoneTitle = ["glomerulosa", "fasciculata", "reticularis"]', 'zoneHormone = ["aldosterone", "cortisol", "androgen"]', "0x55FFF8EB"]) assert.ok(cortex.includes(token), token);
for (const token of ["36 + 315 * t", "t * 1.37 - Double(i) * 0.17", "dividingBy: 0.63", "10 - 6.6 * t", "27 - 14 * t",
  "sin(f * 3.14159)", "Double(i) * 0.349066", "c_cell_art_context_main"]) assert.ok(c.includes(token), token);
const keys = [...new Set([...(cSource + cortexSource).matchAll(/string\.(health_atlas_\w+)/g)].map(m => m[1]))];
for (const locale of ["en", "zh-Hans"]) {
  const table = read("GalaxySSI/" + locale + ".lproj/AtlasComplete.strings");
  for (const key of keys) assert.ok(table.includes(JSON.stringify(key) + " = "), locale + ":" + key);
}
let samples = 0;
for (let frame = 0; frame <= 120; frame++) {
  const t = frame / 120;
  assert.ok(10 - 6.6 * t > 0 && 27 - 14 * t > 0);
  for (let i = 0; i < 3; i++) {
    const position = (.51 + .08 * i + .63 * t) % 1;
    assert.ok(position >= 0 && position < 1); samples++;
  }
}
console.log("Source-only endocrine-zone audit: exact layer/color arrays, dynamic stage contracts, " + keys.length + " bilingual labels and " + samples + " analytic drainage positions. No native acceptance.");
