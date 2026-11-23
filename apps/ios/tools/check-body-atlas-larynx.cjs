// Pinned source/geometry checks only; not native compilation or physiological validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasLarynxStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","View","SuperiorDrawing","FrontalDrawing","SignalDrawing"].map(n=>"GalaxySSIHealthAtlasLarynx"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),view=files[1];
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>Number(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
for(const name of ["outline","vestibule","anteriorRim","airwayWall"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
const frontal=source.match(/private fun frontal[\s\S]*?detail\.rewind\(\)([\s\S]*?)detail\.close\(\)/)[1]+"close()";
assert.deepEqual(toCommands(view.match(/static let frontalLumen = Path \{ p in([\s\S]*?)\n  \}/)[1]),fromCommands(frontal),"frontal lumen");
for(const [swift,kotlin] of [
  ["cycle = 3 * t","val cycle = 3f * t"],
  ["0.5 - 0.5 * cos(2 * .pi * cycle)",".5f - .5f * cos(2.0 * PI * cycle)"],
  ["Self.ease((t - 0.15) / 0.75)","ease((t - .15f) / .75f)"],
  ["vibration * (11 * opening - 3)","vibration * (11f * opening - 3f)"],
  ["0.15 + 0.85 * opening",".15f + .85f * opening"],
  ["Self.ease((t - 0.4) / 0.32)","ease((t - .4f) / .32f)"],
  ["Self.ease((t - 0.75) / 0.25)","ease((t - .75f) / .25f)"],
  ["177 - 0.15 * gap","177f - .15f * gap"],["178 - 0.55 * gap","178f - .55f * gap"],
  ["153 - 0.68 * gap","153f - .68f * gap"],["180 - gap * 0.55","180f - gap * .55f"],
  ["156 - 0.10 * gap","156f - .10f * gap"],
  ["337 - 88 * p : 249 + 88 * p","337f - 88f * p else 249f + 88f * p"],
  ["abs(y - 278) / 9","abs(y - 278f) / 9f"],
  ["unit(cycle - 0.25)","unit(cycle - .25f)"],["270 - 21 * age","270f - 21f * age"],
  ["4 + 24 * age","4f + 24f * age"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["larynxSuperior(frame.gap); larynxFrontal(frame.gap)","if step == 0 || step == 4","up: frame.breath < 0","local.opacity *=","larynxAlpha(pulse.alpha)","larynxAlpha(flow.alpha)","atlas-function-laryngeal-voice-art"])assert(all.includes(token),token);
for(const color of ["F7D9C7","DCA0A5","74898E","4B666F","FFF8E8","ECD2BF","F1C7C4","E8D0B7","E9CBB7","916872","537178","246E76","A26032","DBEEEA"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(larynx_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "LARYNGEAL_VOICE": GalaxySSIHealthAtlasLarynxView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
assert(!all.includes("Timer"));assert(!all.includes("Image("));
console.log("Android #4384 larynx source audit: five exact outlines, shared fold gap, airway and acoustic phase formulas, bilingual labels and project wiring. No native compilation/pixels verified.");
