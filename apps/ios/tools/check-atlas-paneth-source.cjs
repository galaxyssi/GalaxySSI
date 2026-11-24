// Source geometry/phase audit only, not a Swift/Android execution or UI test.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "6581110ec5c048edebf63821dee839b4818fe663";
const original = name => cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlas" + name + ".kt"], {cwd: root, encoding: "utf8"});
const native = name => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI/GalaxySSIHealthAtlas" + name + ".swift"), "utf8");
const wall = original("CryptWallArt"), swift = native("CryptWallDrawing"), course = native("PanethBarrierView");
const numbers = s => [...s.matchAll(/-?(?:\d+\.?\d*|\.\d+)(?:f)?/g)].map(m => Number(m[0].replace(/f$/, "")));
const apical = wall.slice(wall.indexOf("private val apical"), wall.indexOf("private val laminaPropria"));
const sourceCurves = [...apical.matchAll(/cubicTo\(([^)]+)\)/g)].map(m => numbers(m[1]));
const swiftCurves = [...swift.slice(swift.indexOf("static let route"), swift.indexOf("static let apical")).matchAll(/kind: \.cubic, points: \[([^\]]+)\]/g)].map(m => numbers(m[1]));
assert.equal(sourceCurves.length, 7); assert.deepEqual(swiftCurves, sourceCurves);
const shape = wall.slice(wall.indexOf("private val panethShape"), wall.indexOf("protected fun center"));
const body = swift.slice(swift.indexOf("func panethBody"), swift.indexOf("func flatOval"));
const sourceQuads = [...shape.matchAll(/quadTo\(([^)]+)\)/g)].map(m => numbers(m[1]));
const nativeQuads = [...body.matchAll(/addQuadCurve\(to: CGPoint\(x: ([^,]+), y: ([^)]+)\), control: CGPoint\(x: ([^,]+), y: ([^)]+)\)\)/g)]
  .map(m => [Number(m[3]), Number(m[4]), Number(m[1]), Number(m[2])]);
assert.equal(sourceQuads.length, 4); assert.deepEqual(nativeQuads, sourceQuads);
for (const token of ["static let cellSpan", "/ 29", "(0...29)", "(0..<29)", "direction.dx * along - direction.dy * outward",
  "direction.dy * along + direction.dx * outward", "sample(Double($0) + 0.5)", "b.at(0, 20)", "a.at(0, 20)"]) assert.ok(swift.includes(token), token);
for (const token of ["[-3.5, 0.2, 3.9, -0.7]", "[5.5, 4.1, 6.2, 9.0]", "wall.wall(feature: 13)",
  "centers[13]", "ease(t, 0.06, 0.96)", "p < 0.28", "(p - 0.28) / 0.72", "0.76 + Double(i) * 0.095",
  "paneth_barrier_cell", "paneth_barrier_apical", "paneth_barrier_peptides", "crypt_lumen"]) assert.ok(course.includes(token), token);
assert.ok(original("PanethBarrierStoryView").includes("for (i in 0..10)"));
let points = 0;
for (let step = 0; step <= 120; step++) {
  const t = step / 120, p = t * t * (3 - 2 * t);
  for (let i = 0; i <= 10; i++) {
    const y = -19 - i * 3.1 - (18 + (i % 3) * 8) * p;
    assert.ok(Number.isFinite(y) && y < 0, "Dispersal must remain lumen-side of the local apex"); points++;
  }
}
console.log("Source-only Paneth audit: seven apical cubics, four cell-body quadratics, 29-slot poses, four-stage contracts and " + points + " analytic lumen-side samples. No native/pixel acceptance.");
