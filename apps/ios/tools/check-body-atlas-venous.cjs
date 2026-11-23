// Pinned geometry/source wiring only; no native compilation or physiological acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasVenousReturnStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasVenousMotion.swift"),view=local("GalaxySSIHealthAtlasVenousView.swift"),calf=local("GalaxySSIHealthAtlasVenousCalfDrawing.swift"),drawing=local("GalaxySSIHealthAtlasVenousDrawing.swift"),all=motion+view+calf+drawing;
for(const name of ["leg","soleus","gastro","vein"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="move"?["moveTo",...n]:[m[1]==="addCurve"?"cubicTo":"quadTo",...n.slice(2),...n.slice(0,2)];
  });assert.deepEqual(actual,expected,name);
}
for(const [swift,kotlin] of [
  ["case 1: squeeze = 0.82 * Self.ease(t)","1 -> .82f * ease(t)"],["case 2: squeeze = 0.82 + 0.18 * Self.ease(t)","2 -> .82f + .18f * ease(t)"],
  ["case 3: squeeze = 1","3 -> 1f"],["case 4: squeeze = 1 - Self.ease(t)","4 -> 1f - ease(t)"],
  ["Self.ease(t, from: 0.32, to: 0.86)","ease(t, .32f, .86f)"],["1 - Self.ease(t, from: 0, to: 0.29)","1f - ease(t, 0f, .29f)"],
  ["1 - Self.ease(t, from: 0, to: 0.32)","1f - ease(t, 0f, .32f)"],["Self.ease(t, from: 0.29, to: 0.62)","ease(t, .29f, .62f)"],
  ["1 + 0.075 * squeeze, y: 1 - 0.075 * squeeze","1f + .075f * squeeze, 1f - .075f * squeeze"],
  ["27 - 9 * squeeze","27f - 9f * squeeze"],["230 + side * (19 - 8 * squeeze)","X + side * (19f - 8f * squeeze)"],
  ["first - 28 * direction","first - 28f * direction"],["first - 17 * direction","first - 17f * direction"],
  ["first - 13 * direction","first - 13f * direction"],["181 - 24 * direction","MID - 24f * direction"],
  ["181 + 24 * direction","MID + 24f * direction"],["last - 17 * direction","last - 17f * direction"],
  ["last + 13 * direction","last + 13f * direction"],["last + 28 * direction","last + 28f * direction"],
  ["230 + side * (16 * open)","X + side * (16f * open)"],["230 + side * (11 + 12 * open)","X + side * (11f + 12f * open)"],
  ["230 + side * (9 + 10 * open)","X + side * (9f + 10f * open)"],
  ["(2 * safe(t) + Double(index) / 3).truncatingRemainder(dividingBy: 1)","(2f * t + i / 3f) % 1f"],
  ["min(1, min(6 * p, 6 * (1 - p)))","minOf(1f, 6f * p, 6f * (1f - p))"],
  ["Int(213 * 4 * t * (1 - t))","(213f * 4f * t * (1f - t)).toInt()"],
  ["radius + 17 * t","radius + 17f * t"],["frame.distalOpen > 0.86","distalOpen > .86f"],
  ["VenousMotion.ease(t, from: 0.56, to: 0.68)","ease(t, .56f, .68f)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["case 0:","case 1:","case 2, 3:","case 4:","local.clip(to: lumen)","venousValve(116, open: frame.proximalOpen)","venousValve(246, open: frame.distalOpen)",
  "side: 1, direction: 1, first: 116, last: 246, end: 315", "side: -1, direction: -1, first: 246, last: 116, end: 78",
  "venousFlow(t, from: 210, to: 82)","venousFlow(t, from: 310, to: 165", "local.opacity *= Double(packet.alpha) / 255", "frame.squeeze > 0.06"])assert(all.includes(token),token);
for(const color of ["487588","226780","71818A","FAE4CD","EDC4AD","EFD1BB","CC8F8F","F3C2B6","D6909C","E3F4F6","ACD8E2","E8F6F6","AC6A40"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(venous_return_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-venous-return-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "VENOUS_RETURN": GalaxySSIHealthAtlasVenousView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["VenousMotion","VenousView","VenousCalfDrawing","VenousDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 venous source audit: four calf outlines, timed proximal/distal valves, compressed sinus/waist geometry with clipped leaflets, pump ejection/refill, source flow/focus alpha and bilingual labels. No native compilation/pixels verified.");
