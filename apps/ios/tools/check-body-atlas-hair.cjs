// Pinned formula/geometry wiring only; no native compilation or follicle-model validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasHairCycleStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasHairMotion.swift"),view=local("GalaxySSIHealthAtlasHairView.swift"),drawing=local("GalaxySSIHealthAtlasHairDrawing.swift"),all=motion+view+drawing;
const normalize=s=>s.replace(/(\d)f\b/g,"$1").replaceAll("SURFACE","132").replace(/\s/g,"");
const sourceFollicle=source.match(/private fun drawFollicle[\s\S]+?path\.rewind\(\)([\s\S]*?)path\.close\(\)/)[1];
const nativeFollicle=drawing.match(/private func hairFollicle[\s\S]+?let path = Path \{ p in([\s\S]*?)\n    \}/)[1];
const expected=[...sourceFollicle.matchAll(/(moveTo|cubicTo)\(([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(normalize)]);
const actual=[...nativeFollicle.matchAll(/p\.(move|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))/g)].map(m=>{
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>normalize(v[1]));
  return m[1]==="move"?["moveTo",...n]:["cubicTo",...n.slice(2),...n.slice(0,2)];
});assert.equal(actual.length,6);assert.deepEqual(actual,expected);
for(const [swift,kotlin] of [
  ["Self.ease((t - 0.45) / 0.55)","ease((t - .45f) / .55f)"],
  ["282 - 81 * f","282f - 81f * f"],["201 + 81 * renew","201f + 81f * renew"],
  ["1 - Self.ease(2 * t)","1f - ease(2f * t)"],["bulb - 8 - 10 * club","bulb - 8f - 10f * club"],
  ["93 - 19 * f","93f - 19f * f"],["9 + 11 * (bulb - 201) / 81","9f + 11f * (bulb - 201f) / 81f"],
  ["10 + 5 * matrix","10f + 5f * matrix"],["2.6 * (1 + wave(t + 0.18 * Double(i)))","2.6f * (1f + wave(t + .18f * i))"],
  ["173 + 0.19 * d - (d < 0 ? 0.005 * d * d : 0)","173f + SLOPE * d - if (d < 0f) .005f * d * d else 0f"],
  ["13 + 5 * wave(t - 0.25)","13f + 5f * wave(t - .25f)"],["Int(145 - 6 * (halo - 8))","(145f - 6f * (halo - 8f)).toInt()"],
  ["Self.ease(t / 0.56)","ease(t / .56f)"],["65 * release","65f * release"],
  ["0.19 * lift + 10 * Self.ease((release - 0.78) / 0.22)","SLOPE * lift + 10f * ease((release - .78f) / .22f)"],
  ["1 - Self.ease((t - 0.58) / 0.21)","1f - ease((t - .58f) / .21f)"],
  ["replacementRoot + (93 - replacementRoot) * renew","root + (93f - root) * renew"],
  ["3.1 + 2.1 * club","3.1f + 2.1f * club"],
  ["Int(255 * opacity)","(255f * opacity).toInt()"],["Int(220 * opacity)","(220f * opacity).toInt()"],
  ["x < 180 ? 23 : -29","if (x < 180f) 23f else -29f"],
  ["stride(from: 336, through: 48, by: -24)","for (x in 336 downTo 48 step 24)"],
  ["Double(x - 15), y: 154","x - 15f, 154f"],["Double(x - 10), y: 159","x - 10f, 159f"],
  ["Double(x - 24), y: 149","x - 24f, 149f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["if step == 4 { hairRenewal(frame); return }","if step == 3", "divide: step == 0", "if matrix > 0", "for i in -2...2",
  "tip: 74, root: 183, club: 1, opacity: frame.opacity", "local.translateBy(x: -frame.drift, y: -frame.lift)",
  "if frame.opacity > 0.18","if frame.renew > 0.08","if tip < 132","light.translateBy(x: -1.2, y: 0)","if club > 0"])assert(all.includes(token),token);
for(const color of ["9E647C","534057","BA8E94","6B6376","FFE1D7","EAD5E1","FFEADB","DBA1BA","BE8694","F4C1B6","BC8186","A65883","E79DB8","CEC6E6","78628E"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(hair_cycle_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-hair-follicle-cycle-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "HAIR_FOLLICLE_CYCLE": GalaxySSIHealthAtlasHairView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["HairMotion","HairView","HairDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 hair-cycle source audit: fixed upper follicle, source lower-follicle curves, matrix regression/rest, pore-following old-hair lift/fade, delayed replacement and bilingual callouts. No native compilation/pixels verified.");
