// Pinned geometry/timing/resource checks only; no native compilation or acinar secretion validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasAcinarEnzymeStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","AcinusDrawing","CellDrawing","DuctDrawing","ArrivalDrawing","CargoDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasAcinar" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const trace=source.match(/private fun Path.tracePancreaticDuct\(\) \{([^}]+)\}/)[1],expand=b=>b.replace(/tracePancreaticDuct\(\)/g,trace);
const shapes=[...source.matchAll(/private val (\w+) = shape \{([^}]+)\}/g)];
assert.equal(shapes.length,16);
for(const [,name,block] of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(expand(block)),name);
}
const tracks=[...source.matchAll(/private val (\w+) = track\(shape \{([^}]+)\}/g)];
assert.equal(tracks.length,5);
for(const [,name,block] of tracks){
  const native=files[2].match(new RegExp("static let "+name+" = Route\\(([\\s\\S]*?)\\n  \\]\\)"))[1];
  const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...native.matchAll(/\.init\(kind: \.(line|quad|cubic), points: \[([^\]]+)\]/g)].map(m=>[{line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  assert.deepEqual([["moveTo",...start.slice(1).map(norm)],...commands],fromCommands(expand(block)),name);
}
for(const name of ["erFolds","golgiStacks"]){
  const from=source.match(new RegExp("private val "+name+" = List\\(5\\)[\\s\\S]*?shape \\{([^}]+)\\}"))[1];
  const to=files[1].match(new RegExp("static let "+name+"[\\s\\S]*?return Path \\{ p in([^}]+)\\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name+" row geometry");
}
const diamondSource=source.match(/cargoDiamond.apply \{([\s\S]*?)\n            \}/)[1];
const diamondNative=files[1].match(/static func diamond[\s\S]*?var p = Path\(\)([\s\S]*?)return p/)[1];
assert.deepEqual(toCommands(diamondNative),fromCommands(diamondSource),"precursor diamond");
for(const m of source.matchAll(/fun (\w+)\(t: Float\) = ([^\n]+)/g)){
  const native=files[0].match(new RegExp("static func "+m[1]+"\\(_ t: Double\\) -> Double \\{ ([^}]+) \\}"))[1];
  assert.equal(norm(native),norm(m[2].replaceAll("HealthAtlasFunctionStory.safePhase(t)","safe(t)")),m[1]+" motion");
}
const sourceCalls=[...source.matchAll(/callout\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeCalls=[...all.matchAll(/acinarCallout\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(sourceCalls.length,16);assert.deepEqual(nativeCalls,sourceCalls,"stage callout anchors");
const sourceAcini=[...source.matchAll(/acinus\(c, ([^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
const nativeAcini=[...all.matchAll(/acinarAcinus\(([^_][^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
assert.equal(sourceAcini.length,10);assert.deepEqual(nativeAcini,sourceAcini,"scaled acini");
for(const key of new Set([...source.matchAll(/R.string.health_atlas_(\w+)/g)].map(m=>m[1])))for(const language of ["en","zh-Hans"])
  assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
for(const [swift,kotlin] of [
  ["p * p * (3 - 2 * p)","p * p * (3f - 2f * p)"],
  ["a + (b - a) * p","a + (b - a) * p"],
  ["for i in 1...7","for (i in 1..7)"],
  ["rotated.rotate(by: .degrees(45 * Double(i)))","c.rotate(45f * i)"],
  ["31 + 4 * (1 - p)","31f + 4f * (1f - p)"],
  ["Double(i) / 10 + 0.055","from + .055f"],
  ["row = Double(index), y = 120 + row * 8","val y = 120f + row * 8f"],
  ["row = Double(index), x = 127 + row * 6","val x = 127f + row * 6f"],
  ["117 + Double(row) * 8 + (i < 2 ? 0 : 1.6)","117f + row * 8f + if (i < 2) 0f else 1.6f"],
  ["if early < 1","if (early < 1f)"],
  ["max(0, early - 0.23)","(early - .23f).coerceAtLeast(0f)"],
  ["if late > 0","if (late > 0f)"],
  ["3.5 + late * 4","3.5f + late * 4f"],
  ["acinarCellPlate(fused: dock >= 1)","cellPlate(c, fused = dock >= 1f)"],
  ["Motion.mix(201, 232, dock), Motion.mix(168, 175, dock), 8","mix(201f, 232f, dock), mix(168f, 175f, dock), 8f"],
  ["release * 1.14 - 0.14 * Double(i)","release * 1.14f - .14f * i"],
  ["if (0...1).contains(p)","if (p in 0f..1f)"],
  ["y + Double(i % 2) * 4 - 2, precursor: i % 2 == 1, radius: 2.8","y + (i % 2) * 4f - 2f, i % 2 == 1, 2.8f"],
  ["126 + Double(i) * 25.5","126f + i * 25.5f"],
  ["acinarDuctCell(x, 145, i); acinarDuctCell(x, 193, i + 1)","ductCell(c, x, 193f, i + 1)"],
  ["flow * 0.66 + Double(i) * 0.19","flow * .66f + i * .19f"],
  ["y + (i % 2 == 0 ? -2 : 2), precursor: i % 2 != 0, radius: 2.7","y + if (i % 2 == 0) -2f else 2f, i % 2 != 0, 2.7f"],
  ["fluid * 1.32 - Double(i) * 0.16","fluid * 1.32f - i * .16f"],
  ["Motion.mix(i == 1 ? 201 : 161, i == 1 ? 187 : 176, p)","mix(if (i == 1) 201f else 161f, if (i == 1) 187f else 176f, p)"],
  ["startX + 16 * p * p","startX + 16f * p * p"],
  ["0.30 + 0.68 * p - 0.065 * Double(i)",".30f + .68f * p - .065f * i"],
  ["if i % 3 == 2 { acinarFluidMark(x, y) }","if (i % 3 == 2) fluidMark(c, x, y)"],
  ["precursor: i % 3 == 1, radius: 2.65","i % 3 == 1, 2.65f"],
  ["x - r * 0.17, y - r * 0.23, r * 0.35","x - r * .17f, y - r * .23f, r * .35f"],
  ["center - width / 2 - 3, 321","center - width / 2f - 3f, 321f"],
  ["label(key, center + 8, 325, 126)","label(c, res, center + 8f, 325f, 126f)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "if fused {","Geometry.cellOuterMembrane","line(240, 136, 240, 169","line(240, 181, 240, 204",
  "Geometry.fusionMouth","if precursor {","Geometry.diamond(x, y, radius)",
  "acinarCargoKey(\"acinar_enzyme_story_enzymes\", center: 91, precursor: false)",
  "acinarCargoKey(\"acinar_enzyme_story_precursors\", center: 259, precursor: true)",
  "UIFont.systemFont(ofSize: 13, weight: .medium)","min(126, Double(",
  "acinarPackageCargo(t)","acinarReleaseCargo(t)","acinarDuctTransit(t)","acinarArrive(t)",
  "atlas-function-acinar-enzymes-art"
])assert(all.includes(token),token);
assert.equal((all.match(/static let (?:erFolds|golgiStacks): \[Path\] = \(0\.\.<5\)/g)||[]).length,2);
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "ACINAR_ENZYME_SECRETION": GalaxySSIHealthAtlasAcinarView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 acinar source audit: sixteen exact outlines/five routes, five ER/Golgi rows each, fixed fusion mouth, gated mixed cargo, duct-fluid enrichment/delivery, ten scaled acini, measured bilingual keys and sixteen callout anchors. No native compilation/pixels verified.");
