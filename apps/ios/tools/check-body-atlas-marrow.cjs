// Pinned source geometry/formulas only; not native compilation or hematopoiesis validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMarrowStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","View","TissueDrawing","CellDrawing","RenewalDrawing","LineageDrawing"].map(n=>"GalaxySSIHealthAtlasMarrow"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),geometry=files[1];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/Marrow(?:Vessel|LineageTime)\./g,"").replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
for(const name of ["trabecula","stroma","megakaryocyteNucleus"]){
  const from=name==="megakaryocyteNucleus"?source.match(/private fun megakaryocyte[\s\S]*?detail.rewind\(\)([\s\S]*?)detail.close\(\)/)[1]+"close()":source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
const membraneSource=source.match(/private fun drawSelfRenewal[\s\S]*?detail.rewind\(\)([\s\S]*?)detail.close\(\)/)[1]+"close()";
const membraneNative=geometry.match(/static func renewal[\s\S]*?Path \{ p in([\s\S]*?)\n    \}/)[1];
assert.deepEqual(toCommands(membraneNative),fromCommands(membraneSource),"shared membrane");
const cellSource=source.match(/val marrowCells = floatArrayOf\(([\s\S]*?)\n        \)/)[1].split(",").map(s=>s.trim()).filter(Boolean).map(s=>Number(s.replace(/f$/,"")));
const cellNative=[...geometry.slice(geometry.indexOf("static let marrowCells"),geometry.indexOf("static func renewal")).matchAll(/\.init\(x: ([-\d.]+), y: ([-\d.]+)\)/g)].flatMap(m=>m.slice(1).map(Number));
assert.equal(cellSource.length,56);assert.deepEqual(cellNative,cellSource,"28 marrow positions");
for(const name of ["erythroidRoute","megakaryocyteRoute"]){
  const expected=source.match(new RegExp("private val "+name+" = route\\(([^)]+)\\)"))[1].split(",").map(norm);
  const block=geometry.match(new RegExp("static let "+name+" = Route([\\s\\S]*?)\\n  \\]\\)"))[1];
  const points=[...block.matchAll(/[xy]: ([-\d.]+)/g)].map(m=>m[1]);
  assert.deepEqual(points,["105","181",...expected],name);
}
const sourceCallouts=[...source.matchAll(/callout\(c, R\.string\.health_atlas_(\w+),([\s\S]*?)\)(?=\r?\n|;)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
const nativeCallouts=[...all.matchAll(/marrowCallout\("([^"]+)",([\s\S]*?)\)(?=\r?\n|;)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
assert.equal(sourceCallouts.length,14);assert.deepEqual(nativeCallouts,sourceCallouts,"callout anchors");
for(const [swift,kotlin] of [
  ["CGRect(x: 22, y: 74, width: 316, height: 210)","c.clipRect(22f, 74f, 338f, 284f)"],
  ["231 + 11 * sin(((x - 20) / 320 + 0.13) * 2 * .pi)","231f + 11f * wave((x - 20f) / 320f + .13f)"],
  ["Point(x: 18,y: vesselY(18) - 26)","moveTo(18f, vesselY(18f) - 26f)"],
  ["stride(from: 22, through: 342, by: 4)","for (x in 22..342 step 4)"],
  ["stride(from: 342, through: 18, by: -4)","for (x in 342 downTo 18 step 4)"],
  ["132 * separation","132f * separation"],["34 - 6 * separation","34f - 6f * separation"],
  ["distance < 2 * radius","distance < 2f * radius"],
  ["max(2,radius - distance * 0.5)","maxOf(2f, radius - distance * .5f)"],
  ["min(radius * 0.55,distance * 0.38)","minOf(radius * .55f, distance * .38f)"],
  ["progress(t,start: 0.14,end: 0.86)","progress(t, .14f, .86f)"],
  ["progress(t,start: 0.13,end: 0.52)","progress(t, .13f, .52f)"],
  ["progress(t,start: 0.03,end: 0.44)","progress(t, .03f, .44f)"],
  ["progress(t,start: 0.29,end: 0.87)","progress(t, .29f, .87f)"],
  ["176 - 3 * extrude","176f - 3f * extrude"],
  ["176 + 29 * extrude","176f + 29f * extrude"],
  ["169 + 13 * extrude","169f + 13f * extrude"],
  ["12 - 5 * condense","12f - 5f * condense"],
  ["progress(t,start: 0,end: 0.25)","progress(t, 0f, .25f)"],
  ["progress(t,start: 0.18,end: 0.51)","progress(t, .18f, .51f)"],
  ["(t - 0.44) / 0.56","(t - .44f) / .56f"],
  ["fromX + (entryX - fromX) * approach + (endX - entryX) * flow","fromX + (entryX - fromX) * approach + (endX - entryX) * flow"],
  ["(vesselY(x) - 4 - fromY) * cross","(vesselY(x) - 4f - fromY) * cross"],
  ["4 * cross * (1 - cross)","4f * cross * (1f - cross)"],
  ["scaleX: 1 - 0.28 * squeeze,scaleY: 1 + 0.16 * squeeze","c.scale(1f - .28f * squeeze, 1f + .16f * squeeze)"],
  ["8 + 344 * (flow * 0.55 + Double(index) / 7)","8f + 344f * ((flow * .55f + i / 7f)"],
  ["Double((index * 2) % 6)","val radius = 5.5f + (i % 6)"],
  ["flow: t * 0.54","drawMarrow(c, t * .54f"],
  ["flow: t * 1.15","drawMarrow(c, t * 1.15f"],
  ["(t - 0.28) / 0.72,fromX: 137,fromY: 175,entryX: 157,endX: 265","(t - .28f) / .72f, 137f, 175f, 157f, 265f"],
  ["Int(62 + 135 * focus)","(62f + 135f * focus).toInt()"],
  ["frame.extrude > 0.55","extrude > .55f"],
  ["fraction >= 0.96 ? color : MarrowLineage.leader","if (f >= .96f) color else leaderInk"],
  ["baseline + (ty > baseline ? 6 : -15)","baseline + if (ty > baseline) 6f else -15f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["AD6973","9E637B","AE8468","746477","A95060","775583","FFF0E5","EBC8C3","FFEDC9","DDB994","F7DDD9","DCA0A5","E4DEF0","B498C3","F5D1DF","CD8EA5","E7DEED","BD99B6","EAC1C7","CD9DA9","B587A0","93688F","AB81A0","E7A7B2","E5A5AD","F9EAF4","956B9B","744D7D","C9ACD2","D28185","EDB1AC","D38588","E49AA5","C18393","B9ADB6"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(marrow_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["local.clip(to: MarrowTissue.field)","local.clip(to: MarrowTissue.lumen)","if frame.shared","if splitting > 0","local.translateBy(x: 0, y: 170)",
  "path.trimmedPath(from: 0,to: CGFloat(fraction))","local.scaleBy(x: frame.scaleX, y: frame.scaleY)","wash.opacity *=","release ? 7 : 9"
])assert(all.includes(token),token);
assert(all.includes("atlas-function-marrow-hematopoiesis-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "MARROW_HEMATOPOIESIS": GalaxySSIHealthAtlasMarrowView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 marrow source audit: exact bone/stroma/nuclear/shared-membrane paths, 28 positions/two lineage routes, sampled sinusoid, delayed release/shape windows and bilingual anchors. No native compilation/pixels verified.");
