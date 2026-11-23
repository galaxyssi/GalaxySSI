// Pinned source/geometry wiring only; not native rendering or physiological acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSurfactantStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasSurfactantMotion.swift"),view=local("GalaxySSIHealthAtlasSurfactantView.swift"),drawing=local("GalaxySSIHealthAtlasSurfactantDrawing.swift"),all=motion+view+drawing;
const from=source.match(/private val sac = Path\(\).apply \{([^}]+)\}/)[1],to=view.match(/static let sac = Path \{ p in([\s\S]*?)\n  \}/)[1];
const expected=[...from.matchAll(/(moveTo|cubicTo)\(([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
const actual=[...to.matchAll(/p\.(move|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))/g)].map(m=>{
  const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
  return m[1]==="addCurve"?["cubicTo",...n.slice(2),...n.slice(0,2)]:["moveTo",...n];
});assert.deepEqual(actual,expected);assert(!to.includes("closeSubpath"));
const dome=source.match(/private fun dome\(path: Path, y: Float\) \{([^}]+)\}/)[1];
const surface=source.match(/private fun surface\(y: Float\) = Path\(\).apply \{([^}]+)\}/)[1].replace("dome(this, y)",dome.replaceAll("path.",""));
const nativePoints=[...motion.matchAll(/\.init\(x: ([\d.]+), y: (y(?: [+-] [\d.]+)?)\)/g)].map(m=>[m[1],m[2].replaceAll(" ","")]);
const sourcePoints=[...surface.matchAll(/(?:moveTo|cubicTo)\(([^)]+)\)/g)].flatMap(m=>{
  const c=m[1].split(",").map(v=>v.trim().replace(/(\d)f\b/g,"$1").replace("domeX","125").replaceAll(" ",""));
  return Array.from({length:c.length/2},(_,i)=>[c[i*2],c[i*2+1]]);
});assert.equal(nativePoints.length,13);assert.deepEqual(nativePoints,sourcePoints);
for(const [swift,kotlin] of [
  ["0.89 + 0.18 * breath",".89f + .18f * breath"],["step == 3 ? safe(fraction) : step == 4 ? 1 - safe(fraction) : 0","4 -> 1f - t"],
  ["center + (x - center) * width","center + (x - center) * width"],
  ["min(1, safe(t) / 0.48)","(t / .48f).coerceAtMost(1f)"],["(safe(t) - 0.48) / 0.52","(t - .48f) / .52f"],
  ["side < 0 ? 0.32 : 0.60","if (side < 0) .32f else .60f"],["(safe(t) - 0.2) / 0.8","(t - .2f) / .8f"],
  ["0.35 + Double(side) * span * fraction",".35f + side * span * spread"],
  ["radius * 0.58","radius * .58f"],["233 - 14 * approach","233f - 14f * approach"],
  ["1.8 + travel * 2","1.8f + travel * 2f"],["216 - 16 * travel + Double(i) * 1.4","apexY + 4f - 16f * travel + i * 1.4f"],
  [".degrees(-90 + 45 + 290 * t)","-90f, 45f + 290f * t"],["art.surfactantReleasedMaterial(1 + t)","releasedMaterial(c, 1f + t)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["surfaceRoute(230)","SurfactantShapes.section(230)","SurfactantShapes.section(246)","SurfactantShapes.section(254)",
  "case 0:","case 1: art.surfactantRelease(t)","case 2: if t < 0.2","if step == 2 && t >= 0.2", "for i in 1...19",
  "local.translateBy(x: 96, y: 0)","local.translateBy(x: 180, y: 0)",".sac, SurfactantShapes.rose, 14", ".sac, Self.peach, 11.5",
  ".sac, SurfactantShapes.lining, 4.5", ".sac, Self.teal, 1.6","pore.move(to: CGPoint(x: 120, y: 212))",
  "CGPoint(x: 130, y: 212), control1: CGPoint(x: 117, y: 225), control2: CGPoint(x: 133, y: 225)",
  "line(121, 212, 129, 212, SurfactantShapes.lining, 2)"])assert(all.includes(token),token);
for(const color of ["C5E4EA","EDF7F7","F5DDD2","995769","547079","EBADAB","C9ABD1","F8CBD1","CE838C","E1EEE0","9EC8B4","91C8AE"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(surfactant_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-alveolar-surfactant-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "ALVEOLAR_SURFACTANT": GalaxySSIHealthAtlasSurfactantView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["SurfactantMotion","SurfactantView","SurfactantDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 surfactant source audit: source sac/four-curve film route, stored packet highlight, liquid-connected release pore, asymmetric film spreading, breath scaling and bilingual annotations. No native compilation/pixels verified.");
