// Pinned pose/geometry wiring audit only; not native compilation or joint simulation validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasKneeStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasKneeMotion.swift"),view=local("GalaxySSIHealthAtlasKneeView.swift"),drawing=local("GalaxySSIHealthAtlasKneeDrawing.swift"),all=motion+view+drawing;
const nativePoses=[...motion.matchAll(/Pose\(bend: ([\d.]+), extensor: ([\d.]+), flexor: ([\d.]+)\)/g)].map(m=>m.slice(1).map(Number));
const sourcePoses=[...source.matchAll(/Pose\(([.\d]+)f, ([.\d]+)f, ([.\d]+)f\)/g)].map(m=>m.slice(1).map(Number));
assert.equal(nativePoses.length,6);assert.deepEqual(nativePoses,sourcePoses);
for(const name of ["femur","tibia","fibula"]){
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
  ["a + (b - a) * ease","a + (b - a) * ease"],["t * t * (3 - 2 * t)","f * f * (3f - 2f * f)"],
  ["angle * 0.017453293","angle * .017453293f"],
  ["178 + x * cos(radians) - y * sin(radians)","kneeX + x * cos(radians) - y * sin(radians)"],
  ["192 + x * sin(radians) + y * cos(radians)","kneeY + x * sin(radians) + y * cos(radians)"],
  ["angle = -58 * pose.bend","angle = -58f * pose.bend"],["143 + pose.bend * 6","143f + pose.bend * 6f"],["175 + pose.bend * 21","175f + pose.bend * 21f"],
  ["width = 12 + activation * 8","width = 12f + activation * 8f"],["(behind ? 167.0 : 159) - activation * 9","if (behind) 167f - activation * 9f else 159f - activation * 9f"],
  ["(1 - t) * 0.82 + 0.08","(1f - t) * .82f + .08f"],["x + shift * 0.31,tip - 11","x + shift * .31f, tip - 11f"],
  ["quad.x - 2,quad.y + 12,patellaX - 8,patellaY - 8,patellaX,patellaY","quad.x - 2f, quad.y + 12f,"],
  ["ham.x + 1,ham.y + 22,flexorAnchor.x + 10,flexorAnchor.y - 16,flexorAnchor.x,flexorAnchor.y","ham.x + 1f, ham.y + 22f,"],
  ["angle + (step == 1 ? 10 : -10)","angle + if (step == 1) 10f else -10f"],["angle + (step == 1 ? -5 : 5)","angle + if (step == 1) -5f else 5f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["KneeMotion.local(-23, 32, angle: angle)","KneeMotion.local(24, 24, angle: angle)","KneeMotion.local(0, 100, angle: angle)",
  "local.translateBy(x: 178, y: 192); local.rotate(by: .degrees(angle))", "if step == 0 || step >= 2", "if step == 1", "if step == 1 || step == 3",
  "kneePulse(quadTrack,", "kneePulse(hamTrack, 1 - t", "for i in -1...1", "disc(x, y, 3.6, color, border: Self.cream)",
  "lip.move(to: CGPoint(x: -22, y: 11))", "shin.stroke(lip, Self.teal, 3)", "[KneeShapes.fibula, KneeShapes.tibia]"])assert(all.includes(token),token);
for(const color of ["A9815E","B66A45","955572","FFF0D6","D7B28B","FFECD0","DDBC96","E4BAC7","F4C0A9","AB627E","CC765F","FAE0BB","FFDACB"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(knee_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-knee-articulation-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "KNEE_ARTICULATION": GalaxySSIHealthAtlasKneeView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["KneeMotion","KneeView","KneeDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 knee source audit: six shared poses, three exact bone outlines, shin rotation and moving attachments, quadriceps/hamstring deformation, route-specific pulses/arrows and bilingual annotations. No native compilation/pixels verified.");
