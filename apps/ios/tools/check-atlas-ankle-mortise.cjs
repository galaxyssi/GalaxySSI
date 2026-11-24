// Geometry/source audit only; does not run Swift or verify native pixels.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasAnkleMortiseStoryView.kt"], {cwd: root, encoding: "utf8"});
const local = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlasAnkle" + name + ".swift"), "utf8");
const geometry = local("Geometry"), drawing = local("Drawing"), view = local("View");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "");
const original = [...source.matchAll(/val (\w+) = Path\(\).apply \{([\s\S]*?)\n        \}/g)];
const shapes = [...geometry.matchAll(/static (?:let|func) (\w+)[^\n]*Path \{ p in([\s\S]*?)\n  \}/g)];
assert.equal(original.length, 9); assert.equal(shapes.length, 9);
let count = 0;
for (let i = 0; i < original.length; i++) {
  const expected = [...original[i][2].matchAll(/(moveTo|lineTo|quadTo|cubicTo|close)\(([^)]*)\)/g)].map(m => [m[1], ...m[2].split(",").filter(s => s.trim()).map(norm)]);
  const actual = shapes[i][2].trim().split(/\r?\n/).map(line => {
    const operation = line.match(/p\.(move|addLine|addQuadCurve|addCurve|closeSubpath)\(/)[1];
    const points = [...line.matchAll(/CGPoint\(x: ([^,]+), y: ([^)]+)\)/g)].map(m => [norm(m[1]), norm(m[2])]);
    return [{move: "moveTo", addLine: "lineTo", addQuadCurve: "quadTo", addCurve: "cubicTo", closeSubpath: "close"}[operation], ...(points.length > 1 ? [...points.slice(1).flat(), ...points[0]] : points.flat())];
  });
  assert.deepEqual(actual, expected, shapes[i][1]); count += actual.length;
}
for (const token of ["case 0: ankleOverview(sin(phase * .pi))", "case 1: ankleCradle(0, sin(phase * .pi))", "case 2: ankleSide(16 * ease, advancing: true)", "case 3: ankleCradle(ease * 10, 1)", "ankleSide(16 * (1 - ease), advancing: false)", "phase * phase * (3 - 2 * phase)", "local.rotate(by: .degrees(-angle))", "Double(Int(95 + highlight * 140)) / 255", "for index in 0..<3", "shift > 0.2", "2.5 + emphasis * 1.6", "tx + (left ? 19 : -19)"]) assert(drawing.includes(token), token);
for (const token of ["local.translateBy(x: 157, y: 190)", "local.translateBy(x: -157, y: -190)", "206 + shift * 2.4 + 10", "196 + shift / 2"]) assert(drawing.includes(token));
assert(view.includes('"atlas-function-ankle-mortise-art"')); assert(view.includes("story.fraction(phase)"));
const catalogue = JSON.parse(fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasRegionalStories.dataset/content.json")));
const story = catalogue.stories.find(s => s.id === "ANKLE_MORTISE");
assert.equal(story.chapters.length, 5); assert.equal(story.durationMs, 20000);
assert.deepEqual(catalogue.routes.tibia, ["KNEE_ARTICULATION", "ANKLE_MORTISE"]);
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const file of ["Geometry", "Drawing", "View"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlasAnkle" + file + ".swift;").length - 1, 1);
console.log("Android #4385 ankle: nine exact paths / " + count + " commands, five scene mappings, easing/rotation/highlight/callout source contracts and project registration. Runtime source dispatch audited separately; no native execution.");
