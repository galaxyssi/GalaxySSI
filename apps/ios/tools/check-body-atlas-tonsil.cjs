// Pinned geometry/timing/resource checks only; no native compilation or tonsillar sampling validation.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process"), assert = require("node:assert/strict");
const root = path.resolve(__dirname, "../../.."), sha = "ab78711d467c013444883dbaeca23c39a601c875";
const source = cp.execFileSync("git", ["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasTonsilStoryView.kt"], {cwd: root, encoding: "utf8"});
const names = ["Motion","Geometry","Routes","View","LocatorDrawing","SectionDrawing","CellularDrawing","TissueDrawing","LabelsDrawing"].map(n => "GalaxySSIHealthAtlasTonsil" + n + ".swift");
const local = n => fs.readFileSync(path.join(root, "apps/ios/GalaxySSI", n), "utf8");
const files = names.map(local), all = files.join("\n");
const norm = s => s.replace(/(\d)f\b/g, "$1").replace(/\s/g, "").replace(/(^|[^\d])\.(\d)/g, "$10.$2");
const fromCommands = block => [...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(((?:x\([^)]*\)|[^()])*)\)|(close)\(\)/g)].map(m => m[3] ? ["close"] : [m[1], ...m[2].split(",").map(norm)]);
const toCommands = block => [...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m => {
  if (m[3]) return ["close"];
  const n = [...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v => norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]], ...(n.length > 2 ? [...n.slice(2), ...n.slice(0,2)] : n)];
});
const traces={};
for(const name of ["traceSmallCrypt","traceFolds","traceCrypt","traceLining"])
  traces[name]=source.match(new RegExp("private fun Path\\."+name+"\\([^)]*\\) \\{([^}]+)\\}"))[1];
const expand=block=>block.replace(/trace(SmallCrypt|Folds|Crypt|Lining)\(([^)]*)\)/g,(m,n,args)=>traces["trace"+n].replace(/if \(!join\) moveTo\(84f, 134f\)/,args.includes("true")?"":"moveTo(84f, 134f)"));
const shapes=[...source.matchAll(/private val (\w+) = shape \{([^}]+)\}/g)].map(m=>({name:m[1],block:expand(m[2])}));
assert.equal(shapes.length,14);
for(const {name,block} of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block),name+" expanded shared trace");
}
const presenterSource=source.match(/process.rewind\(\)([\s\S]*?)stroke\(c, process/)[1].replace(/process\./g,"");
const presenterNative=files[1].match(/static func presenter[\s\S]*?var p = Path\(\)([\s\S]*?)return p/)[1];
assert.deepEqual(toCommands(presenterNative),fromCommands(presenterSource),"dynamic antigen-presenting process");
for(const [name,shape] of [["smallCryptTrack","smallCrypt"],["surfaceTrack","cryptSurface"],["epithelialTrack","epithelialSurface"],["approachTrack",null],["pickupTrack",null]]){
  const block=shape?shapes.find(s=>s.name===shape).block:source.match(new RegExp("private val "+name+" = track\\(shape \\{([^}]+)\\}"))[1];
  const native=files[2].match(new RegExp("static let "+name+" = Route\\(([\\s\\S]*?)\\n  \\]\\)"))[1];
  const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...native.matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(m=>[m[1]==="quad"?"quadTo":"cubicTo",...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  assert.deepEqual([["moveTo",...start.slice(1).map(norm)],...commands],fromCommands(block),name);
}
for(const m of source.matchAll(/fun (\w+)\(t: Float(?:, lag: Float = 0f)?\) = ([^\n]+)/g)){
  const indexed=m[0].includes("lag:"),native=files[0].match(new RegExp("static func "+m[1]+"\\(_ t: Double"+(indexed?", lag: Double = 0":"")+"\\) -> Double \\{ ([^}]+) \\}"))[1];
  assert.equal(norm(native),norm(m[2]),m[1]+" timing");
}
const sourceLabels=[...source.matchAll(/label\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeLabels=[...all.matchAll(/label\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(sourceLabels.length,13);assert.deepEqual(nativeLabels.sort(),sourceLabels.sort(),"bilingual labels");
const leaders=[...source.matchAll(/leader\(c, ([^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
const nativeLeaders=[...all.matchAll(/tonsilLeader\(([^_][^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
assert.equal(leaders.length,9);assert.deepEqual(nativeLeaders,leaders,"callout lines");
const follicles=[...source.matchAll(/follicle\(c, ([^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
const nativeFollicles=[...all.matchAll(/tonsilFollicle\(([^_][^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
assert.equal(follicles.length,12);assert.deepEqual(nativeFollicles,follicles,"lymphoid follicle locations");
for(const [key] of sourceLabels)for(const language of ["en","zh-Hans"])
  assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
for(const [swift,kotlin] of [
  ["p * p * (3 - 2 * p)","p * p * (3f - 2f * p)"],
  ["Double(Int(215 * strength)) / 255","(215f * strength).toInt()"],
  ["radius + 4 * (1 - strength)","radius + 4f * (1f - strength)"],
  ["Double(i % 3 - 1) * rx * 0.36 + Double(i / 3) * 2","(i % 3 - 1) * rx * .36f + i / 3 * 2f"],
  ["(Double(i / 3) - 0.5) * ry * 0.74 + Double(i % 2) * 2","(i / 3 - .5f) * ry * .74f + i % 2 * 2f"],
  ["x - rx * 0.60, y - ry * 0.64, x + rx * 0.70, y + ry * 0.43","x - rx * .60f, y - ry * .64f, x + rx * .70f, y + ry * .43f"],
  ["local.rotate(by: .degrees(-27))","c.rotate(-27f, x, y)"],
  ["-radius, -0.67 * radius, radius, 0.67 * radius","x - r, y - .67f * r, x + r, y + .67f * r"],
  ["if width > 10","if (width > 10f)"],
  ["markers(surfaceTrack, count: 44)","epithelium(c, cryptSurface, surfaceTrack, 44)"],
  ["markers(epithelialTrack, count: 34)","epithelium(c, epithelialSurface, epithelialTrack, 34, 16f)"],
  ["cryptTrace(t)), 0x8F4B66, 2.4","stroke(c, highlight, palatine, 2.4f)"],
  ["Motion.encounter(t, lag: 0.24) * 0.56","HealthAtlasTonsilMotion.encounter(t, .24f) * .56f"],
  ["tonsilAntigen(x + 18, y - 10, 2.5, edge: 0xBC9463)","antigen(c, x + 18f, y - 10f, 2.5f, 0xffbc9463)"],
  ["tonsilAntigen(x, y, 5.2)","antigen(c, x, y, 5.2f)"],
  ["present ? Motion.contact(t) : 0, tip = 172 + 33 * reach","val tip = 172f + 33f * reach"],
  ["tonsilAntigen(tip - 1.5, 225, 3.6)","antigen(c, tip - 1.5f, 225f, 3.6f)"],
  ["Double(Int(200 * (1 - 0.65 * glow))) / 255","(200f * (1f - .65f * glow)).toInt()"],
  ["spread = 6 + 10 * glow","spread = 6f + 10f * glow"],
  ["[221.0, 83]","221f, 56f"],
  ["endAngle: .degrees(start + 56)","83f, 56f"],
  ["tonsilAntigen(x, y, 5 - 1.3 * f)","antigen(c, x, y, 5f - 1.3f * f)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "(1..<count).compactMap","position: Double(index) / Double(count)","static let surfacePoints","static let epithelialPoints",
  "Geometry.cryptSurface, points: Routes.surfacePoints","Geometry.epithelialSurface, points: Routes.epithelialPoints, width: 16",
  "local.translateBy(x: 94, y: 134)","local.translateBy(x: -94, y: -134)","guard strength > 0 else { return }",
  "tonsilCellular(t, present: false)","tonsilCellular(t, present: true)","if step == 4 {","atlas-function-tonsillar-sampling-art"
])assert(all.includes(token),token);
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "TONSILLAR_SAMPLING": GalaxySSIHealthAtlasTonsilView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 tonsil source audit: fourteen expanded outlines/five tracks, exact dynamic presenter, source timing, distinct crypt/fold anatomy, cached epithelial marker positions, antigen uptake/contact arcs, twelve follicles and bilingual anchors. No native compilation/pixels verified.");
