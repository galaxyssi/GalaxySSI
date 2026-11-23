// Pinned source/resource audit only. No Swift, XCTest, native arc orientation or pixel acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=name=>cp.execFileSync("git",["show",sha+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:20_000_000});
const source=show("java/com/galaxyssi/chat/HealthAtlasSignalStoryView.kt").toString();
const motion=local("GalaxySSIHealthAtlasSignalMotion.swift"),view=local("GalaxySSIHealthAtlasSignalView.swift");
const synapse=local("GalaxySSIHealthAtlasSynapseDrawing.swift"),myelin=local("GalaxySSIHealthAtlasMyelinDrawing.swift"),thyroid=local("GalaxySSIHealthAtlasThyroidDrawing.swift");
const all=motion+view+synapse+myelin+thyroid;
const d=source.match(/private val dendrites by lazy \{ listOf\(([\s\S]*?)\n    \) \}/);assert(d);
const dendrites=[...d[1].matchAll(/track \{([^}]+)\}/g)];assert.equal(dendrites.length,2);
const paths={dendriteA:dendrites[0][1],dendriteB:dendrites[1][1]};
for(const name of ["axon","portal","tshRoute","thyroidOut"]){
  const block=source.match(new RegExp("private val "+name+" by lazy \\{ track \\{([^}]+)\\}"));assert(block,name);paths[name]=block[1];
}
for(const [name,block] of Object.entries(paths)){
  const expected=[...block.matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
for(const [swift,kotlin] of [
  ["safePhase(t) * (myelinated ? 0.98 : 0.63)","safePhase(t) * (if (myelinated) .98f else .63f)"],
  ["1 - 0.70 * safePhase(t)","1f - .70f * HealthAtlasFunctionStory.safePhase(t)"],
  ["(t - 0.38 - Double(index) * 0.085) / 0.39","(t - .38f - index * .085f) / .39f"],
  ["f - 27 / length","end - 27f"],["chapter == 3 && t > 0.35","chapter == 3 && t > .35f"],
  ["140 + 21 * min(1, max(0, t / 0.35))","140f + 21f * (t / .35f).coerceIn(0f, 1f)"],
  ["Double(i - 2) * 18 * f","(i - 2) * 18f * f"],["174 + 61 * f","174f + 61f * f"],
  ["18 + 19 * t","18f + 19f * t"],["t * 1.4 - Double(i) * 0.15","t * 1.4f - i * .15f"],
  ["min(1, max(0.05,","coerceIn(.05f, 1f)"],["* 345","* 345f"],
  ["37 + 287 * t","37f + 287f * t"],["1 - abs(head - node) / 17","1f - abs(head - node) / 17f"],
  ["max(34, head - 38)","maxOf(34f, head - 38f)"],["34 + 292 * Motion.axonTravel","34f + 292f * HealthAtlasSignalMotion.axonTravel"],
  ["t * 1.14 + Double(i) / 6","t * 1.14f + i / 6f"],["t * 1.25 + Double(i) / 5","t * 1.25f + i / 5f"],
  ["t * 1.11 + Double(i) / 6","t * 1.11f + i / 6f"],["min(1, t * 1.2)","(t * 1.2f).coerceAtMost(1f)"],
  ["fraction > 0.53","fraction > .53f"],["max(1, Int(4 * drive))","(4f * drive).toInt().coerceAtLeast(1)"],
  ["248 - f * 172","248f - f * 172f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
assert(motion.includes("nodes = [94.0, 160, 226, 292]"));assert(source.includes("nodes = intArrayOf(94, 160, 226, 292)"));
assert(view.includes("trimmedPath(from: CGFloat(start), to: CGFloat(f))"));
assert(motion.includes("static let dendriteLengths"));assert(motion.includes("static let axonLength"));assert(!view.includes("CurveLength"));
const length=local("GalaxySSIHealthAtlasCurveLength.swift");
for(const token of ["polygon - chord <= 2 * part.tolerance","(polygon + chord) / 2","part.tolerance / 2",
  "part.depth < 20","Array(right.reversed())","accuracy / Double(route.commands.count)"])assert(length.includes(token),token);
assert(myelin.includes("startAngle: .degrees(-93), endAngle: .degrees(-93 + turn), clockwise: false"));
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_signal_(\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_signal_'+key+'"'),key);
}
const folder=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasNeuron.imageset");
const filename=JSON.parse(fs.readFileSync(path.join(folder,"Contents.json"))).images[0].filename;
assert(show("res/drawable-nodpi/health_atlas_neuron.png").equals(fs.readFileSync(path.join(folder,filename))));
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-signal"],{cwd:root,stdio:"inherit"});
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "SYNAPTIC_SIGNAL", "MYELIN_SIGNAL", "THYROID_FEEDBACK": GalaxySSIHealthAtlasSignalView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["CurveLength","SignalMotion","SignalView","SynapseDrawing","MyelinDrawing","ThyroidDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 signal source audit: three five-stage courses, six original routes, cached arc-length/27-unit trails, source vesicle release, myelin/node/relative-travel rules, thyroid conversion/feedback, retained neuron and two native vector plates. No native compilation/pixels verified.");
