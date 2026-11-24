// Pinned source geometry/formulas only; not native compilation or filtration validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPodocyteStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","StoryView","WallDrawing","FocusDrawing","ParticlesDrawing","LabelsDrawing"].map(n=>"GalaxySSIHealthAtlasPodocyte"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),geometry=files[1];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
const flatten=s=>s.replace(/(?:Motion\.)?(footY|wallY)\((\w+)f?\)/g,(_,name,arg)=>name+"_"+arg.replace(/f$/,""));
const fromCommands=block=>[...flatten(block).matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...flatten(block).matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
for(const name of ["capsule","tuft","tuftBranch","foot","podocyte"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
const nativeTrack=block=>{
  const first=flatten(block).match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...flatten(block).matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]\)/g)].map(m=>[
    {cubic:"cubicTo",quad:"quadTo",line:"lineTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))
  ]);
  return [["moveTo",norm(first[1]),norm(first[2])],...commands];
};
assert.deepEqual(nativeTrack(geometry.match(/static let tuftFlow = Route([\s\S]*?)\n  \]\)/)[1]),fromCommands(source.match(/private val tuft = Path\(\).apply \{([^}]+)\}/)[1]),"tuft track");
assert.deepEqual(nativeTrack(geometry.match(/static func filtrationRoute([\s\S]*?)\n  \}/)[1]),fromCommands(source.match(/private fun filtrationRoute[\s\S]*?Path\(\).apply \{([^}]+)\}/)[1]),"filtration route");
for(const [method,nativeMethod] of [["water","podocyteWater"],["solute","podocyteSolute"]]){
  const from=source.match(new RegExp("private fun "+method+"[\\s\\S]*?brush.rewind\\(\\)([\\s\\S]*?)brush.close\\(\\)"))[1]+"close()";
  const to=files[5].match(new RegExp("func "+nativeMethod+"[\\s\\S]*?var p = Path\\(\\);([\\s\\S]*?)fill\\(p"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),method+" glyph");
}
const sourceLabels=[...source.matchAll(/label\(c, R\.string\.health_atlas_(\w+), ([\d.f, ]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
const nativeLabels=[...all.matchAll(/label\("([^"]+)",([\d.,]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
assert.equal(sourceLabels.length,13);assert.deepEqual(nativeLabels,sourceLabels,"label positions");
const leaderNorm=s=>norm(s.replaceAll("PodocyteLabelAnchor.","").replaceAll("feet.last()","lastFoot").replaceAll("feet[7]","lastFoot").replaceAll("slits.last()","lastSlit").replaceAll("slits[6]","lastSlit"));
const fromLeaders=[...source.matchAll(/leader\(c, (\d[^\n]+)\)/g)].map(m=>m[1].split(",").map(leaderNorm)).sort();
const toLeaders=[...all.matchAll(/podocyteLeader\((\d[^\n]+)\)/g)].map(m=>m[1].split(",").map(leaderNorm)).sort();
assert.equal(fromLeaders.length,6);assert.deepEqual(toLeaders,fromLeaders,"leader anchors");
const dataset=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"),"utf8"));
const story=dataset.stories.find(s=>s.id==="PODOCYTE_BARRIER");
const chapters=[...source.matchAll(/\w+\(R\.string\.(health_atlas_podocyte_story_\w+), R\.string\.(health_atlas_podocyte_story_\w+)\)/g)].map(m=>({title:m[1],caption:m[2]}));
assert.equal(chapters.length,5);assert.deepEqual(story.chapters,chapters);assert.equal(story.durationMs,20000);
assert.deepEqual(story.references.map(r=>r.url),[source.match(/STRUCTURE_SOURCE = "([^"]+)"/)[1],source.match(/ALBUMIN_SOURCE = "([^"]+)"/)[1]]);
for(const [swift,kotlin] of [
  ["case 1: return f * f","FENESTRAE -> f * f"],
  ["case 2: return 1 - (1 - f) * (1 - f)","BASEMENT -> 1f - (1f - f) * (1f - f)"],
  ["ease(safe((f - 0.08) / 0.84))","ease(((f - .08f) / .84f).coerceIn(0f, 1f))"],
  ["left = 24.0, right = 244.0, matrixDepth = 13.0","private const val MATRIX_DEPTH = 13f"],
  ["43 + 25.5 * Double($0)","43f + 25.5f * it"],
  ["39.5 + 27 * Double($0)","39.5f + 27f * it"],
  ["feet[$0] + 13.5","feet[it] + 13.5f"],
  ["fenestrae[i - 1] + 3.5","fenestrae[i - 1] + 3.5f"],
  ["fenestrae[i] - 3.5","fenestrae[i] - 3.5f"],
  ["173 - 0.0008 * dx * dx","173f - .0008f * dx * dx"],
  ["max(0,1 - abs(x - 81) / 15)","(1f - abs(x - 81f) / 15f).coerceAtLeast(0f)"],
  ["wallY(x) - 12 - 12 * bulge * bulge","wallY(x) - 12f - 12f * bulge * bulge"],
  ["max(1,Int((right - left) / 2))","((right - left) / 2f).toInt().coerceAtLeast(1)"],
  ["Double(i) / Double(samples)","* i / samples"],
  ["stride(from: samples, through: 0, by: -1)","for (i in samples downTo 0)"],
  ["left - 13 + (45 + Double(index) * 76 + f * 190)","LEFT - 13f + (45f + i * 76f + f * 190f)"],
  ["left - 7 + (23 + Double(index) * 57 + f * 157)","LEFT - 7f + (23f + i * 57f + f * 157f)"],
  ["f * 1.27 + Double(index) / 3","f * 1.27f + i / 3f"],
  ["p + 0.16","p + .16f"],
  ["f.map { 11 + 2 * wave($0 - 0.25) } ?? 11","if (f == null) 11f else 11f + 2f * wave(f - .25f)"],
  ["f == nil ? 1.2 : 1.7","if (f == null) 1.2f else 1.7f"],
  ["f * 0.72 + Double(i) * 0.33","f * .72f + i * .33f"],
  ["footY(x - 4.6) + 3.5","footY(x - 4.6f) + 3.5f"],
  ["footY(x + 4.6) + 3.5","footY(x + 4.6f) + 3.5f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["52666B","9D5863","A26169","8A7051","705580","537A73","514F64","30759D","327C6A","886521","F4CBC2","CCDFE2","FBDDD1","D38F94","F6E7C3","DBC096","C6B2D6","E5D7ED","F5F5E9","93A49B","E6ACAC","EAB5B4","875267","9C3F51","BFA681","B16D80","874E62","AC8ABD","856397","CDB8DC","ADC9BF","9F4960","A1732E","69458C","D1838B","E9AAA6","BA707D","C7A05D","D4B071","E4C487","88BED5"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
assert(source.includes("0x00f0bbb5"));assert(source.includes("0x00ddebed"));
assert(all.includes("Self.color(0xF0BBB5).opacity(0)"));assert(all.includes("Self.color(0xDDEBED).opacity(0)"));
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(podocyte_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["podocyteGlomerulus(step == 0 ? f : nil)","if let f","podocyteBlood(step == 4 ? f : 0)","Int(255 * PodocyteFocus.safe(alpha))",
  "PodocyteFocus.slits[6] - (PodocyteFocus.slits[6] - PodocyteFocus.slits[0]) * f","local.clip(to: Path(CGRect(x: PodocyteFlow.left, y: 109, width: PodocyteFlow.right - PodocyteFlow.left, height: 46)))",
  "pore: Motion.fenestrae[0],slit: Motion.slits[0],exit: 33","pore: Motion.fenestrae[7],slit: Motion.slits[6],exit: 234",
  "at(PodocyteParticles.leftFlow,phases.p) { podocyteWater","at(PodocyteParticles.rightFlow,phases.p) { podocyteSolute",
  "at(PodocyteParticles.leftFlow,phases.q) { podocyteSolute","at(PodocyteParticles.rightFlow,phases.q) { podocyteWater"
])assert(all.includes(token),token);
const filtrate=files[5].slice(files[5].indexOf("func podocyteFiltrate"),files[5].indexOf("func podocyteRedCell"));
assert(!filtrate.includes("podocyteProtein"));assert(!filtrate.includes("podocyteRedCell"));
assert(all.includes("atlas-function-podocyte-barrier-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "PODOCYTE_BARRIER": GalaxySSIHealthAtlasPodocyteStoryView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
const structure=local("GalaxySSIHealthAtlasPodocyteView.swift");
assert(structure.includes("let stage: Int")&&structure.includes("let stages: [String]"),"retain the separate legacy structure entry point");
assert.equal(project.split("GalaxySSIHealthAtlasPodocyteView.swift in Sources").length-1,2,"no duplicate legacy compilation");
console.log("Android #4384 podocyte source audit: exact contours/glyphs/routes, source stage order/timing/references, sampled layers/gaps, transparent endpoints, distinct blood/filtrate particles and bilingual anchors. No native compilation/pixels verified.");
