// Pinned source/geometry wiring audit; no Swift/native execution.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasBarrierStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasBarrierMotion.swift"),view=local("GalaxySSIHealthAtlasBarrierView.swift"),base=local("GalaxySSIHealthAtlasIllustratedDrawing.swift"),all=motion+view+base;
for(const [swift,kotlin] of [
  ["277 - 129 * safePhase(t)","277f - 129f * HealthAtlasFunctionStory.safePhase(t)"],
  ["safePhase(t) - 0.05 * Double(index)","safePhase(t) - .05f * index"],["disrupted ? 1.55 : index == 0 ? 0.98 : 0.36","disrupted -> 1.55f"],
  ["col == 3 && flatten && !shed","col == 3 && flatten && !shed"],["13.5 - Double(row) * 1.7","13.5f - row * 1.7f"],
  ["t < 0.88","t < .88f"],["16 + 6 * t, 13 - 8 * t","16f + 6f * t, 13f - 8f * t"],
  ["207 + 23 * t","207f + 23f * t"],["111 - 47 * t","111f - 47f * t"],[".degrees(18 * t)","18f * t"],
  ["t * 1.45 - Double(index) * 0.12","t * 1.45f - index * .12f"],["t * 1.15 - 0.07 * Double(i)","t * 1.15f - .07f * i"],
  ["234 - 45 * f","234f - 45f * f"],["x + 60, barrierY","x + 60f, 171f + row * 20f"],
  ["x + 93, barrierY","x + 93f, 171f + row * 20f"],["Double(228 + j * 8) - 128 * f","228f + j * 8f - 128f * f"],
  ["max(2, ry * 0.34)","(ry * .34f).coerceAtLeast(2f)"],["rx * 0.30","rx * .30f"],["ry * 0.51","ry * .51f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["case 0: epidermis(t, flatten: false, shed: false)","case 1: epidermis(t, flatten: true, shed: false)",
  "case 2: lipids(t)","case 3: compareWater(t)","default: epidermis(t, flatten: true, shed: true)",
  'label("barrier_intercellular", 180, 195, 235)',"from: 0xFFE6D5, to: 0xD99B9A","98, 315, 0xFFEFDD, 0xD9A5A1",
  "atlas-function-epidermal-barrier-art"])assert(view.includes(token),token);
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(barrier_\w+)/g)].map(m=>m[1]))){
  assert(view.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(base.includes("13 * min(1, maxWidth / max(measured, 0.0001))"));
assert(base.includes("sin(t * 2 * .pi)"));assert(base.includes("stroke(path, border, 1.05)"));assert(base.includes("stroke(path, border, 1.3)"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "EPIDERMAL_BARRIER": GalaxySSIHealthAtlasBarrierView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["BarrierMotion","IllustratedDrawing","BarrierView"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 epidermal source audit: five stages, basal division, ascent/flattening/shedding, granular lipid secretion, intact/disrupted escape rules, source Illustrated primitives and bilingual bounded labels. No native compilation/pixels verified.");
