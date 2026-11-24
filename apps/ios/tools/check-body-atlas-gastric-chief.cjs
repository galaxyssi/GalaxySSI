// Pinned geometry/timing/resource checks only; no native compilation or gastric secretion validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGastricChiefStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","LocatorDrawing","CloseUpDrawing","ActivationDrawing","DigestDrawing","MoleculeDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasGastricChief" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const shapes=[...source.matchAll(/private val (\w+) = shape \{([^}]+)\}/g)];
assert.equal(shapes.length,18);
for(const [,name,block] of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block),name);
}
const tracks=[...source.matchAll(/track\(shape \{([^}]+)\}/g)].map(m=>fromCommands(m[1]));
const routeBlocks=[...files[2].matchAll(/Route\(start: ([\s\S]*?)\n    \]\)/g)];
const nativeTracks=routeBlocks.map(m=>{
  const start=m[1].match(/\.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...m[1].matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(c=>[c[1]==="quad"?"quadTo":"cubicTo",...[...c[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  return [["moveTo",...start.slice(1).map(norm)],...commands];
});
assert.equal(tracks.length,8);assert.equal(nativeTracks.length,8);
const keyed=arr=>arr.map(c=>JSON.stringify(c)).sort();
assert.deepEqual(keyed(nativeTracks),keyed(tracks),"eight transport routes");
const decodeRoutes=block=>[...block.matchAll(/Route\(start: ([\s\S]*?)\n    \]\)/g)].map(m=>{
  const start=m[1].match(/\.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...m[1].matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(c=>[c[1]==="quad"?"quadTo":"cubicTo",...[...c[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  return [["moveTo",...start.slice(1).map(norm)],...commands];
});
for(const name of ["locateTrack","acidTrack","packTracks","secretionTracks"]){
  const marker="private val "+name+" = ";
  const start=source.indexOf(marker),end=source.indexOf("\n    private val ",start+marker.length);
  const expected=[...source.slice(start,end).matchAll(/track\(shape \{([^}]+)\}/g)].map(m=>fromCommands(m[1]));
  const localStart=files[2].indexOf("static let "+name);
  assert(localStart>=0,name+" declaration");
  const localEnd=files[2].indexOf("\n  static let ",localStart+1);
  const block=files[2].slice(localStart,localEnd<0?undefined:localEnd);
  assert.deepEqual(decodeRoutes(block),expected,name+" indexed route order");
}
const fromY=source.match(/private val proteinY = floatArrayOf\(([^)]+)\)/)[1].split(",").map(s=>Number(norm(s)));
const toY=files[1].match(/static let proteinY = \[([^\]]+)\]/)[1].split(",").map(Number);
assert.equal(fromY.length,12);assert.deepEqual(toY,fromY,"protein chain elevations");
for(const match of source.matchAll(/fun (\w+)\(t: Float(?:, index: Int)?\) = (ease\([^\n]+\))/g)){
  const name=match[1],indexed=match[0].includes("index: Int");
  const native=files[0].match(new RegExp("static func "+name+"\\(_ t: Double"+(indexed?", _ index: Int":"")+"\\) -> Double \\{ ([^}]+) \\}"))[1];
  assert.equal(norm(native.replaceAll("Double(index)","index")),norm(match[2]),name);
}
const fromLabels=[...source.matchAll(/callout\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const toLabels=[...all.matchAll(/gastricChiefCallout\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(fromLabels.length,17);assert.deepEqual(toLabels,fromLabels,"stage callout anchors");
for(const key of new Set([...source.matchAll(/R.string.health_atlas_(\w+)/g)].map(m=>m[1]))) for(const language of ["en","zh-Hans"])
  assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
for(const [swift,kotlin] of [
  ["f * f * (3 - 2 * f)","f * f * (3f - 2f * f)"],
  ["t.isFinite ? min(1, max(0, t)) : 0","if (t.isFinite()) t.coerceIn(0f, 1f) else 0f"],
  ["215 - 2 * Double(i), 115 + 28 * Double(i), isChief: i >= 4, isParietal: i == 2","215f - 2f * i, 115f + 28f * i, i >= 4, i == 2"],
  ["283 - Double(i), 117 + 28 * Double(i), isChief: i >= 4, isParietal: i == 1 || i == 3","283f - 1f * i, 117f + 28f * i, i >= 4, i == 1 || i == 3"],
  ["if x > 250","if (x > 250f)"],
  ["1 + 1.2 * p","1f + 1.2f * p"],
  ["4.4 + 4.6 * p","4.4f + 4.6f * p"],
  ["if p < 0.90","if (p < .90f)"],
  ["181 + 36 * p, 183 + 12 * p, 9","181f + 36f * p, 183f + 12f * p, 9f"],
  ["release(t, 0) == 0","release(t, 0) == 0f"],
  ["line(226, 184, 226, 206, 0xCFE5E0, 3.4)","line(c, 226f, 184f, 226f, 206f, 0xffcfe5e0, 3.4f)"],
  ["Double(Int(143 * flow)) / 255","(143f * flow).toInt()"],
  ["flow * 1.18 - 0.19 * Double(i)","flow * 1.18f - .19f * i"],
  ["y + Double(i % 2) * 5","y + (i % 2) * 5f"],
  ["174, 191 - 7 * first, 11, cleavage: first","174f, 191f - 7f * first, 11f, first"],
  ["195, 238 - 12 * second, 9, cleavage: second","195f, 238f - 12f * second, 9f, second"],
  ["middleX = 5 * left - 4 * right, middleY = 20 * left","val middleX = 5f * left - 4f * right"],
  ["if left == 0 { gastricChiefBond(3, 0, 0) }","if (left == 0f) bond(c, 3, 0f, 0f)"],
  ["if right == 0 { gastricChiefBond(7, middleX, middleY) }","if (right == 0f) bond(c, 7, middleX, middleY)"],
  ["gastricChiefChain(0, 3, -11 * left, -8 * left)","chain(c, 0, 3, -11f * left, -8f * left)"],
  ["gastricChiefChain(4, 7, middleX, middleY)","chain(c, 4, 7, middleX, middleY)"],
  ["gastricChiefChain(8, 11, middleX + 17 * right, middleY - 29 * right)","chain(c, 8, 11, middleX + 17f * right, middleY - 29f * right)"],
  ["target + side * (46 * (1 - p) + 26 * split) + Double(i) * middleX * p","target + side * (46f * (1f - p) + 26f * split) + i * middleX * p"],
  ["157 - 35 * (1 - p) + (15 + Double(i) * middleY) * wave(p * 0.25) - 39 * split","157f - 35f * (1f - p) + (15f + i * middleY) * wave(p * .25f) - 39f * split"],
  ["for i in first..<last","for (i in first until last)"],
  ["for i in first...last","for (i in first..last)"],
  ["66 + 20 * Double(i) + dx","66f + 20f * i + dx"],
  ["radius * 0.47, cleavage: 0","radius * .47f, 0f"],
  ["dx = 1.20 * cleavage, dy = 0.62 * cleavage","val dx = 1.20f * cleavage"],
  ["art.line(0.72 + dx, -0.42 + dy, 0.89 + dx, 0.16 + dy, 0x9B622F, 0.36)","line(c, .72f + dx, -.42f + dy, .89f + dx, .16f + dy, amber, .36f)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "cleavage: Double? = nil","if let cleavage","local.scaleBy(x: size, y: size)",
  "at(route, p)","at(route, f)","if f > 0","if isParietal","if isChief",
  "gastricChiefPack(t)","gastricChiefRelease(t)","gastricChiefActivate(t)","gastricChiefDigest(t)",
  "Geometry.sharedLumen, 105, 246, 0xE8AA92, 0xEDCFAC",
  "gastricChiefMolecule(x, y, 9)","gastricChiefMolecule(288, 145, 7.4)",
  "proteinY[i] + dy","ys[i + 1] + dy","atlas-function-gastric-chief-art"
])assert(all.includes(token),token);
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "GASTRIC_CHIEF_SECRETION": GalaxySSIHealthAtlasGastricChiefView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 gastric-chief source audit: eighteen exact outlines/eight transport routes, twelve protein positions, source timing/packing/fusion/acid activation, distinct precursor caps, two chain cut sites and seventeen bilingual callout anchors. No native compilation/pixels verified.");
