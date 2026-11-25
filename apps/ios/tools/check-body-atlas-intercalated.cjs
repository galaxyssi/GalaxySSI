// Pinned geometry/timing/resource checks only; no native compilation or intercalated transport validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasIntercalatedStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","DuctDrawing","TransportDrawing","GlyphDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasIntercalated" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(shapes.length,5);
for(const [,name,block] of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block),name);
}
const routes=[...source.matchAll(/private val (\w+) = track\(Path\(\).apply \{([^}]+)\}/g)];
assert.equal(routes.length,2);
for(const [,name,block] of routes){
  const native=files[2].match(new RegExp("static let "+name+" = GalaxySSIHealthAtlasSectionLesson.Route\\(([\\s\\S]*?)\\n  \\]\\)"))[1];
  const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...native.matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(m=>[m[1]==="quad"?"quadTo":"cubicTo",...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  assert.deepEqual([["moveTo",...start.slice(1).map(norm)],...commands],fromCommands(block),name);
}
const glyph=source.match(/private fun bicarbonate[\s\S]*?brush.rewind\(\)([\s\S]*?)ink\(baseInk\)/)[1];
const nativeGlyph=files[6].match(/func intercalatedBicarbonate[\s\S]*?var p = Path\(\)([\s\S]*?)fill\(p/)[1];
assert.deepEqual(toCommands(nativeGlyph),fromCommands(glyph),"bicarbonate diamond");
const labels=[...source.matchAll(/label\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeLabels=[...all.matchAll(/label\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(labels.length,12);assert.deepEqual(nativeLabels,labels,"legend and compartment labels");
const leaders=[...source.matchAll(/leader\(c, ([^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
const nativeLeaders=[...all.matchAll(/intercalatedLeader\(([^_][^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
assert.equal(leaders.length,8);assert.deepEqual(nativeLeaders,leaders,"leader endpoints");
const nuclei=[...source.matchAll(/nucleus\(c, ([^)]+)\)/g)].map(m=>m[1].split(",").slice(0,2).map(norm));
const nativeNuclei=[...all.matchAll(/intercalatedNucleus\(([^_][^)]+)\)/g)].map(m=>m[1].split(",").slice(0,2).map(norm));
assert.equal(nuclei.length,4);assert.deepEqual(nativeNuclei,nuclei,"principal/type-A nuclei");
for(const [key] of labels)for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
assert(files[0].includes("case orientation, protonSecretion, bicarbonateReturn, luminalBuffers, acidExcretion"));
for(const [swift,kotlin] of [
  ["f * f * (3 - 2 * f)","f * f * (3f - 2f * f)"],
  ["case .protonSecretion: return f * f","PROTON_SECRETION -> f * f"],
  ["f * (2 - f)","f * (2f - f)"],
  ["(f - 0.07) / 0.86","(f - .07f) / .86f"],
  ["case .acidExcretion: return f","ACID_EXCRETION -> f"],
  ["(f - 0.14) / 0.86","(f - .14f) / .86f"],
  ["from + (to - from) * f","from + (to - from) * f"],
  ["f * 1.22 + Double(index) * 0.31 + 0.08","f * 1.22f + i * .31f + .08f"],
  ["f * 0.91 + Double(index) * 0.49 + 0.12","f * .91f + i * .49f + .12f"],
  ["(16 + Double(i) * 64 + f * 132).truncatingRemainder(dividingBy: 320)","(16f + i * 64f + f * 132f) % 320f"],
  ["(Double(i) * 47 + f * 148).truncatingRemainder(dividingBy: 217)","(i * 47f + f * 148f) % 217f"],
  ["min(1, f / 0.54)","(f / .54f).coerceAtMost(1f)"],
  ["meeting = phosphate ? 230.0 : 211.0","meeting = if (phosphate) 230f else 211f"],
  ["startX = phosphate ? 186.0 : 169.0","startX = if (phosphate) 186f else 169f"],
  ["y = phosphate ? 115.0 : 88.0, rise = phosphate ? 9.0 : 16.0","rise = if (phosphate) 9f else 16f"],
  ["Motion.mix(startX, meeting + 4, approach), Motion.mix(y + rise, y - 4, approach)","mix(startX, meeting + 4f, approach), mix(y + rise, y - 4f, approach)"],
  ["Motion.mix(startX + 22, meeting, approach)","mix(startX + 22f, meeting, approach)"],
  ["Motion.mix(meeting, 313, (f - 0.54) / 0.46)","mix(meeting, 313f, (f - .54f) / .46f)"],
  ["(Double(i) * 43 + f * 153).truncatingRemainder(dividingBy: 174)","(i * 43f + f * 153f) % 174f"],
  ["if bound { intercalatedProton(x + 4, y - 4) }","if (bound) proton(c, x + 4f, y - 4f)"],
  ["rounded(145, 132, 157, 143, 3, 0xA02E40)","rounded(c, 145f, 132f, 157f, 143f, 3f, protonInk)"],
  ["rounded(194, 224, 208, 233, 2.5, 0x246E61)","rounded(c, 194f, 224f, 208f, 233f, 2.5f, baseInk)"],
  ["131 + 0.01 * (x - 167) * (x - 167)","131f + .01f * (x - 167f) * (x - 167f)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "clipped.clip(to: capillary)","CGRect(x: 116, y: 79, width: 215, height: 48)","CGRect(x: 164, y: 105, width: 173, height: 23)",
  "art.intercalatedCapillary(stage == .acidExcretion ? f : 0)","art.intercalatedBuffer(f, phosphate: false)",
  "art.intercalatedBuffer(GalaxySSIHealthAtlasIntercalatedMotion.phosphateDelay(f), phosphate: true)",
  "bound: false","bound: true","phosphate: i % 2 != 0","if approach < 1",
  "arrow(153, 127, 164, 110","arrow(203, 238, 221, 265","arrow(180, 104, 326, 104",
  "rounded(x - 6, y - 3.5, x + 5.5, y + 3.5, 1.5, 0x66517D)","disc(x, y, 4.7, 0xD5AC66",
  "atlas-function-intercalated-balance-art"
])assert(all.includes(token),token);
const catalogue=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"),"utf8"));
const story=catalogue.stories.find(s=>s.id==="INTERCALATED_BALANCE");
const chapters=[...source.matchAll(/\w+\(\s*R.string.(health_atlas_intercalated_story_\w+),\s*R.string.(health_atlas_intercalated_story_\w+),?\s*\)/g)].map(m=>({title:m[1],caption:m[2]}));
assert.equal(chapters.length,5);assert.deepEqual(story.chapters,chapters);
assert.equal(story.durationMs,Number(source.match(/DURATION_MS = ([\d_]+)L/)[1].replaceAll("_","")));
const references=[...source.matchAll(/const val (?:POLARITY_SOURCE|BUFFER_SOURCE) = "([^"]+)"/g)].map(m=>m[1]);assert.equal(references.length,2);
for(const url of references)assert(story.references.some(r=>r.url===url),url);
assert(!all.includes("Timer"));assert(!all.includes("Image("));assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "INTERCALATED_BALANCE": GalaxySSIHealthAtlasIntercalatedView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 intercalated source audit: five exact compartments/two directional routes, source nonlinear progress, distinct ion/buffer glyphs, continuous binding/outflow, clipped independent blood/luminal streams, membrane symbols, twelve bilingual labels and references. No native compilation/pixels verified.");
