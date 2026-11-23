// Source/geometry integration audit only; not Swift execution or native pixel verification.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMovementStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasMovementMotion.swift"),view=local("GalaxySSIHealthAtlasMovementView.swift");
const muscle=local("GalaxySSIHealthAtlasMuscleDrawing.swift"),bone=local("GalaxySSIHealthAtlasBoneDrawing.swift");
const all=motion+view+muscle+bone;
for(const name of ["nerve","tubule"]){
  const block=source.match(new RegExp("private val "+name+" = track \\{([\\s\\S]*?)\\n    \\}"));assert(block,name);
  const commands=[...block[1].matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>({
    kind:{moveTo:"move",lineTo:"line",quadTo:"quad",cubicTo:"cubic"}[m[1]],
    numbers:m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))
  }));
  const target=motion.match(new RegExp("static let "+name+" = GalaxySSIHealthAtlasSectionLesson.Route\\(start: \\.init\\(x: ([\\d.]+), y: ([\\d.]+)\\), commands: \\[([\\s\\S]*?)\\n  \\]\\)"));assert(target,name);
  const actual=[{kind:"move",numbers:[Number(target[1]),Number(target[2])]},
    ...[...target[3].matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]/g)].map(m=>({
      kind:m[1],numbers:[...m[2].matchAll(/\.init\(x: ([\d.]+), y: ([\d.]+)\)/g)].flatMap(p=>[Number(p[1]),Number(p[2])])
    }))];
  assert.deepEqual(actual,commands,name);
}
for(const [swift,kotlin] of [
  ["actinLength = 80.0","ACTIN_LENGTH = 80f"],["myosinLength = 122.0","MYOSIN_LENGTH = 122f"],
  ["t * t * (3 - 2 * t)","t * t * (3f - 2f * t)"],["111 - 33 * ease(t)","111f - 33f * ease(t)"],
  ["96 * ease(extending ? 1 - fraction : fraction)","96f * ease(if (extending) 1f - t else t)"],
  ["62 - 48 * ease(fraction)","62f - 48f * ease(t)"],["(x - 81) / 178","(x - 81f) / 178f"],
  ["151 + cup * cup * depth","151f + cup * cup * depth"],["location: 0.40","floatArrayOf(0f, .40f, 1f)"],
  ["t * 1.3 + Double(i) * 0.14","t * 1.3f + i * .14f"],["t * 1.8 + Double(i) / 9","t * 1.8f + i / 9f"],
  ["15 + 109 * Motion.cycle(t * 1.25)","15f + 109f * cycle(t * 1.25f)"],["t * 1.45","t * 1.45f"],
  ["t * 1.3 + Double(i) / 8","t * 1.3f + i / 8f"],["4 + 2 * sin(t * 18 + Double(i))","4f + 2f * sin(t * 18f + i)"],
  ["pivotX + 33 * sin(rad) + 7 * cos(rad)","pivotX + 33f * sin(rad) + 7f * cos(rad)"],
  ["pivotY + 33 * cos(rad) - 7 * sin(rad)","pivotY + 33f * cos(rad) - 7f * sin(rad)"],
  ["pivotX + 10 * sin(rad) - 10 * cos(rad)","pivotX + 10f * sin(rad) - 10f * cos(rad)"],
  ["pivotY + 10 * cos(rad) + 10 * sin(rad)","pivotY + 10f * cos(rad) + 10f * sin(rad)"],
  ["15 + 6 * angle / 96","15f + 6f * angle / 96f"],["18 - 5 * angle / 96","18f - 5f * angle / 96f"],
  ["width / 12","width / 12f"],["width / 17","width / 17f"],["length * 0.47","length * .47f"],
  ["length * 0.46","length * .46f"],["length * 0.84","length * .84f"],
  ["index * 4.1","i * 4.1f"],["index * 3.5","i * 3.5f"],["0x9FF7D6CF","0x9ff7d6cf"],
  ["Double(i) * 0.043","i * .043f"],["t * 1.35 + Double(i) * 0.23","t * 1.35f + i * .23f"],
  ["5 * sin(t * 4 + Double(i))","5f * sin(t * 4f + i)"],["184 + 5 * t","184f + 5f * t"],
  ["29 + i * 91 % 282","29f + i * 91 % 282"],["155 + i * 43 % 128","155f + i * 43 % 128"],
  ["125 + Double(i) * 10.5","125f + i * 10.5f"],["time * 1.2","t * 1.2f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["matrix(depth: original, filled: true)","matrix(depth: depth, filled: false)",
  "clipped.clip(to: path)","if chapter >= 3","if chapter == 4","osteoclast(depth)",
  "surfaceCell(x, Motion.boneY(x, depth: depth), 5","surfaceCell(x, Motion.boneY(x, depth: depth), 8",
  "Motion.blend(0x8AC2B2, 0xECD5AB","top: -48, bottom: 1","top: 145, bottom: 302"])assert(bone.includes(token),token);
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_((?:motion|bone)_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-bone-remodeling-art"));assert(view.includes("atlas-function-muscle-motion-art"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "MUSCLE_MOTION", "BONE_REMODELING": GalaxySSIHealthAtlasMovementView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["MovementMotion","MovementView","MuscleDrawing","BoneDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 movement source audit: two five-stage courses, source nerve/tubule routes, fixed filament lengths, elbow attachments, erosion/reversal/osteoid/mineralization rules, native gradients and both language labels. Swift compilation/native pixels unverified.");
