// Source/resource integration audit only; no Swift execution, native build or pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=name=>cp.execFileSync("git",["show",sha+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:20_000_000});
const source=show("java/com/galaxyssi/chat/HealthAtlasBreathingView.kt").toString();
const stage=show("java/com/galaxyssi/chat/HealthAtlasBreathingStage.kt").toString();
const view=local("GalaxySSIHealthAtlasBreathingView.swift"),motion=local("GalaxySSIHealthAtlasBreathingMotion.swift");
for(const name of ["toRightLung","toLeftLung","blood","oxygen","carbon"]){
  const block=source.match(new RegExp("private val "+name+" = path \\{([\\s\\S]*?)\\n    \\}"));assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|lineTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=view.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");
  assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
for(const [swift,kotlin] of [
  ["ease((fraction - 0.12) / 0.62)","ease((fraction - .12f) / .62f)"],
  ["1 - ease(fraction / 0.35)","1f - ease(fraction / .35f)"],
  ["case .diffuse, .perfuse: return 1","DIFFUSE, PERFUSE -> 1f"],
  ["case .exhale: return 1 - ease(fraction)","EXHALE -> 1f - ease(fraction)"]
]){assert(motion.includes(swift),swift);assert(stage.includes(kotlin),kotlin);}
for(const [swift,kotlin] of [
  ["54 + 232 * zoom","54f + 232f * zoom"],["214 - 183 * zoom","214f - 183f * zoom"],["175 - 157 * zoom","175f - 157f * zoom"],
  ["phase * 6 + Double($0) / 4","time * 6f + i / 4f"],["phase * 3 + Double($0) / 7","time * 3f + i / 7f"],
  ["phase * 7 + Double($0) / 3","time * 7f + i / 3f"],["1 + 0.077 * motion.expansion","1f + .077f * expansion"],
  ["1 + 0.045 * motion.expansion","1f + .045f * expansion"],["position > 0.78","position > .78f"],
  ["motion.expansion * 10","expansion * 10f"],["262 + down * 2.4","262f + down * 2.4f"],
  ["motion.zoom > 0.8","zoom > .8f"],["size * 1.25","size * 1.25f"],["size * 0.66","size * .66f"]
]){assert((view+motion).includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const [android,asset,file] of [
  ["health_atlas_lungs","HealthAtlasLungs","atlas.png"],["health_atlas_alveolus","HealthAtlasAlveolus","alveolus.png"]
]){
  const bytes=show("res/drawable-nodpi/"+android+".png");
  assert(bytes.equals(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",asset+".imageset",file))),asset);
}
for(const key of ["muscle","air_out","air_in","alveolar_air","oxygen","carbon"]){
  for(const language of ["en","zh-Hans"]){
    assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_breathe_'+key+'"'),key);
  }
}
for(const token of ["layer.drawLayer","layer.opacity = 1 - motion.zoom","layer.opacity = motion.zoom",
  "GalaxySSIHealthAtlasGasExchange.position(.oxygen","GalaxySSIHealthAtlasGasExchange.position(.carbon",
  "GalaxySSIHealthAtlasFunctionPath.sample","reverse: true, size: 17","atlas-function-breathing-art"])assert(view.includes(token),token);
assert(local("GalaxySSIHealthAtlasFunctionPath.swift").includes("path.trimmedPath(from: 0, to: CGFloat(position))"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "BREATHING": GalaxySSIHealthAtlasBreathingView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const file of ["GalaxySSIHealthAtlasBreathingMotion.swift","GalaxySSIHealthAtlasBreathingView.swift"]){
  assert.equal(project.split(file+" in Sources").length-1,2,file);
}
console.log("Android #4384 breathing source audit: five stages, five exact routes, original lung/alveolus PNGs, reversible airflow, opposing diffusion, independent blood flow and whole/detail crossfade. Native pixels and Swift type checking unverified.");
