// Pinned formula/geometry wiring audit only; no Swift execution or native pixel acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasTendonStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasTendonMotion.swift"),view=local("GalaxySSIHealthAtlasTendonView.swift"),drawing=local("GalaxySSIHealthAtlasTendonDrawing.swift"),all=motion+view+drawing;
for(const name of ["bone","corticalEdge"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|lineTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addLine|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="addCurve"?["cubicTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
  });assert.deepEqual(actual,expected,name);
}
for(const [swift,kotlin] of [
  ["case 1: load = 0.28 * eased","1 -> .28f * eased"],["case 2: load = 0.28 + (0.82 - 0.28) * eased","2 -> .28f + (.82f - .28f) * eased"],
  ["case 3: load = 0.82 + (1 - 0.82) * eased","3 -> .82f + (1f - .82f) * eased"],["case 4: load = 1 - eased","4 -> 1f - eased"],
  ["148 - 15 * load","148f - 15f * load"],["2 * load","2f * load"],["5 * load","5f * load"],
  ["56 - 10 * load","56f - 10f * load"],["(304 - first) / 8","(304f - first) / 8f"],["10 - 8.8 * load","10f - 8.8f * load"],
  ["7 + 46 * load","7f + 46f * load"],["4 + 4 * load","4f + 4f * load"],["2.5 + 2 * load","2.5f + 2f * load"],["1.8 + 1.1 * load","1.8f + 1.1f * load"],
  ["Int(255 * min(1, load * 4))","(255f * (load * 4f).coerceAtMost(1f)).toInt()"],
  ["Int(220 * (1 - abs(2 * progress - 1)))","(220f * (1f - abs(2f * progress - 1f))).toInt()"],
  ["5 + 15 * progress","5f + 15f * progress"],
  ["CGPoint(x: 269, y: 108), control: CGPoint(x: 259, y: 112)","tendon.quadTo(259f, 112f, 269f, 108f)"],
  ["CGPoint(x: 269, y: 131), control: CGPoint(x: 274, y: 119)","tendon.quadTo(274f, 119f, 269f, 131f)"],
  ["Double(row) * (4.5 - frame.load)","row * (4.5f - load)"],["Double(row) * (8 + frame.load)","row * (8f + load)"],
  ["row % 2 == 0 ? 0xBB7482 : 0xFDE5DF","if (row % 2 == 0) 0xffbb7482 else 0xfffde5df"],
  ["half % 2 == 0 ? -frame.crimp : frame.crimp","if (half % 2 == 0) -crimp else crimp"],
  ["frame.first + Double(half) * frame.halfWave","first + half * halfWave"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["progress = step == 0 ? 3 * t : 0","progress - 1","progress - 2","step == 3 ? t : 0","if frame.load > 0.06",
  "tendonLoadArrow(276, 164, direction: -1","tendonLoadArrow(96, 319, direction: -1","tendonLoadArrow(264, 319, direction: 1",
  "for row in -1...1","for row in -2...2","for row in 0...2","for half in 0...7","local.opacity *= Double(alpha) / 255",
  "local.opacity *= Double(frame.arrowAlpha) / 255","row == 1 ? 3.1 : 2.4"])assert(all.includes(token),token);
for(const color of ["96754E","65817B","F9D1CC","D88D99","E4F2E7","ADD2C6","FFF5DF","EAD3A8","C7A679","F3F8EF","DCEFE5","51867D"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(tendon_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-tendon-force-transfer-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "TENDON_FORCE_TRANSFER": GalaxySSIHealthAtlasTendonView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["TendonMotion","TendonView","TendonDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 tendon source audit: five load stages, source bone/cortical geometry and fixed insertion, muscle/tendon deformation, three uncrimping collagen rows, sequential focus/force arrows and bilingual callouts. No native compilation/pixels verified.");
