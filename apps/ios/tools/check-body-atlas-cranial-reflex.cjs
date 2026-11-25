// Pinned geometry/timing/resource checks only; no native compilation or reflex validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCranialReflexStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","EyeDrawing","NeuralDrawing","LightLabelsDrawing"].map(n => "GalaxySSIHealthAtlasCranial" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
for (const name of ["eye","lid","globeSection","retina","lightGuide","lightIn","lightThrough","midbrain","midbrainFolds"]) {
  const from = source.match(new RegExp("private val " + name + " = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to = files[1].match(new RegExp("static let " + name + " = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to), fromCommands(from), name);
}
const routeNames = ["nerve","stay","cross","localRelay","crossRelay","returnNerve","toIris"];
for (const name of routeNames) {
  const from = fromCommands(source.match(new RegExp("val " + name + " = Path\\(\\).apply \\{([^}]+)\\}"))[1]);
  const block = files[2].match(new RegExp(name + " = Track\\(([\\s\\S]*?)\\n      \\]\\)\\)"))[1];
  const start = block.match(/start: \.init\(x: (x\([^)]+\)), y: ([^)]+)\)/);
  const commands = [...block.matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(m => [m[1] === "quad" ? "quadTo" : "cubicTo", ...[...m[2].matchAll(/[xy]: (x\([^)]+\)|[^,)]+)/g)].map(v => norm(v[1]))]);
  assert.deepEqual([["moveTo", ...start.slice(1).map(norm)], ...commands], from, name);
  for (const direction of [1,-1]) {
    const x = n => direction > 0 ? n : 360 - n;
    const end = from.at(-1).slice(-2).map(n => n.startsWith("x(") ? x(Number(n.slice(2,-1))) : Number(n));
    assert(end.every(n => n >= 0 && n <= 360), name + " endpoint bounds");
    if (name === "cross" || name === "crossRelay") assert(direction > 0 ? end[0] > 180 : end[0] < 180, name + " crosses midline");
  }
}
const sourceCalls = [...source.matchAll(/callout\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m => [m[1], ...m[2].split(",").map(norm)]);
const nativeCalls = [...all.matchAll(/cranialCallout\("([^"]+)", ([^)]+)\)/g)].map(m => [m[1], ...m[2].split(",").map(norm)]);
assert.equal(sourceCalls.length, 11); assert.deepEqual(nativeCalls, sourceCalls, "label anchors");
for (const [key] of sourceCalls) for (const language of ["en","zh-Hans"]) assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_' + key + '"'), key);
for (const [swift,kotlin] of [
  ["direction > 0 ? value : 360 - value", "if (direction > 0f) value else 360f - value"],
  ["step == 4 ? ease(t, 0.08, 0.84) : 0", "if (step == 4) ease(t, .08f, .84f) else 0f"],
  ["12.6 - 6.6 * narrowing", "12.6f - 6.6f * narrowing"],
  ["ease(t, 0.66, 0.94)", "ease(t, .66f, .94f)"],
  ["1 - 0.48 * ease(t, 0.12, 0.68)", "1f - .48f * ease(t, .12f, .68f)"],
  ["ease(t, 0.44, 0.88)", "ease(t, .44f, .88f)"],
  ["1 - 0.65 * ease(t, 0, 0.44)", "1f - .65f * ease(t, 0f, .44f)"],
  ["ease(t, 0.46, 0.59) * (1 - 0.8 * ease(t, 0.68, 0.96))", "ease(t, .46f, .59f) * (1f - .8f * ease(t, .68f, .96f))"],
  ["(t - 0.42) / 0.53", "(t - .42f) / .53f"],
  ["t / 0.49", "t / .49f"], ["(t - 0.10) / 0.77", "(t - .10f) / .77f"],
  ["(t - 0.04) / 0.54", "(t - .04f) / .54f"], ["(t - 0.58) / 0.36", "(t - .58f) / .36f"],
  ["frame.t / 0.50", "t / .50f"], ["(frame.t - 0.48) / 0.31", "(t - .48f) / .31f"],
  ["ease(frame.t, 0.58, 1)", "ease(t, .58f, 1f)"],
  ["Double(Int(205 * glow)) / 255", "(205f * glow).toInt()"],
  ["Double(Int(110 * activity)) / 255", "(110f * activity).toInt()"],
  ["Double(Int(235 * frame.narrowing)) / 255", "(235f * narrowing).toInt()"],
  ["6 + 4 * activity", "6f + 4f * activity"],
  ["for i in 0..<40", "for (i in 0 until 40)"],
  ["frame.radius + (i % 3 == 0 ? 3.2 : 2)", "pupilRadius + if (i % 3 == 0) 3.2f else 2f"],
  ["i % 2 == 0 ? 20.1 : 18.3", "if (i % 2 == 0) 20.1f else 18.3f"],
  ["cosA * 17 - sinA", "cosA * 17f - sinA"], ["75 + sinA * 17 + cosA", "75f + sinA * 17f + cosA"],
  ["max(0, t - 0.25)", "(t - .25f).coerceAtLeast(0f)"],
  ["p * p * (3 - 2 * p)", "p * p * (3f - 2f * p)"]
]) { assert(all.includes(swift),swift); assert(source.includes(kotlin),kotlin); }
for (const color of ["65747E","B47C31","26746E","8CB2A8","755587","AE94B7","A25264","C79BA1","936964","AC7D8B","FFFBF3","EDD9CF","B1B99A","688E83","F3D9DF","E3BCC9","F5E9DF","C8A6A0","C48177","EBAD91","4B7169","507B70","718675","243B42","F4F2E6","DCA7A0","B68883","C595A7","E6B4C4","CB9AAA","D6A5B8","CCAA71","D7B789"]) {
  assert(all.includes("0x"+color),color); assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for (const token of ["guard t.isFinite, (0...1).contains(t) else { return }","let side = sides[0]","static let sides = [Side(1), Side(-1)]","clipped.clip(to: Geometry.eye)","guard frame.step == 0 else { return }","local.translateBy(x: 90, y: 0)","if step == 4 {","atlas-function-cranial-reflex-art","cranialEye(90, direction: 1","cranialEye(270, direction: -1"])
  assert(all.includes(token),token);
assert(!all.includes("Timer")); assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "CRANIAL_REFLEX": GalaxySSIHealthAtlasCranialView'));
const project = fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for (const name of names) assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 cranial-reflex source audit: nine exact paths, seven mirrored/crossing routes, five-stage signal windows, bilateral pupil narrowing, forty iris spokes, integer-alpha activity/glow and eleven bilingual label anchors. No native compilation/pixels verified.");
