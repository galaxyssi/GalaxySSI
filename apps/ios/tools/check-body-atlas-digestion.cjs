// Pinned source/resource audit only. Does not execute Swift, XCTest or native Canvas.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=name=>cp.execFileSync("git",["show",sha+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:20_000_000});
const source=show("java/com/galaxyssi/chat/HealthAtlasDigestiveStoryView.kt").toString();
const stages=show("java/com/galaxyssi/chat/HealthAtlasDigestionStage.kt").toString();
const motion=local("GalaxySSIHealthAtlasDigestionMotion.swift"),view=local("GalaxySSIHealthAtlasDigestionView.swift");
const routes=["swallow","downEsophagus","stomachExit","smallBowel","bile","enzymes","waterSoluble","dietaryFat",
  "colonEntry","ascending","transverse","descending","colonFlow","rectal"];
const numbers=block=>[...block.matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)]
  .map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
function compare(name,expected){
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
for(const name of routes){
  const block=source.match(new RegExp("private val "+name+" = path \\{([^}]+)\\}"));assert(block,name);compare(name,numbers(block[1]));
}
const water=source.match(/private val waterTracks = listOf\(([\s\S]*?)\n    \)/);assert(water);
const tracks=[...water[1].matchAll(/path \{([^}]+)\}/g)];assert.equal(tracks.length,3);
for(const [i,key] of ["waterTrackA","waterTrackB","waterTrackC"].entries())compare(key,numbers(tracks[i][1]));
assert(stages.includes("meal = listOf(SWALLOW, PERISTALSIS, STOMACH, DUODENUM, VILLUS)"));
assert(stages.includes("colon = listOf(CECUM, MIX, WATER, PROPULSION, RECTUM)"));
assert(motion.includes("meal: [Self] = [.swallow, .peristalsis, .stomach, .duodenum, .villus]"));
assert(motion.includes("colon: [Self] = [.cecum, .mix, .water, .propulsion, .rectum]"));
for(const [swift,kotlin] of [
  ["fraction < 0.58 ? 0.52 + 0.24 * fraction : 0.66 + 0.66 * (fraction - 0.58)","if (t < .58f) .52f + .24f * t else .66f + .66f * (t - .58f)"],
  ["fraction * 10","t * 10f"],["12 + (index % 4) * 6","12f + (index % 4) * 6f"],
  ["(4.3 - 2 * fraction) + Double(index % 3) * 0.7","(4.3f - 2f * t) + (index % 3) * .7f"],
  ["fraction * 1.2 + Double($0) / 6","t * 1.2f + i / 6f"],["t * 1.25 + Double($0) / Double(count)","t * 1.25f + i / count.toFloat()"],
  ["0.03 + 0.93 * t"," .03f + .93f * t"],["0.91 * t - 0.13",".91f * t - .13f"],
  ["0.04 + 0.92 * t",".04f + .92f * t"],["t > 0.53","t > .53f"],["(t - 0.53) / 0.47","(t - .53f) / .47f"],
  ["position < 0.47","progress < .47f"],["sin(phase - 1.6)","sin(phase - 1.6f)"],["sin(phase - 2.9)","sin(phase - 2.9f)"],
  ["0.55 + sin(phase) * 0.21",".55f + sin(phase) * .21f"],["0.41 + sin(phase - 1.6) * 0.19",".41f + sin(phase - 1.6f) * .19f"],
  ["0.51 + sin(phase - 2.9) * 0.21",".51f + sin(phase - 2.9f) * .21f"],["0.96 * t - 0.085",".96f * t - .085f"],
  ["0.06 + 0.9 * t",".06f + .9f * t"],["0.20 + 0.19 * t",".20f + .19f * t"],["9 - t * 3","9f - t * 3f"],
  ["0.53 + 0.15 * t",".53f + .15f * t"],["8 - t * 3","8f - t * 3f"],["radius * 0.42","radius * .42f"],
  ["size * 1.22","size * 1.22f"],["size * 0.64","size * .64f"]
]){assert((motion+view).includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["art.translateBy(x: 4, y: -16)","art.scaleBy(x: 0.93, y: 0.93)",
  "art.translateBy(x: 12, y: 41)","art.scaleBy(x: 0.89, y: 0.89)","case .villus: break",
  "atlas-function-meal-art","atlas-function-colon-art","lineWidth: 9","lineWidth: 4.4"])assert(view.includes(token),token);
for(const id of new Set([...source.matchAll(/R\.string\.(health_atlas_(?:meal|colon_story)_\w+)/g)].map(m=>m[1]))){
  assert(view.includes('"'+id+'"'),id);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"'+id+'"'),id);
}
const original=show("res/drawable-nodpi/health_atlas_gut_jejunum.png");
assert(original.equals(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionGutJejunum.imageset/art.png"))));
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-digestion"],{cwd:root,stdio:"inherit"});
const registry=local("GalaxySSIHealthAtlasFunctionArtwork.swift");
assert(registry.includes('case "DIGESTION", "COLON": GalaxySSIHealthAtlasDigestionView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["DigestionMotion","DigestionView"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 digestive source audit: separate meal/colon courses, ten stages, seventeen exact routes, source bolus/squeeze/mixing/absorption motion, seven dedicated illustrations and bilingual labels. Native rendering unverified.");
