// Pinned geometry/annotation/reading-emphasis audit, not native Swift execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI");
const source = cp.execFileSync("git", ["show", "a81aa85a1c81e41ff19a032eabea1eddcd2371dc:apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasVulvarProtectionStoryView.kt"], {cwd: root, encoding: "utf8"});
const local = name => fs.readFileSync(path.join(app, "GalaxySSIHealthAtlasVulvar" + name + ".swift"), "utf8");
const geometry = local("Geometry"), features = local("Features"), drawing = local("Drawing"), norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "");
const original = [...source.matchAll(/private val (\w+) = (?:track\()?Path\(\)\.apply \{([\s\S]*?)\n    \}\)?/g)]; assert.equal(original.length, 10);
let commands = 0, tracks = 0;
for (const [, name, body] of original) {
  const expected = [...body.matchAll(/(moveTo|lineTo|quadTo|cubicTo|close)\(([^)]*)\)/g)].map(m => [m[1], ...m[2].split(",").filter(s => s.trim()).map(norm)]);
  const native = geometry.match(new RegExp("static let " + name + " = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const actual = native.trim().split(/\r?\n/).map(line => {
    const operation = line.match(/p\.(move|addLine|addQuadCurve|addCurve|closeSubpath)\(/)[1];
    const points = [...line.matchAll(/CGPoint\(x: ([^,]+), y: ([^)]+)\)/g)].map(m => [norm(m[1]), norm(m[2])]);
    return [{move: "moveTo", addLine: "lineTo", addQuadCurve: "quadTo", addCurve: "cubicTo", closeSubpath: "close"}[operation], ...(points.length > 1 ? [...points.slice(1).flat(), ...points[0]] : points.flat())];
  });
  assert.deepEqual(actual, expected, name); commands += actual.length;
  if (name !== "profileBase") {
    if (expected.at(-1)[0] === "close") assert.deepEqual(expected.at(-2).slice(-2), expected[0].slice(1), name + " closes without an extra segment");
    const track = geometry.match(new RegExp("static let " + name + "Track = GalaxySSIHealthAtlasRegionalTrack\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
    assert.deepEqual([...track.matchAll(/[xy]: ([^,)]+)/g)].map(m => norm(m[1])), expected.filter(c => c[0] !== "close").flatMap(c => c.slice(1)), name + " trace"); tracks++;
  }
}
assert.equal(commands, 50); assert.equal(tracks, 9);
const pack = JSON.parse(fs.readFileSync(path.join(app, "Assets.xcassets/HealthAtlasRegionalStructures.dataset/content.json")));
let annotations = 0;
for (const [name, owner] of [["region", "vulva"], ["outer", "labia-majora"], ["inner", "labia-minora"]]) {
  const original = pack.plates.find(p => p.owner === owner).features;
  const block = features.match(new RegExp("static let " + name + ": \\[Feature\\] = \\[([\\s\\S]*?)\\n  \\]"))[1];
  const native = [...block.matchAll(/\.init\(key: "([^"]+)", x: ([^,]+), y: ([^)]+)\)/g)].map(m => ({key: m[1], x: +m[2], y: +m[3]}));
  assert.deepEqual(native, original.map(f => ({key: f.title.slice(13), x: f.marker.x, y: f.marker.y})), name); annotations += native.length;
}
const inks = new Map([...source.matchAll(/private val (\w+) = 0xff([0-9a-f]+)/g)].map(m => [m[1], "0x" + m[2].toUpperCase()]));
let callouts = 0;
for (const [, plate, index, args, ink] of source.matchAll(/callout\(c, Plates\.(\w+)\.features\[(\d+)\], ([\d.f, ]+), (\w+)\)/g)) {
  assert(norm(drawing).includes(norm("vulvarCallout(f." + plate + "[" + index + "], " + args + ", " + inks.get(ink) + ")"))); callouts++;
}
assert.equal(callouts, 8);
for (const token of ["0.10 + 0.90 * p * p * (3 - 2 * p)", "(t - start) / (end - start)"]) assert(geometry.includes(token));
for (const token of ["case 0:", "case 1:", "case 2:", "case 3:", "g.reveal(t, 0, 0.56)", "g.reveal(t, 0.32, 0.95)", "g.reveal(t, 0, 0.67)", "g.reveal(t, 0.28, 0.96)", "g.reveal(t, 0, 0.91)", "g.reveal(t, 0, 0.92)", "g.reveal(t, 0, 0.72)", "g.reveal(t, 0.28, 0.98)", "longerLeft: false", "longerLeft: true", "local.translateBy(x: 148, y: 0)", "local.translateBy(x: 360, y: 0)", "stroke(segment, Self.cream, 4)", "stroke(segment, color, 2.05)", "feature.x * 360", "feature.y * 280 + 40"]) assert(drawing.includes(token), token);
for (const suffix of ["Region", "OuterSection", "InnerCloseup"]) assert(fs.statSync(path.join(app, "Assets.xcassets/HealthAtlasRegionalVulvarProtection" + suffix + ".imageset/art.pdf")).size > 0);
let samples = 0;
for (const [start, end] of [[0, 0.56], [0.32, 0.95], [0, 0.67], [0.28, 0.96], [0, 0.91], [0, 0.92], [0, 0.72], [0.28, 0.98]]) {
  let previous = 0.1;
  for (let tick = 0; tick <= 120; tick++) { const t = tick / 120, p = Math.min(1, Math.max(0, (t - start) / (end - start))), progress = 0.1 + 0.9 * p * p * (3 - 2 * p); assert(progress >= previous - 1e-12 && progress >= 0.1 && progress <= 1); previous = progress; samples++; }
}
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const file of ["Geometry", "Features", "Drawing", "View"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlasVulvar" + file + ".swift;").length - 1, 1);
console.log("Android #4385 vulvar protection: ten exact paths/50 commands, nine traces, " + annotations + " original feature anchors, eight source callouts and " + samples + " analytic reveal samples. Five scene contracts/resources; runtime activation pending, no native execution.");
