// Source/geometry wiring audit only; not native compilation or pixel acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasAirwayStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasAirwayMotion.swift"),view=local("GalaxySSIHealthAtlasAirwayView.swift"),all=motion+view;
for(const name of ["clearance","toEsophagus"]){
  const block=source.match(new RegExp("private val "+name+" = track\\(Path\\(\\).apply \\{([^}]+)\\}"));assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
// Compare complete outline command streams, not just their bounding boxes.
for(const [native,android] of [["left","leftLung"],["right","rightLung"],["airway","airway"]]){
  const from=source.match(new RegExp("private val "+android+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+native+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|lineTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")));
    return [m[1],...n];
  });
  const actual=[...to.matchAll(/p\.(move|addLine|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="addCurve"?["cubicTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
  });
  assert.deepEqual(actual,expected,native);
}
for(const [swift,kotlin] of [
  ["safePhase(fraction) * 0.84","safePhase(fraction) * .84f"],
  ["0.84 + 0.16 * safePhase(fraction)",".84f + .16f * HealthAtlasFunctionStory.safePhase(fraction)"],
  ["safePhase(fraction) * 1.42 - Double(index) * 0.13","safePhase(fraction) * 1.42f - index * .13f"],
  ["Double(index + 1) * 0.14) * 1.38","(i + 1) * .14f) * 1.38f"],
  ["0.13 * Double(column) - 0.035 * Double(fiber)",".13f * column - .035f * fiber"],
  ["0.27 + 0.71 * f",".27f + .71f * f"],["0.866 + f * (0.134 / 0.3)",".866f + f * (.134f / .3f)"],
  ["(f - 0.3) / 0.7","(f - .3f) / .7f"],["t * 1.38","t * 1.38f"],
  ["y - 25 + abs(beat) * 0.20","y - 25f + kotlin.math.abs(beat) * .20f"],
  ["257 - 51 * upward + 2 * Double(i)","257f - 51f * upward + 2f * i"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["if step == 3","else if step == 4","if step >= 3","if index == 3","for fiber in -2...2",
  "CGRect(x: 25, y: 181, width: 310, height: 40)","fraction: t) * 288","if step == 1","step == 0 ? \"airway_particles\" : \"airway_mucus\""])assert(all.includes(token),token);
for(const color of ["446B7D","A4C9C8","AE784D","FFE5DE","DF9A9D","C4E5E7","79AAB8","A9B5DB","69A68F"]){
  assert(view.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(airway_\w+)/g)].map(m=>m[1]))){
  assert(view.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(!all.includes("Timer"));assert(!all.includes("Image("));assert(view.includes("atlas-function-airway-clearance-art"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "AIRWAY_CLEARANCE": GalaxySSIHealthAtlasAirwayView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["AirwayMotion","AirwayView"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 airway source audit: five stages, exact lung/airway outlines and two tracks, staged settling/secretion/ciliary waves, clipped mucus travel and swallowing handoff. No native compilation/pixels verified.");
