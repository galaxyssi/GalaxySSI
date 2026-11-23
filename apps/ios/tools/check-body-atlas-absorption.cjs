// Pinned geometry/source wiring only; no native compilation, Path acceptance or medical validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasIntestinalAbsorptionStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasAbsorptionMotion.swift"),view=local("GalaxySSIHealthAtlasAbsorptionView.swift"),drawing=local("GalaxySSIHealthAtlasAbsorptionDrawing.swift"),all=motion+view+drawing;
const sourceCommands=block=>[...block.matchAll(/(?:moveTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
const nativeRoute=text=>{const c=JSON.parse("["+text+"]");return [[c[0],c[1]],...c.slice(2)];};
assert.deepEqual(nativeRoute(motion.match(/static let outline = route\(([\s\S]*?)\)\n/)[1]),sourceCommands(source.match(/private val surface = Path\(\).apply \{([^}]+)\}/)[1]));
for(const name of ["bloodRoute","lipidIntake","lymphRoute","cellSolutes","cellLipids","cellExport"]){
  const from=source.match(new RegExp("private val "+name+" = Route\\(Path\\(\\).apply \\{([^}]+)\\}, Cargo\\.(\\w+)"));assert(from,name);
  const to=motion.match(new RegExp("static let "+name+" = Transport\\(path: route\\(([^)]+)\\), cargo: \\.(\\w+)"));assert(to,name);
  assert.deepEqual(nativeRoute(to[1]),sourceCommands(from[1]),name);assert.equal(to[2].toUpperCase(),from[2]);
}
for(const name of ["enterocyte","capillaries","lacteal"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="addCurve"||m[1]==="addQuadCurve"?[m[1]==="addCurve"?"cubicTo":"quadTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
  });assert.deepEqual(actual,expected,name);
}
for(const [swift,kotlin] of [
  ["for index in 8...128","for (index in 8..128)"],["position: Double(index) / 136","villusOutline.length * index / 136f"],
  ["nx = -sample.direction.dy, ny = sample.direction.dx","val nx = -tangent[1]"],
  ["x - 3.8 * nx, y: y - 3.8 * ny","x - 3.8f * nx, y - 3.8f * ny"],
  ["x + 14 * nx, y: y + 14 * ny","x + 14f * nx, y + 14f * ny"],["x + 9 * nx, cy = y + 9 * ny","val cx = x + 9f * nx"],
  ["index % 4 == 0","index % 4 == 0"],["index % 4 == 2","index % 4 == 2"],
  ["stride(from: 222, through: 342, by: 4)","for (x in 222..342 step 4)"],["x % 8 == 2 ? 97 : 99","if (x % 8 == 2) 97f else 99f"],
  [".truncatingRemainder(dividingBy: 1) * 0.86 + 0.04","% 1f) * .86f + .04f"],
  ["Double(index) / Double(count)","index / count.toFloat()"],
  ["radius * 0.83","radius * .83f"],["radius * 0.36","radius * .36f"],["radius: 3 + 2 * t","3f + 2f * t"],
  ["width: 128 * progress, height: 16","218f + 128f * progress, 110f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["static let features: Features", "absorptionVillus(highlight: step == 1, progress: step == 0 ? t : nil)",
  "absorptionInset(progress: step == 1 ? t : nil)","if step == 2 || step == 4", "if step == 3", "if step == 4", "if step >= 3",
  "absorptionFlow(AbsorptionMotion.lipidIntake, t, count: 1)","absorptionFlow(AbsorptionMotion.cellLipids, t, count: 2)","absorptionFlow(AbsorptionMotion.cellExport, t, count: 2)",
  "local.clip(to: AbsorptionShapes.villus)","StrokeStyle(lineWidth: 27, lineCap: .round, lineJoin: .round)",".trimmedPath(from: 0, to: CGFloat(progress))",
  "highlight ? 1.45 : 0.9","at(route.path, 0.8)","at(route.path, 1)",".degrees(45)"])assert(all.includes(token),token);
for(const color of ["637E81","8A6052","A16125","FFEEE0","E9B7A6","FFD7BA","D7918C","FFE3C9","E9AD9E","BA7C78","AD5264","F6A1A0","B8DDD0","FFDD90"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(absorption_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-intestinal-absorption-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "INTESTINAL_ABSORPTION": GalaxySSIHealthAtlasAbsorptionView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["AbsorptionMotion","AbsorptionView","AbsorptionDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 absorption source audit: source six-curve villus, six cargo-specific tracks, three anatomical outlines, cached normal-based brush/cell geometry, clipped inset highlights and bilingual labels. No native compilation/pixels verified.");
