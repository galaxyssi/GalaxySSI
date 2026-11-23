// Source/resource parity only. No native build, Canvas playback or clinical calibration.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=(name,rev=sha)=>cp.execFileSync("git",["show",rev+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:20_000_000});
const source=show("java/com/galaxyssi/chat/HealthAtlasVisionStoryView.kt").toString();
const stages=show("java/com/galaxyssi/chat/HealthAtlasVisionStage.kt").toString();
const motion=local("GalaxySSIHealthAtlasVisionMotion.swift"),view=local("GalaxySSIHealthAtlasVisionView.swift");
for(const name of ["lightInRetina","coneRelay","nerve"]){
  const block=source.match(new RegExp("private val "+name+" = (?:path|Path\\(\\).apply) \\{([^}]+)\\}"));assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
for(const [swift,kotlin] of [
  ["[-12.0, 0, 12]","listOf(-12f, 0f, 12f)"],["160 + offset * 1.8","160f + offset * 1.8f"],
  ["160 + offset * 1.55","160f + offset * 1.55f"],["164 + offset * 0.55","164f + offset * .55f"],
  ["164 + offset * 0.42","164f + offset * .42f"],["[255,149]","lineTo(255f, 149f)"],
  ["0.43 + fraction * 0.37",".43f + t * .37f"],["t * 1.28 + Double(i) * 0.5","t * 1.28f + i * .5f"],
  ["(fraction - 0.10) / 0.38","(t - .10f) / .38f"],["fraction < 0.46 ? 6 : 2","if (t < .46f) 6 else 2"],
  ["t < 0.51","t < .51f"],["t >= 0.46","t >= .46f"],["sin(t * 8) * 2","sin(t * 8f) * 2f"],
  ["t * 2.4 + Double(i) / Double(motion.captureCount)","t * 2.4f + i / count.toFloat()"],
  ["t * 1.4 - 0.12 + Double(i) * 0.25 + 1","t * 1.4f - .12f + i * .25f + 1f"],
  ["motion.fraction * 1.6 + Double(i) * 0.2","t * 1.6f + i * .2f"],
  ["1 + Int(fraction * 4)","1 + (t * 4f).toInt()"],["1 + Int(fraction * 2)","1 + (t * 2f).toInt()"],
  ["3 - Int(fraction)","3 - t.toInt()"],["4 - Int(fraction * 3)","4 - (t * 3f).toInt()"],
  ["1 + Int(fraction * 3)","1 + (t * 3f).toInt()"],["(light - 0.24) / 0.54","(light - .24f) / .54f"],
  ["time * 2 + Double(i) * 0.24","t * 2f + i * .24f"],["Double(abs(i - 2)) * 0.25","abs(i - 2) * .25f"]
]){assert((view+motion).includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const [swift,kotlin] of [["0.68 - 0.53 * fraction",".68f - .53f * fraction"],
  ["0.15 + 0.43 * fraction",".15f + .43f * fraction"],["0.58 + 0.36 * fraction",".58f + .36f * fraction"]]){
  assert(motion.includes(swift));assert(stages.includes(kotlin));
}
assert(stages.includes("pathway = listOf(ENTRY, FOCUS, CAPTURE, RELAY, OUTPUT)"));
assert(stages.includes("adaptation = listOf(DIM, ROD, MIXED, BRIGHT, COLOR)"));
assert(motion.includes("pathway: [Self] = [.entry, .focus, .capture, .relay, .output]"));
assert(motion.includes("adaptation: [Self] = [.dim, .rod, .mixed, .bright, .color]"));
for(const [android,asset] of [["eye_section","HealthAtlasEyeSection"],["sensory_rod","HealthAtlasSensoryRod"],
  ["sensory_cone","HealthAtlasSensoryCone"],["brain","HealthAtlasBrain"]]){
  const folder=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",asset+".imageset");
  const filename=JSON.parse(fs.readFileSync(path.join(folder,"Contents.json"))).images[0].filename;
  assert(show("res/drawable-nodpi/health_atlas_"+android+".png").equals(fs.readFileSync(path.join(folder,filename))),asset);
}
// The retained native-gradient retina resource has the same original source in #4384.
const retina="res/drawable/health_atlas_sensory_retina_section.xml";
assert(show(retina).equals(show(retina,"7e5841c21c313fd2ecee924e6805385e96a564a1")));
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs")],{cwd:root,stdio:"inherit"});
for(const id of new Set([...source.matchAll(/R\.string\.(health_atlas_vision_story_\w+)/g)].map(m=>m[1]))){
  assert(view.includes('"'+id.replace("health_atlas_vision_story_","")+'"'),id);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"'+id+'"'),id);
}
for(const token of ["atlas-function-light-adaptation-art","atlas-function-vision-art","fraction * motion.opticsDrawn",
  "radius: radius + 1.4","Motion.blend(0x29404A, 0xF1E9D4","Motion.blend(0x8D9C9D","motion.emphasis == i"])assert(view.includes(token),token);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "VISION", "LIGHT_ADAPTATION": GalaxySSIHealthAtlasVisionView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["VisionMotion","VisionView"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 vision source audit: two five-stage courses, converging rays, retinal light/relay paths, capture threshold, source relative rod/cone response rules, original PNGs and retained gradient retina. Native rendering unverified.");
