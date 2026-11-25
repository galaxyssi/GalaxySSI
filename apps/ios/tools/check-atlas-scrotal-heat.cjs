// Pinned source/geometry audit, not Swift execution or native pixel acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasScrotalHeatStoryView.kt"], {cwd: root, encoding: "utf8"});
const local = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlasScrotalHeat" + name + ".swift"), "utf8");
const geometry = local("Geometry"), drawing = local("Drawing"), view = local("View");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "");
const original = [...source.matchAll(/private val (\w+) = Path\(\).apply \{([\s\S]*?)\n    \}/g)];
assert.equal(original.length, 11);
let count = 0;
for (const [, name, body] of original) {
  const native = geometry.match(new RegExp("static let " + name + " = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected = [...body.matchAll(/(moveTo|lineTo|quadTo|cubicTo|close)\(([^)]*)\)/g)].map(m => [m[1], ...m[2].split(",").filter(s => s.trim()).map(norm)]);
  const actual = native.trim().split(/\r?\n/).map(line => {
    const operation = line.match(/p\.(move|addLine|addQuadCurve|addCurve|closeSubpath)\(/)[1];
    const points = [...line.matchAll(/CGPoint\(x: ([^,]+), y: ([^)]+)\)/g)].map(m => [norm(m[1]), norm(m[2])]);
    return [{move: "moveTo", addLine: "lineTo", addQuadCurve: "quadTo", addCurve: "cubicTo", closeSubpath: "close"}[operation], ...(points.length > 1 ? [...points.slice(1).flat(), ...points[0]] : points.flat())];
  });
  assert.deepEqual(actual, expected, name); count += actual.length;
}
// Confirm route DTOs retain identical controls and travel directions for arc-length tracers.
for (const name of ["artery", "vein"]) {
  const native = geometry.match(new RegExp("static let " + name + "Track = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
  const expected = [...original.find(p => p[1] === name)[2].matchAll(/(?:moveTo|cubicTo|quadTo)\(([^)]*)\)/g)].flatMap(m => m[1].split(",").map(norm));
  const actual = [...native.matchAll(/[xy]: ([^,)]+)/g)].map(m => norm(m[1]));
  assert.deepEqual(actual, expected, name + " tracer");
}
for (const token of ["if step == 2 { scrotalExchange(t) }", "coverings: step == 1", "0.5 + 0.5 * wave(t)", "local.translateBy(x: 0, y: 10)", "local.scaleBy(x: -1, y: 1)", "0xEDC5CF, 9 + 2 * emphasis", "0xBEDFD7, 8 + 2 * emphasis", "width + 2.4", "track.length + 22", "head - 22", "end > start", "start / track.length, to: end / track.length", "0x96652F", "wave(t * 2 - Double(i) * 0.24)", "above ? 5 : -15"]) assert(drawing.includes(token), token);
assert(view.includes('"atlas-function-scrotal-heat-exchange-art"'));
const story = JSON.parse(fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasRegionalStories.dataset/content.json"))).stories.find(s => s.id === "SCROTAL_HEAT_EXCHANGE");
assert.equal(story.chapters.length, 3); assert.deepEqual(story.owners, ["scrotum"]);
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const file of ["Geometry", "Drawing", "View"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlasScrotalHeat" + file + ".swift;").length - 1, 1);
console.log("Android #4385 scrotal heat: eleven exact paths / " + count + " commands, original tracer controls/directions, mirrored sections, three chapter contracts and project registration. Runtime source dispatch audited separately; no native execution.");
