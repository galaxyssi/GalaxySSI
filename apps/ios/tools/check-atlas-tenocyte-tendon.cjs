// Source and analytic pose audit; not Swift, drawing or native scene execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI");
const source = cp.execFileSync("git", ["show", "a81aa85a1c81e41ff19a032eabea1eddcd2371dc:apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasTenocyteTendonMatrixStoryView.kt"], {cwd: root, encoding: "utf8"});
const local = name => fs.readFileSync(path.join(app, "GalaxySSIHealthAtlasTenocyteTendon" + name + ".swift"), "utf8");
const geometry = local("Geometry"), drawing = local("Drawing"), norm = s => s.replace(/(\d)f\b/g, "$1").replace(/(^|[^\d])\.(\d)/g, "$10.$2").replace(/\s/g, "");
for (const [android, swift] of [["fiberPath", "fiber"], ["cellPath", "cell"]]) {
  const original = source.match(new RegExp("private fun " + android + "\\([^\\n]+\\) \\{([\\s\\S]*?)\\n    \\}"))[1];
  const native = geometry.match(new RegExp("static func " + swift + "\\([^\\n]+\\) -> Path \\{([\\s\\S]*?)\\n  \\}"))[1];
  const expected = [...original.matchAll(/(?:path|p)\.(moveTo|cubicTo|close)\(([^)]*)\)/g)].map(m => [m[1], ...m[2].split(",").filter(s => s.trim()).map(norm)]);
  const actual = [...native.matchAll(/p\.(move|addCurve|closeSubpath)\(([^\n]*)\)/g)].map(m => {
    const points = [...m[2].matchAll(/CGPoint\(x: ([^,]+), y: ([^)]+)\)/g)].map(p => [norm(p[1]), norm(p[2])]);
    return [{move: "moveTo", addCurve: "cubicTo", closeSubpath: "close"}[m[1]], ...(points.length > 1 ? [...points.slice(1).flat(), ...points[0]] : points.flat())];
  });
  assert.deepEqual(actual, expected, swift);
}
for (const [original, native] of [[".56f * eased", "0.56 * eased"], [".56f + .44f * eased", "0.56 + 0.44 * eased"], ["1f - eased", "1 - eased"], ["length * (1f + .23f * amount)", "length * (1 + 0.23 * amount)"], ["height * (1f - .12f * amount)", "height * (1 - 0.12 * amount)"], ["halfHeight * .64f * amount", "halfHeight * 0.64 * amount"]]) { assert(source.includes(original)); assert(geometry.includes(native)); }
assert(geometry.includes("[78, 89, 106, 119, 167, 179, 196, 208]"));
for (const token of ["row == 3 || row == 4", "(3.5 - Double(row)) * 5 * amount", "1 + 0.13 * amount", "row.isMultiple(of: 2) ? 3.1 : 4.6", "1 - 0.74 * amount", "x - 46 * spread, x + 46 * spread", "local.clip(to: g.field)", "length * 0.40, height: height * 0.56", "143 - 2 * amount", "85 - 4 * amount", "274 + 3 * amount", "dash: [4, 3]", "125 - reach * phase", "235 + reach * phase", "18 + 36 * amount"]) assert(drawing.includes(token), token);
const deformation = (step, t) => { const ease = t * t * (3 - 2 * t); return step === 1 ? 0.56 * ease : step === 2 ? 0.56 + 0.44 * ease : step === 3 ? 1 - ease : 0; };
assert.equal(deformation(0, 1), deformation(1, 0)); assert.equal(deformation(1, 1), deformation(2, 0)); assert.equal(deformation(2, 1), deformation(3, 0)); assert.equal(deformation(3, 1), 0);
let poses = 0;
for (let step = 0; step < 4; step++) for (let tick = 0; tick <= 120; tick++) {
  const amount = deformation(step, tick / 120); assert(amount >= 0 && amount <= 1);
  for (const row of [3, 4]) {
    const x = 180 + (3.5 - row) * 5 * amount, spread = 1 + 0.13 * amount;
    const firstEnd = x - 46 * spread, secondEnd = x + 46 * spread;
    assert(firstEnd < secondEnd && firstEnd > 20 && secondEnd < 340);
    assert(Number.isFinite(73 * (1 + 0.23 * amount)) && 16 * (1 - 0.12 * amount) > 0);
  }
  poses++;
}
const keys = ["axis", "release", "pull", "fibers", "nucleus", "profile", "rest"];
for (const language of ["en", "zh-Hans"]) for (const key of keys) assert(fs.readFileSync(path.join(app, language + ".lproj/AtlasRegional.strings"), "utf8").includes('"health_atlas_tenocyte_tendon_matrix_art_' + key + '"'));
const catalogue = JSON.parse(fs.readFileSync(path.join(app, "Assets.xcassets/HealthAtlasRegionalStories.dataset/content.json")));
assert.equal(catalogue.stories.find(s => s.id === "TENOCYTE_TENDON_MATRIX").chapters.length, 4);
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const file of ["Geometry", "Drawing", "View"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlasTenocyteTendon" + file + ".swift;").length - 1, 1);
console.log("Android #4385 tenocyte: exact parameterized fiber/cell curves, four deformation stages, marker vertices, rest profile, bilingual keys and " + poses + " analytic poses. Runtime activation pending; no native execution.");
