// Source/geometry audit only; not Swift execution or native visual acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPenileUrinaryStoryView.kt"], {cwd: root, encoding: "utf8"});
const local = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlasPenileUrinary" + name + ".swift"), "utf8");
const geometry = local("Geometry"), drawing = local("Drawing"), view = local("View");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "");
const commands = body => [...body.matchAll(/(moveTo|lineTo|quadTo|cubicTo|close)\(([^)]*)\)/g)].map(m => [m[1], ...m[2].split(",").filter(s => s.trim()).map(norm)]);
const original = [...source.matchAll(/private val (\w+) = Path\(\)\.apply \{([\s\S]*?)\n    \}/g)];
assert.equal(original.length, 9);
const extra = source.match(/private val route = Path\(proximalRoute\)\.apply \{([\s\S]*?)\n    \}/)[1];
let count = 0;
function actual(body) {
  return body.trim().split(/\r?\n/).map(line => {
    const operation = line.match(/p\.(move|addLine|addQuadCurve|addCurve|closeSubpath)\(/)[1];
    const points = [...line.matchAll(/CGPoint\(x: ([^,]+), y: ([^)]+)\)/g)].map(m => [norm(m[1]), norm(m[2])]);
    return [{move: "moveTo", addLine: "lineTo", addQuadCurve: "quadTo", addCurve: "cubicTo", closeSubpath: "close"}[operation], ...(points.length > 1 ? [...points.slice(1).flat(), ...points[0]] : points.flat())];
  });
}
for (const [, name, body] of original) {
  const native = geometry.match(new RegExp("static let " + name + " = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected = commands(body); assert.deepEqual(actual(native), expected, name); count += expected.length;
}
const appended = geometry.match(/var p = proximalRoute\n([\s\S]*?)\n    return p/)[1];
assert.deepEqual(actual(appended), commands(extra)); count += commands(extra).length;
for (const [name, body] of [["proximalTrack", original.find(p => p[1] === "proximalRoute")[2]], ["flow", original.find(p => p[1] === "proximalRoute")[2] + extra]]) {
  const native = geometry.match(new RegExp("static let " + name + " = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
  assert.deepEqual([...native.matchAll(/[xy]: ([^,)]+)/g)].map(m => norm(m[1])), commands(body).flatMap(c => c.slice(1)), name);
}
for (const token of ["if step == 0 { penileTransverse(t) }", "distal: step == 2", "local.scaleBy(x: -1, y: 1)", "0.5 + 0.5 * wave(t)", "distal ? spongyStart : 0", "distal ? flow.length : spongyStart", "end - start + 24", "max(distance - 24, start)", "min(distance, end)", "tail / flow.length, to: head / flow.length", "0xC28233, 4.4", "0xFFD47F, 2.4", "above ? 5 : -15"]) assert(drawing.includes(token), token);
assert(view.includes('"atlas-function-penile-urinary-route-art"'));
const story = JSON.parse(fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasRegionalStories.dataset/content.json"))).stories.find(s => s.id === "PENILE_URINARY_ROUTE");
assert.equal(story.chapters.length, 3); assert.deepEqual(story.owners, ["penis"]);
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const file of ["Geometry", "Drawing", "View"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlasPenileUrinary" + file + ".swift;").length - 1, 1);
console.log("Android #4385 penile urinary route: ten exact paths / " + count + " commands, continuous tracer DTO controls, proximal/distal interval contracts and project registration. Runtime source dispatch audited separately; no native execution.");
