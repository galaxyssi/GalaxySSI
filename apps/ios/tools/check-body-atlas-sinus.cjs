// Pinned geometry/timing/resource checks only; no native compilation or sinus clearance validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSinusDrainageStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","LocatorDrawing","SectionDrawing","ClearanceDrawing","SecretionDrawing","LabelsDrawing","Drawing"].map(n => "GalaxySSIHealthAtlasSinus" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)].map(m=>({name:m[1],block:m[2]}));
assert.equal(shapes.length,17);
const locator=source.slice(source.indexOf("private fun locate("),source.indexOf("private fun sectionArt("));
const details=[...locator.matchAll(/scratch.rewind\(\)([\s\S]*?)stroke\(c, scratch/g)].map(m=>m[1]);
shapes.push({name:"faceDetails",block:details[0]},{name:"noseDetails",block:details[1]});
const secretion=source.slice(source.indexOf("private fun secretionDetail("),source.indexOf("private fun detailCilium("));
shapes.push({name:"secretoryCell",block:secretion.match(/scratch.rewind\(\)([\s\S]*?)area\(c, scratch/)[1]});
for(const {name,block} of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block),name);
}
const ascent=source.match(/private val ascentTrack = track\(Path\(\).apply \{([^}]+)\}/)[1];
const exit=source.match(/private val exitTrack = track\(Path\(outlet\).apply \{([^}]+)\}/)[1];
for(const [name,block] of [["ascent",ascent],["exit",shapes.find(s=>s.name==="outlet").block+exit]]){
  const native=files[2].match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
  const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...native.matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(m=>[m[1]==="quad"?"quadTo":"cubicTo",...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  assert.deepEqual([["moveTo",...start.slice(1).map(norm)],...commands],fromCommands(block),name+" route");
}
const sourceLabels=[...source.matchAll(/label\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeLabels=[...all.matchAll(/label\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(sourceLabels.length,4);assert.deepEqual(nativeLabels,sourceLabels,"view labels");
const leaders=[...source.matchAll(/leader\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeLeaders=[...all.matchAll(/sinusLeader\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(leaders.length,10);assert.deepEqual(nativeLeaders,leaders,"ten leader anchors");
for(const key of new Set([...source.matchAll(/R.string.health_atlas_(\w+)/g)].map(m=>m[1])))for(const language of ["en","zh-Hans"])
  assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
for(const [swift,kotlin] of [
  ["Double(group) * 0.21, Double(group) * 0.21 + 0.37","group * .21f, group * .21f + .37f"],
  ["sin(.pi * p)","sin(PI.toFloat() * p)"],
  ["ease(interval(t, 0.10, 0.88))","ease(interval(t, .10f, .88f))"],
  ["0.07 + 0.21 * Double(index), 0.42 + 0.21 * Double(index)",".07f + .21f * index, .42f + .21f * index"],
  ["2 * Double.pi * (2.65 * phase(t) - Double(index) * 0.09)","2f * PI.toFloat() * (2.65f * phase(t) - index * .09f)"],
  ["0.35 + 0.65 * cos(angle)",".35f + .65f * cos(angle)"],
  ["0.03 + 0.17 * Double(index), 0.62 + 0.17 * Double(index)",".03f + .17f * index, .62f + .17f * index"],
  ["0.03 + 0.14 * Double(index), 0.77 + 0.10 * Double(index)",".03f + .14f * index, .77f + .10f * index"],
  ["p * p * (3 - 2 * p)","p * p * (3f - 2f * p)"],
  ["1.25 + emphasis * 2.5","1.25f + emphasis * 2.5f"],
  ["0.05 + Double(i) * 0.057",".05f + i * .057f"],
  ["Motion.ciliumBend(t, anchor.index) * 4","HealthAtlasSinusDrainageMotion.ciliumBend(t, i) * 4f"],
  ["Double(point.x) - 2 * tangentY","position[0] - 2f * tangent[1]"],
  ["Double(point.y) + 2 * tangentX","position[1] + 2f * tangent[0]"],
  ["x + 3 * tangentY, y: y - 3 * tangentX","x + 3f * tangent[1], y - 3f * tangent[0]"],
  ["x + 6 * tangentY + bend * tangentX, y: y - 6 * tangentX + bend * tangentY","x + 6f * tangent[1] + bend * tangent[0], y - 6f * tangent[0] + bend * tangent[1]"],
  ["head - 0.10, head, 0x12695F, 4.4","head - .10f, head, mucusInk, 4.4f"],
  ["head - 0.12, head, 0x12695F, 4.4","head - .12f, head, mucusInk, 4.4f"],
  ["bottom - (bottom - top) * GalaxySSIHealthAtlasSinusMotion.heightReveal(t)","bottom - (bottom - top) * HealthAtlasSinusDrainageMotion.heightReveal(t)"],
  ["if t > 0.21","if (t > .21f)"],
  ["8 + 3 * GalaxySSIHealthAtlasSinusMotion.heightReveal(t)","8f + 3f * HealthAtlasSinusDrainageMotion.heightReveal(t)"],
  ["local.translateBy(x: 108, y: 4)","c.translate(108f, 4f)"],
  ["local.scaleBy(x: 0.43, y: 0.43)","c.scale(.43f, .43f)"],
  ["if i != 3","if (i != 3)"],
  ["index: i * 4 + j","i * 4 + j, t"],
  ["ciliumBend(t * 0.43, index) * 6","ciliumBend(t * .43f, index) * 6f"],
  ["x: x + bend * 0.5, y: 217","x + bend * .5f, 217f"],
  ["244 + 4 * Double(i) - (40 + 4 * Double(i)) * release","244f + 4f * i - (40f + 4f * i) * release"],
  ["(release - 0.78) / 0.22","(release - .78f) / .22f"],
  ["x - 3 - 10 * spread, y - 3.9, x + 3 + 10 * spread, y + 3.9","x - 3f - 10f * spread, y - 3.9f, x + 3f + 10f * spread, y + 3.9f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "CiliumAnchor(index: i, sample: sample)","static let cilia: [CiliumAnchor] = (0...15).compactMap",
  "local.translateBy(x: 180, y: 0); local.scaleBy(x: -1, y: 1)",
  "Motion.highlight(t, 0)","Motion.highlight(t, 1)","Motion.highlight(t, 2)","Motion.highlight(t, 3)",
  "let start = max(0, from)","guard to > start else { return }","trimmedPath(from: start, to: to)",
  "sinusFilm(Routes.ascent, 0, 1, 0x9BC8B6, 4)","sinusFilm(Routes.ascent, 0.06, 1, 0x9BC8B6, 3.3)",
  "sinusFilm(Routes.exit, 0, 1, 0x9BC8B6, 4)","for anchor in Routes.cilia",
  "sinusCrossSection(t, step: step)","sinusSecretion(t)","atlas-function-sinus-drainage-art"
])assert(all.includes(token),token);
const catalogue=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"),"utf8"));
const story=catalogue.stories.find(s=>s.id==="SINUS_DRAINAGE");assert.equal(story.chapters.length,5);
for(const url of [...source.matchAll(/const val \w+_REFERENCE_URL = "([^"]+)"/g)].map(m=>m[1]))assert(story.references.some(r=>r.url===url),url);
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "SINUS_DRAINAGE": GalaxySSIHealthAtlasSinusView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 sinus source audit: twenty exact outlines/two independent tracks, cached tangent anchors, source highlight/secretion/ciliary timing, finite mucus trails, detail zoom and fourteen bilingual labels/leaders with both references. No native compilation/pixels verified.");
