// Pinned source/geometry wiring only; no native playback or physiological acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCardiacSignalStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasCardiacSignalMotion.swift"),view=local("GalaxySSIHealthAtlasCardiacSignalView.swift"),drawing=local("GalaxySSIHealthAtlasCardiacSignalDrawing.swift"),all=motion+view+drawing;
const sourceRoutes=[...source.slice(source.indexOf("private val routes"),source.indexOf("private val wall")).matchAll(/path \{([^}]+)\}/g)].map(m=>[...m[1].matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(c=>c[1].split(",").map(v=>Number(v.trim().replace(/f$/,"")))));
const nativeRoutes=[...motion.matchAll(/route\((\d+), (\d+), ([^\n]+?)\)(?=,|\n)/g)].map(m=>[[Number(m[1]),Number(m[2])],...JSON.parse("["+m[3]+"]")]);
assert.equal(nativeRoutes.length,5);assert.deepEqual(nativeRoutes,sourceRoutes);
for(const name of ["wall","leftVentricle","rightVentricle"]){
  const from=source.match(new RegExp("private val "+name+" = path \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="move"?["moveTo",...n]:[m[1]==="addCurve"?"cubicTo":"quadTo",...n.slice(2),...n.slice(0,2)];
  });assert.deepEqual(actual,expected,name);
}
for(const [swift,kotlin] of [
  ["step == 3 ? ease : step == 4 ? 1 - ease : 0","4 -> 1f - ease"],
  ["step == 0 && (0...1).contains(route)","step == 0 && index in 0..1"],
  ["min(1, t / 0.56)","(t / .56f).coerceAtMost(1f)"],
  ["(3...4).contains(route) && t >= 0.56","index in 3..4 && t >= .56f"],
  ["(t - 0.56) / 0.44","(t - .56f) / .44f"],
  ["7 + 2.4 * wave(t)","7f + 2.4f * wave(t)"],["7 + 2.5 * wave(t)","7f + 2.5f * wave(t)"],
  ["33 + 33 * shortening","33f + 33f * shortening"],["326 - 33 * shortening","326f - 33f * shortening"],
  ["(width - 56) * Double(i) / 3","(width - 56f) * i / 3f"],
  ["previous + 29, 268","previous + 29f, cy - 5f"],["center - 14, 273, center + 14","center - 14f, cy, center + 14f"],
  ["(t - 0.72) / 0.28","(t - .72f) / .28f"],
  ["max(0, shortening - Double(i) * 0.06)","(shortening - i * .06f).coerceAtLeast(0f)"],
  ["252 + 15 * f","252f + 15f * f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [".trimmedPath(from: 0, to: CGFloat(progress))","at(route, progress)","if progress > 0","if step == 2 && t > 0.72","for i in 0...3","for i in 0...5"])assert(all.includes(token),token);
for(const color of ["975367","4F5578","E79B45","975E80","F7C6B2","D08083","FFE2D0","E5A8A4","F5D8C7","B0CEC4","BF8063"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(cardiac_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-cardiac-excitation-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "CARDIAC_EXCITATION": GalaxySSIHealthAtlasCardiacSignalView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["CardiacSignalMotion","CardiacSignalView","CardiacSignalDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 cardiac-signal source audit: five conduction tracks, three heart outlines, sequential trunk/branch timing, node pulses, cell shortening/recovery and calcium/filament scenes with bilingual labels. No native compilation/pixels verified.");
