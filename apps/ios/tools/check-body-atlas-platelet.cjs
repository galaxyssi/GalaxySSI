// Pinned geometry/source wiring audit only; no native rendering or medical validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPlateletStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasPlateletMotion.swift"),view=local("GalaxySSIHealthAtlasPlateletView.swift"),drawing=local("GalaxySSIHealthAtlasPlateletDrawing.swift"),all=motion+view+drawing;
for(const name of ["lowerWall","exposedEdge"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|lineTo|quadTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addLine|addQuadCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="addQuadCurve"?["quadTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
  });assert.deepEqual(actual,expected,name);
}
const sourceFibers=[...source.matchAll(/^\s+fiber\(([^)]+)\),?$/gm)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
const nativeFibers=[...motion.matchAll(/fiber\((\d+), (\d+), \[([^\]]+)\]\)/g)].map(m=>[Number(m[1]),Number(m[2]),...JSON.parse("["+m[3]+"]")]);
assert.equal(sourceFibers.length,5);assert.deepEqual(nativeFibers,sourceFibers);
const sourceArrivals=[...source.matchAll(/Arrival\(Pose\(([^)]+)\), Pose\(([^)]+)\), ([^)]+)\)/g)].map(m=>m.slice(1).flatMap(v=>v.split(",").map(n=>Number(n.trim().replace(/f$/,"")))));
const nativeArrivals=[...motion.matchAll(/Arrival\(from: Pose\(([^)]+)\), to: Pose\(([^)]+)\), delay: ([^)]+)\)/g)].map(m=>m.slice(1).flatMap(v=>v.split(",").map(n=>Number(n.replace(/\w+:\s*/,"").trim()))));
assert.equal(sourceArrivals.length,5);assert.deepEqual(nativeArrivals,sourceArrivals);
for(const [swift,kotlin] of [
  ["ease(phase / 0.82)","ease(phase / .82f)"],["ease(phase / 0.58)","ease(phase / .58f)"],
  ["ease((phase - delay) / 0.64)","ease((phase - recruit.delay) / .64f)"],["ease(joined / 0.7)","ease(joined / .7f)"],
  ["ease((t - 0.16) / 0.76)","ease((phase - .16f) / .76f)"],["1 - PlateletMotion.ease(t / 0.42)","1f - ease(phase / .42f)"],
  ["ease(0.32 + t * 1.55 - Double(index) * 0.18)","ease(.32f + t * 1.55f - i * .18f)"],
  ["13 + a * (8 * tip - 3)","13f + activation * (8f * tip - 3f)"],["7 + a * (8 * tip + 1)","7f + activation * (8f * tip + 1f)"],
  ["Double(i) * 2 * .pi / 14 - .pi / 2","it * 2 * PI / pointCount - PI / 2"],
  ["(p.x + next.x) * 0.5","(outlineX[i] + outlineX[next]) * .5f"],
  ["(2.6 + 0.6 * f) * visibility","(2.6f + .6f * f) * visibility"],
  ["4 + 3 * max(0, focus)","4f + 3f * focus.coerceAtLeast(0f)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["step == 0 ? 0 : step == 1", "step < 2 ? 0 : step == 2", "step < 3 ? 0 : step == 3",
  "if step == 2", "if step == 3", "if step == 4", "case 1, 2:","case 3, 4:",
  "mirror.translateBy(x: 360, y: 0); mirror.scaleBy(x: -1, y: 1)",".trimmedPath(from: 0, to: CGFloat(f))", "(0..<14).map"])assert(all.includes(token),token);
for(const color of ["A7697B","BE8B93","946024","FFD694","307E79","87649D","FBFFFC","DCEEEA","F3D7D7","E8B6B9","EDF8EE"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(platelet_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-platelet-hemostasis-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "PLATELET_HEMOSTASIS": GalaxySSIHealthAtlasPlateletView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["PlateletMotion","PlateletView","PlateletDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 platelet source audit: five arrivals, fourteen-point activation morph, mirrored gap walls, signal spread/fade, five source fibrin tracks with progressive trim and bilingual annotations. No native compilation/pixels verified.");
