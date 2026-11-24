// Pinned geometry/timing/resource checks only; no native compilation or duct buffer validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasDuctBufferStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","AnatomyDrawing","SignalDrawing","SecretionDrawing","BufferDrawing","GlyphDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasDuctBuffer" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const trace=source.match(/private fun Path.traceDuct\(\) \{([^}]+)\}/)[1],expand=b=>b.replaceAll("traceDuct()",trace);
const shapes=[...source.matchAll(/private val (\w+) = shape \{([^}]+)\}/g)];assert.equal(shapes.length,13);
for(const [,name,block] of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(expand(block)),name);
}
const branchBlock=source.match(/private val lobuleBranches = listOf\(([\s\S]*?)\n    \)/)[1];
const branches=[...branchBlock.matchAll(/shape \{([^}]+)\}/g)].map(m=>fromCommands(m[1]));
const nativeBranches=[...files[1].slice(files[1].indexOf("static let lobuleBranches")).matchAll(/Path \{ p in([^}]+)\}/g)].map(m=>toCommands(m[1]));
assert.equal(branches.length,3);assert.deepEqual(nativeBranches,branches,"lobule branch curves");
const expectedRoutes=[...source.matchAll(/private val (\w+) = track\(shape \{([^}]+)\}/g)].map(m=>({name:m[1],block:expand(m[2])}));
for(const [name,shape]of[["signalTrack","bloodCourse"],["acidStream","bufferBowel"]])expectedRoutes.push({name,block:shapes.find(m=>m[1]===shape)[2]});
assert.equal(expectedRoutes.length,7);
for(const {name,block} of expectedRoutes){
  const native=files[2].match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
  const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const cmds=[...native.matchAll(/\.init\(kind: \.(line|quad|cubic), points: \[([^\]]+)\]/g)].map(m=>[{line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  assert.deepEqual([["moveTo",...start.slice(1).map(norm)],...cmds],fromCommands(block),name);
}
for(const m of source.matchAll(/fun (\w+)\(t: Float(?:, outlet: Int)?\) = (ease\([^\n]+\))/g)){
  const indexed=m[0].includes("outlet: Int");
  const native=files[0].match(new RegExp("static func "+m[1]+"\\(_ t: Double"+(indexed?", _ outlet: Int":"")+"\\) -> Double \\{ ([^}]+) \\}"))[1];
  assert.equal(norm(native.replaceAll("Double(outlet)","outlet")),norm(m[2]),m[1]+" timing");
}
const callouts=[...source.matchAll(/callout\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeCallouts=[...all.matchAll(/ductBufferCallout\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(callouts.length,16);assert.deepEqual(nativeCallouts,callouts,"callout anchors");
const leaders=[...source.matchAll(/leader\(c, ([^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
const nativeLeaders=[...all.matchAll(/ductBufferLeader\(([^_][^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
assert.equal(leaders.length,5);assert.deepEqual(nativeLeaders,leaders,"duct lumen side pointers");
for(const [key] of callouts)for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
for(const [swift,kotlin] of [
  ["p * p * (3 - 2 * p)","p * p * (3f - 2f * p)"],
  ["for i in 1...5","for (i in 1..5)"],
  ["Double(i) * 60","i * 60f"],
  ["ductBufferAcinus(85, 107, 0.86)","acinus(c, 85f, 107f, .86f)"],
  ["ductBufferAcinus(86, 180, 1)","acinus(c, 86f, 180f, 1f)"],
  ["ductBufferAcinus(93, 254, 0.87)","acinus(c, 93f, 254f, .87f)"],
  ["p - Double(i) * 0.045","p - i * .045f"],
  ["if f >= 0","if (f >= 0f)"],
  ["if i != 9","if (i != 9)"],
  ["0.27 + arrival * 0.73 - 0.085 * Double(i)",".27f + arrival * .73f - .085f * i"],
  ["signal - Double(i) * 0.12","signal - i * .12f"],
  ["if f > 0","if (f > 0f)"],
  ["ductBufferCell(x, 115, 45, 36, active: i == 1 || i == 3)","ductCell(c, x, 115f, 45f, 36f, i == 1 || i == 3)"],
  ["ductBufferCell(x, 207, 45, 36, active: i == 2)","ductCell(c, x, 207f, 45f, 36f, i == 2)"],
  ["secretion(t - Double(j) * 0.09, i)","secretion(t - j * .09f, i)"],
  ["across = min(1, p * 2), downstream = max(0, p * 2 - 1)","val across = (p * 2f).coerceAtMost(1f)"],
  ["top ? 142 + across * (26 + Double(j) * 4) : 217 - across * (27 + Double(j) * 4)","if (top) 142f + across * (26f + j * 4f) else 217f - across * (27f + j * 4f)"],
  ["base + Double(j) * 7 + downstream * 38","base + j * 7f + downstream * 38f"],
  ["0.12 + 0.87 * p - Double(i) * 0.043",".12f + .87f * p - i * .043f"],
  ["ductBufferFluidMark(x, y, scale: 0.74)","fluidMark(c, x, y, .74f)"],
  ["0.05 + Double(i) * 0.129 + Motion.delivery(t) * 0.115",".05f + i * .129f + motion.delivery(t) * .115f"],
  ["x >= 196 && x <= 200 + 110 * mixed","x in 196f..(200f + 110f * mixed)"],
  ["if !reached || i % 2 == 0","if (!reached || i % 2 == 0)"],
  ["Double(i % 3 - 1) * 4, 0.63, muted: reached","(i % 3 - 1) * 4f, .63f, reached"],
  ["0.17 + 0.82 * inlet - Double(i) * 0.19",".17f + .82f * inlet - i * .19f"],
  ["ductBufferFluidMark(x, y, scale: 0.84)","fluidMark(c, x, y, .84f)"],
  ["mixed * 0.77","mixed * .77f"],
  ["x - 12 * s, y - 5 * s, x + 12 * s, y + 5 * s","x - 12f * s, y - 5f * s, x + 12f * s, y + 5f * s"],
  ["line(x - 4 * s, y, x + 3 * s, y + s, edge, 1)","line(c, x - 4f * s, y, x + 3f * s, y + s, if (muted) 0xffb08f67 else acidInk, 1f)"],
  ["width - 3","width - 3f"],["width - 10","width - 10f"],["width - 22","width - 22f"],
  ["y + h * 0.36, mid + 6, y + h * 0.67","y + h * .36f, mid + 6f, y + h * .67f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "if mixed > 0","Routes.mixingTrack.path.trimmedPath(from: 0, to: mixed)",
  "stroke(front, 0xDEC99E, 22); stroke(front, 0xC9D6BB, 14)",
  "muted ? 0xDDC59D : 0xE9B976","muted ? 0xB08F67 : 0xA66539",
  "for i in 0...6","for j in 0...2","top = i != 1",
  "ductBufferOrient(t)","ductBufferSignal(t)","ductBufferSecrete(t)","ductBufferDeliver(t)","ductBufferMixing(t)",
  "atlas-function-pancreatic-duct-buffer-art"
])assert(all.includes(token),token);
const catalogue=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"),"utf8"));
const story=catalogue.stories.find(s=>s.id==="PANCREATIC_DUCT_BUFFER");assert.equal(story.chapters.length,5);
const references=[...source.matchAll(/const val \w+_REFERENCE_URL = "([^"]+)"/g)].map(m=>m[1]);assert.equal(references.length,2);for(const url of references)assert(story.references.some(r=>r.url===url),url);
assert(!all.includes("Timer"));assert(!all.includes("Image("));assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "PANCREATIC_DUCT_BUFFER": GalaxySSIHealthAtlasDuctBufferView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 pancreatic duct source audit: thirteen exact outlines/three branch curves, seven named tracks/seven timing windows, five-cell acini, secretin route and directional secretion, spatial mixing-front attenuation, sixteen bilingual callouts and both references. No native compilation/pixels verified.");
