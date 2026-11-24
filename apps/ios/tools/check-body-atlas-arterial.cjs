// Pinned source geometry/formulas only; not native compilation or hemodynamic validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasArterialStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Shapes","View","LocatorDrawing","TubeDrawing"].map(n=>"GalaxySSIHealthAtlasArterial"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),motion=files[0],tube=files[4];
const block=motion.match(/static let arch = Route([\s\S]*?)\n  \]\)/)[1],first=block.match(/start: \.init\(x: ([\d.]+), y: ([\d.]+)\)/);
const native=[["moveTo",Number(first[1]),Number(first[2])],...[...block.matchAll(/\.init\(kind: \.cubic, points: \[([^\]]+)\]\)/g)].map(m=>["cubicTo",...[...m[1].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>Number(v[1]))])];
const from=source.match(/private val arch = Path\(\).apply \{([^}]+)\}/)[1];
const expected=[...from.matchAll(/(moveTo|cubicTo)\(([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
assert.deepEqual(native,expected,"aortic arch route");
const branches=[...source.matchAll(/branch\(([\d.f, ]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
const nativeBranches=[...motion.slice(motion.indexOf("static let branches")).matchAll(/\.init\(start: \.init\(x: ([\d.]+), y: ([\d.]+)\), commands: \[\.init\(kind: \.quad, points: \[\.init\(x: ([\d.]+), y: ([\d.]+)\), \.init\(x: ([\d.]+), y: ([\d.]+)\)\]/g)].map(m=>m.slice(1).map(Number));
assert.equal(branches.length,3);
assert.deepEqual(nativeBranches,branches.map(([x,y,endX,endY])=>[x,y,x,y-11,endX,endY]));
assert.deepEqual(motion.match(/layerLines = \[([^\]]+)\]/)[1].split(",").map(Number),[0,6,9,16]);
for(const [swift,kotlin] of [
  ["x0 = 28.0, x1 = 332.0, tubeY = 253.0","const val X0 = 28f"],
  ["0.88 * smooth(t)",".88f * smooth(t)"],
  ["abs(safe(location) - (0.06 + 0.88 * t))","abs(HealthAtlasFunctionStory.safePhase(location) - requireNotNull(front(chapter, t)))"],
  ["0.22 + 0.67 * smooth(1 - min(1,distance / 0.36))",".22f + .67f * smooth(1f - (distance / .36f).coerceAtMost(1f))"],
  ["0.8 * (1 - smooth(t))",".8f * (1f - smooth(t))"],
  ["0.82 * sin(t * .pi)",".82f * sin(t * Math.PI)"],
  ["step == 2 ? 0.06 + 0.88 * safe(t) : nil","if (chapter == 2) .06f + .88f * HealthAtlasFunctionStory.safePhase(progress) else null"],
  ["case 1, 2: return 0.76 * t","1, 2 -> .76f * t"],
  ["0.48 * t - 0.17 * t * t",".48f * t - .17f * t * t"],
  ["0.57 * t",".57f * t"],
  ["20 + 12 * expansion(step: step,t: t,location: location)","20f + 12f * HealthAtlasArterialMotion.expansion(step, t, f)"],
  ["(0...24).map","for (i in 0..24)"],
  ["stride(from: 24, through: 0, by: -1)","for (i in 24 downTo 0)"],
  ["tubeY - radius(step: step,t: t,location: f) - offset","TUBE_Y - radius(step, t, f) - offset"],
  ["tubeY + radius(step: step,t: t,location: f) + offset","TUBE_Y + radius(step, t, f) + offset"],
  ["tubeY + side * (radius(step: step,t: t,location: f) + offset)","TUBE_Y + side * (radius(step, t, f) + offset)"],
  ["(distance + Double(index) * 0.25).truncatingRemainder(dividingBy: 1)","(distance + index * .25f) % 1f"],
  ["xAt(0.05 + 0.9 * f)","xAt(.05f + .9f * f)"],
  ["index % 2 == 0 ? -5 : 6","if (index % 2 == 0) -5f else 6f"],
  ["location: 0.24","expansion(step, t, .24f)"],
  ["23 + 7 * expansion","23f + 7f * expansion"],
  ["start: -138,sweep: 48 + 288 * t","-138f, 48f + 288f * t"],
  ["start: 207,sweep: 126","207f, 126f"],
  ["at(ArterialLocator.arch,0.37)","at(archTrack, .37f)"],
  ["t * 0.62 + 0.1","t * .62f + .1f"],
  ["(r + 13) * 0.66","(r + 13f) * .66f"],
  ["(r + 13) * 0.75","(r + 13f) * .75f"],
  ["(r + 1) * 0.71","(r + 1f) * .71f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
const nativeLayers=[...tube.matchAll(/\((\d+),(\d+),(\d+),0x([A-F\d]+),0x([A-F\d]+)\)/g)].map(m=>m.slice(1).map((v,i)=>i<3?Number(v):v.toLowerCase()));
assert.deepEqual(nativeLayers,[[16,199,299,"f4d4bf","dea392"],[11,205,292,"eca8a0","cc7680"],[3,216,285,"f4c0a9","e09487"],[0,223,279,"ffe1ce","efada5"]]);
for(const color of ["995B67","5D797C","984957","9C621E","DD8891","EDA9A3","E9BCA7","DA8991","F5BEA5","FAE0CC","F4BAAB","F5C4B0"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
assert(all.includes("0x26FFF4E8"));assert(source.includes("0x26fff4e8"));
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(arterial_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["if let center = GalaxySSIHealthAtlasArterialMotion.front","if let distance = GalaxySSIHealthAtlasArterialMotion.flowTravel","for f in [0.0,1]","side * r,x,ArterialTube.tubeY + side * (r + 16)","closed: true","if step != 0","if step == 0"])assert(all.includes(token),token);
assert(all.includes("atlas-function-arterial-pulse-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "ARTERIAL_PULSE": GalaxySSIHealthAtlasArterialView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 arterial source audit: arch/three branches, four 25-sample layers, independent wave/flow formulas, coupled cross-section, open cutaway edges and bilingual labels. No native compilation/pixels verified.");
