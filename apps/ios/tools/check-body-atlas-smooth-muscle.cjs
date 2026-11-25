// Pinned source/geometry wiring audit only; no native pixels or physiological acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSmoothMuscleStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasSmoothMuscleMotion.swift"),view=local("GalaxySSIHealthAtlasSmoothMuscleView.swift"),drawing=local("GalaxySSIHealthAtlasSmoothMuscleDrawing.swift"),all=motion+view+drawing;
const from=source.match(/private val bolus = Path\(\).apply \{([^}]+)\}/)[1],to=view.match(/static let bolus = Path \{ p in([\s\S]*?)\n  \}/)[1];
const expected=[...from.matchAll(/(moveTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
const actual=[...to.matchAll(/p\.(move|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
  return m[1]==="addCurve"?["cubicTo",...n.slice(2),...n.slice(0,2)]:["moveTo",...n];
});assert.deepEqual(actual,expected);
const positions=JSON.parse("["+motion.match(/positions: \[Double\] = \[([^\]]+)\]/)[1]+"]");
const sourcePositions=source.match(/positions = floatArrayOf\(([^)]+)\)/)[1].split(",").map(v=>Number(v.trim().replace(/f$/,"")));
assert.deepEqual(positions,sourcePositions);
for(const [swift,kotlin] of [
  ["Self.positions[step] + (Self.positions[step + 1] - Self.positions[step]) * t","positions[step] + (positions[step + 1] - positions[step]) * t"],
  ["step == 0 ? 0 : step == 1 ? 16 * t : step == 4 ? 16 * (1 - t) : 16","4 -> 16f * (1f - t)"],
  ["step == 2 ? 23 * t : step == 3 ? 23 : step == 4 ? 23 * (1 - t) : 0","4 -> 23f * (1f - t)"],
  ["step == 0 ? 3 + 10 * t : 13","if (step == 0) 3f + 10f * t else 13f"],
  ["1 + squeeze / 180","1f + squeeze / 180f"],["(1.18 + 0.025 * fullness) / stretch","(1.18f + .025f * fullness) / stretch"],
  ["squeeze * Self.bump(x - behind, width: 34)","squeeze * bump(x - behind, 34f)"],
  ["opening * Self.bump(x - ahead, width: 39)","opening * bump(x - ahead, 39f)"],
  ["min(x - 16, 344 - x) / 19","minOf(x - LEFT, RIGHT - x) / 19f"],
  ["28 + edge * (fullness * Self.bump(x - center, width: 43) + openingAt(x) - squeezeAt(x))","28f + edge * (fullness * bump(x - center, 43f) + openingAt(x) - squeezeAt(x))"],
  ["q * q * (3 - 2 * q)","q * q * (3f - 2f * q)"],
  ["8 + 0.6 * frame.opening","8f + .6f * frame.opening"],["8 + 0.45 * frame.squeeze","8f + .45f * frame.squeeze"],
  ["SmoothFrame.positions[4] - 48","positions[4] - BEHIND_OFFSET"],
  ["151 - 18 * frame.heightScale","AXIS - 18f * frame.heightScale"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const [offset,fill,edge] of [[29,"DCCFE7","Self.violet"],[20,"F4C5BD","Self.coral"],[6,"F8DCB7","0xBF8C79"],[0,"FFF5E7","0xAF816E"]]){
  assert(drawing.includes(`smoothLayer(contour, offset: ${offset}, fill: 0x${fill}, edge: ${edge})`));
}
for(const token of ["stride(from: 16, through: 344, by: 2)","for i in contour.indices.reversed()", "stroke(sides, edge, offset == 29 ? 1.6 : 1.1)",
  "stride(from: 24, through: 336, by: 9)","stride(from: 24, through: 312, by: 32)","stride(from: x + 4, through: x + 20, by: 4)",
  "squeeze > 5 ? SmoothShapes.squeeze : open > 5 ? SmoothShapes.open : Self.coral","(1...3).contains(step)","(2...3).contains(step)",
  "if step == 0", "if step == 4", "outward: false", "outward: true", "local.scaleBy(x: frame.stretch, y: frame.heightScale)"])assert(all.includes(token),token);
const sides=drawing.slice(drawing.indexOf("var sides = Path()"),drawing.indexOf("private func smoothFibers"));
assert(!sides.includes("closeSubpath"),"Tube-side outline must remain open");
for(const color of ["A1475C","397A70","DCCFE7","F4C5BD","F8DCB7","BF8C79","FFF5E7","AF816E","ECC174","FFE3A3"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(smooth_muscle_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-smooth-muscle-wave-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "SMOOTH_MUSCLE_WAVE": GalaxySSIHealthAtlasSmoothMuscleView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["SmoothMuscleMotion","SmoothMuscleView","SmoothMuscleDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 smooth-muscle source audit: continuous source chapter positions, four shared-contour open-ended layers, ahead dilation/behind constriction, bolus scaling, fiber highlights and bilingual callouts. No native compilation/pixels verified.");
