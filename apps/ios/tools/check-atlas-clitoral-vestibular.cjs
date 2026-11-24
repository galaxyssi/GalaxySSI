// Pinned source/geometry/resource audit; not Swift or native scene execution.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), app = path.join(root, "apps/ios/GalaxySSI"), sha = "a81aa85a1c81e41ff19a032eabea1eddcd2371dc";
const local = name => fs.readFileSync(path.join(app, "GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "");
let paths = 0, commands = 0, tracks = 0, labels = 0, leaders = 0;
for (const [name, prefix, count, routeNames] of [["VestibularGland", "vestibular_gland", 7, ["upper", "middle", "lower", "main", "leftOutlet", "rightOutlet"]], ["ClitoralSensory", "clitoral_sensory", 9, ["endingRoute", "dorsalRoute", "sacralRoute"]]]) {
  const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + "StoryView.kt"], {cwd: root, encoding: "utf8"});
  const geometry = local(name + "Geometry"), drawing = local(name + "Drawing"), view = local(name + "View");
  const original = [...source.matchAll(/private val (\w+) = (?:track\()?Path\(\)\.apply \{([\s\S]*?)\n    \}\)?/g)];
  assert.equal(original.length, count); paths += count;
  const expected = body => [...body.matchAll(/(moveTo|lineTo|quadTo|cubicTo|close)\(([^)]*)\)/g)].map(m => [m[1], ...m[2].split(",").filter(s => s.trim()).map(norm)]);
  for (const [, id, body] of original) {
    const native = geometry.match(new RegExp("static let " + id + " = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
    const actual = native.trim().split(/\r?\n/).map(line => {
      const operation = line.match(/p\.(move|addLine|addQuadCurve|addCurve|closeSubpath)\(/)[1];
      const points = [...line.matchAll(/CGPoint\(x: ([^,]+), y: ([^)]+)\)/g)].map(m => [norm(m[1]), norm(m[2])]);
      return [{move: "moveTo", addLine: "lineTo", addQuadCurve: "quadTo", addCurve: "cubicTo", closeSubpath: "close"}[operation], ...(points.length > 1 ? [...points.slice(1).flat(), ...points[0]] : points.flat())];
    });
    assert.deepEqual(actual, expected(body), name + ":" + id); commands += actual.length;
    if (routeNames.includes(id)) {
      const track = geometry.match(new RegExp("static let " + id + "Track = GalaxySSIHealthAtlasRegionalTrack\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
      assert.deepEqual([...track.matchAll(/[xy]: ([^,)]+)/g)].map(m => norm(m[1])), expected(body).flatMap(c => c.slice(1)), name + ":" + id + " trace controls"); tracks++;
    }
  }
  for (const [, key, args] of source.matchAll(new RegExp("label\\(c, string\\.health_atlas_(" + prefix + "_\\w+), ([^\\n]+)\\)", "g"))) {
    assert(norm(drawing).includes(norm('label("' + key + '", ' + args + ')')), key); labels++;
    for (const language of ["en", "zh-Hans"]) assert(fs.readFileSync(path.join(app, language + ".lproj/AtlasRegional.strings"), "utf8").includes('"health_atlas_' + key + '"'));
  }
  const nativeLeader = name === "VestibularGland" ? "vestibularGlandLeader" : "clitoralLeader";
  for (const [, args] of source.matchAll(/leader\(c, ([\d.f, ]+)\)/g)) { assert(norm(drawing).includes(norm(nativeLeader + "(" + args + ")")), args); leaders++; }
  assert(view.includes("story.chapter(phase), story.fraction(phase)"));
}
assert.equal(tracks, 9);
const gland = local("VestibularGlandDrawing"), sensory = local("ClitoralSensoryDrawing");
for (const token of ["case 0: vestibularGlandLocation(t, flow: false)", "case 1: vestibularGlandMicro(t, collecting: false)", "case 2: vestibularGlandMicro(t, collecting: true)", "vestibularGlandLocation(t, flow: true)", "y: 28, width: 360, height: 280", "[g.upperTrack, g.middleTrack, g.lowerTrack]", "Int(t * Double(tracks.count))", "t * Double(tracks.count) - Double(slot)", "p * (branch.length + main.length)", "distance / branch.length", "(distance - branch.length) / main.length", "for sector in 0...7 where sector != 2", "Double(sector) * 45", "max(0, distance - 8)", "y - 10 + 10 * t", "1.8 + 0.7 * t"]) assert(gland.includes(token), token);
for (const token of ["case 0: clitoralStructure(t)", "case 1: clitoralEndings(t)", "case 2: clitoralDorsal(t)", "clitoralSacral(t)", "y: 36, width: 360, height: 280", "y: 25, width: 360, height: 280", "min(3, Int(t * 4))", "5 + 4 * phase", "125 * (1 - wave(phase + 0.25))", "mirrored.scaleBy(x: -1, y: 1)", "max(0, head - 26)", "0x307E83, 3.1", "4.1, 0xF7F6DF"]) assert(sensory.includes(token), token);
for (const asset of ["HealthAtlasRegionalGreaterVestibularGlandDucts", "HealthAtlasRegionalClitoralCutaway"]) assert(fs.statSync(path.join(app, "Assets.xcassets", asset + ".imageset/art.pdf")).size > 0);
const pbx = fs.readFileSync(path.join(root, "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"), "utf8");
for (const name of ["RegionalTrack", "VestibularGlandGeometry", "VestibularGlandDrawing", "VestibularGlandView", "ClitoralSensoryGeometry", "ClitoralSensoryDrawing", "ClitoralSensoryView"]) assert.equal(pbx.split("path = GalaxySSIHealthAtlas" + name + ".swift;").length - 1, 1);
console.log("Android #4385 clitoral/vestibular: " + paths + " exact paths / " + commands + " commands / " + tracks + " traces, " + labels + " bilingual labels / " + leaders + " source callouts, four scenes per course and project resources. Runtime activation pending; no native execution.");
