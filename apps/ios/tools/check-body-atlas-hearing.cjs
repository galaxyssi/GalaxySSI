// Pinned source/resource audit, not native rendering or Swift type checking.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=name=>cp.execFileSync("git",["show",sha+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:20_000_000});
const source=show("java/com/galaxyssi/chat/HealthAtlasHearingStoryView.kt").toString();
const stage=show("java/com/galaxyssi/chat/HealthAtlasSoundStage.kt").toString();
const motion=local("GalaxySSIHealthAtlasHearingMotion.swift"),view=local("GalaxySSIHealthAtlasHearingView.swift");
for(const [android,swift] of [["cochlea","cochlea"],["nerve","nerveRoute"]]){
  const block=source.match(new RegExp("private val "+android+" = Path\\(\\).apply \\{([\\s\\S]*?)\\n    \\}"));assert(block,android);
  const expected=[...block[1].matchAll(/(?:moveTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=view.match(new RegExp("static let "+swift+" = route\\(([^\\n]+)\\)"));assert(target,swift);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,swift);
}
for(const [swift,kotlin] of [
  ["sin((progress * 3 - delay) * 2 * .pi)","sin((progress * 3f - delay) * 2 * PI)"],
  ["progress * 0.92","progress * .92f"],["abs(position - center) / 0.42","abs(position - center) / .42f"],
  ["delay: position * 2.8","position * 2.8f"]
]){assert(motion.includes(swift),swift);assert(stage.includes(kotlin),kotlin);}
for(const [swift,kotlin] of [
  ["center: 0.444, radius: 0.058","influence(x, .444f, .058f)"],["center: 0.51, radius: 0.17","influence(y, .51f, .17f)"],
  ["center: 0.56, radius: 0.15","influence(x, .56f, .15f)"],["center: 0.45, radius: 0.14","influence(y, .45f, .14f)"],
  ["motion * (5.5 * drum + 4 * chain)","motion * (5.5f * drum + 4f * chain)"],
  ["(0.29 - y) / 0.14","(.29f - y) / .14f"],["center: 0.46, radius: 0.34","influence(x, .46f, .34f)"],
  ["fraction * 1.7 + Double($0) / 6","phase * 1.7f + index / 6f"],["fraction * 1.8 + Double($0) / 4","phase * 1.8f + index / 4f"],
  ["fraction * 1.14","phase * 1.14f"],["motion.motion * 3","motion * 3f"],["15 * motion.motion","15f * motion"]
]){assert((motion+view).includes(swift),swift);assert(source.includes(kotlin),kotlin);}
assert(motion.includes("(0...28).flatMap"));assert(motion.includes("(0...28).map"));
assert(source.includes("const val COLUMNS = 28"));assert(source.includes("const val ROWS = 28"));
for(const [android,asset] of [["health_atlas_ear_section","HealthAtlasEarSection"],
  ["health_atlas_sensory_cochlear_hair","HealthAtlasSensoryCochlearHair"],["health_atlas_brain","HealthAtlasBrain"]]){
  const folder=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",asset+".imageset");
  const filename=JSON.parse(fs.readFileSync(path.join(folder,"Contents.json"))).images[0].filename;
  assert(show("res/drawable-nodpi/"+android+".png").equals(fs.readFileSync(path.join(folder,filename))),asset);
}
for(const key of ["canal","drum","ossicles","window","cochlea_label","basilar","base","apex","bundle","synapse","relays","cortex","signal"]){
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_hear_'+key+'"'),key);
}
for(const token of ["columns: 28, rows: 28).id(asset)","GalaxySSIHealthAtlasFunctionPath.sample","for step in 0...100",
  "motion.motion > 0","atlas-function-hearing-art"])assert(view.includes(token),token);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "HEARING": GalaxySSIHealthAtlasHearingView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["FunctionPath","HearingMotion","HearingView"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 hearing source audit: five stages, 28x28 ear/hair meshes, packet/oscillation rules, exact cochlea/nerve paths, source PNGs and both language labels. No native compilation or pixels verified.");
