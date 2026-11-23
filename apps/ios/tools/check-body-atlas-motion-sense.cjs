// Pinned source/geometry wiring audit; no Swift/native execution or calibrated neural simulation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMotionSenseStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasMotionSenseMotion.swift"),view=local("GalaxySSIHealthAtlasMotionSenseView.swift");
const touch=local("GalaxySSIHealthAtlasTouchDrawing.swift"),balance=local("GalaxySSIHealthAtlasBalanceDrawing.swift"),all=motion+view+touch+balance;
for(const name of ["canal","lateralCanal","posteriorCanal","touchNerve"]){
  const block=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"));assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
for(const [swift,kotlin] of [
  ["(t - 0.31) / 0.69","(t - .31f) / .69f"],["0.66 + 0.20 * t",".66f + .20f * t"],["0.48 + 0.46 * t",".48f + .46f * t"],
  ["0.91 * max(0, 1 - t / 0.74)",".91f * (1f - t / .74f).coerceAtLeast(0f)"],
  ["31 * safePhase(t)","31f * HealthAtlasFunctionStory.safePhase(t)"],["-headHeading(t)","-headHeading(t)"],
  ["-16 * sin(.pi * safePhase(t))","-16f * sin(PI.toFloat() * HealthAtlasFunctionStory.safePhase(t))"],
  ["(x - 179) / 58","(x - 179f) / 58f"],["29 * load * exp(-distance * distance)","29f * load * exp(-distance * distance)"],
  ["22 * max(0, 1 - t / 0.31)","22f * (1f - t / .31f).coerceAtLeast(0f)"],
  ["28 * max(0, (t - 0.74) / 0.26)","28f * ((t - .74f) / .26f).coerceAtLeast(0f)"],
  ["17 - 4.5 * load","17f - 4.5f * load"],["step != 0 || load > 0.35","step != 0 || load > .35f"],
  ["Int(load * 5)","(load * 5).toInt()"],["11 + 20 * load","11f + 20f * load"],["startsAt: 0.24","t, i, .24f"],
  ["sample < 75 ? 11 : 31","if (i < 75) 11f else 31f"],["sample > 27","i > 27"],
  ["21 * t","21f * t"],["otolith ? 7 : 5","if (otolith) 7 else 5"],["otolith ? 27.0 : 23","if (otolith) 27f else 23f"],
  ["otolith ? 83.0 : 124","if (otolith) 83f else 124f"],["otolith ? 152 : 187 + offset * 5","if (otolith) 152f else 187f + j * 5f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["case 0, 1, 4: touchSkin(step: step, t: t)","case 2: touchChannel(t)","default: touchFiring(t)",
  "motionScientificText(\"PIEZO2\", 180, 301)","stride(from: 29, through: 331, by: 2)","stride(from: 331, through: 29, by: -2)"])assert(touch.includes(token),token);
for(const token of ["case 2, 3: balanceHair(otolith: step == 3, t: t)","default: gaze(t)",
  "fluid.rotate(by: .degrees(lag))","rotated.rotate(by: .degrees(heading))","eye.rotate(by: .degrees(look))"])assert(balance.includes(token),token);
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(sense_(?:touch|balance)_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(view.includes("atlas-function-vestibular-balance-art"));assert(view.includes("atlas-function-touch-signal-art"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "TOUCH_SIGNAL", "VESTIBULAR_BALANCE": GalaxySSIHealthAtlasMotionSenseView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["MotionSenseMotion","MotionSenseView","TouchDrawing","BalanceDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 motion-sense source audit: two five-stage courses, four exact tracks, pressure/release/PIEZO2/spike rules, labyrinth/fluid/cupula/otolith scenes, head-gaze counter rotation and bounded bilingual labels. No native compilation/pixels verified.");
