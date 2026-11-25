// Pinned source/geometry audit only; no Swift/native execution or visual acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasOcularStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasOcularMotion.swift"),view=local("GalaxySSIHealthAtlasOcularView.swift");
const pigment=local("GalaxySSIHealthAtlasPigmentDrawing.swift"),relay=local("GalaxySSIHealthAtlasRodRelayDrawing.swift"),cornea=local("GalaxySSIHealthAtlasCorneaDrawing.swift"),all=motion+view+pigment+relay+cornea;
for(const [swift,kotlin] of [
  ["returnToRod ? 238 - 66 * f : 172 + 66 * f","if (returnToRod) 238f - 66f * f else 172f + 66f * f"],
  ["104 - 76 * safePhase(t)","104f - 76f * HealthAtlasFunctionStory.safePhase(t)"],
  ["(safePhase(t) - 0.08 * Double(index)) * 1.24","(HealthAtlasFunctionStory.safePhase(t) - 0.08f * index) * 1.24f"],
  ["Double(224 - (j & 1) * 4)","224f - (j and 1) * 4f"],["0.88 * (1 - moved)",".88f * (1f - moved)"],
  ["(t - 0.34) / 0.58","(t - .34f) / .58f"],["t < 0.42","t < .42f"],["(t - 0.52) * 2.1","(t - .52f) * 2.1f"],
  ["t < 0.67","t < .67f"],["bend * 10 * size","bend * 10f * size"],["3.4 * size","3.4f * size"],
  ["max(0, t - Double(i) * 0.029)","(t - i * .029f).coerceAtLeast(0f)"],
  ["4 + 2 * wave(t + Double(i) * 0.095)","4f + 2f * wave(t + i * .095f)"],
  ["219 - t * 77","219f - t * 77f"],["16 - t * 9","16f - t * 9f"],
  ["t * Double(35 + i * 4)","t * (35f + i * 4f)"],["155 - 21 * t","155f - 21f * t"],["163 - 13 * t","163f - 13f * t"],
  ["111 + tearRipple","111f + tearRipple"],["127 - tearRipple","127f - tearRipple"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["case 1: pigmentPhoton(t)","case 3: pigmentConversion(t)","default: pigmentSection(step: step, t: t)",
  'ocularScientificText("RPE65", 238, 117)',"returnToRod: returning"])assert(pigment.includes(token),token);
for(const token of ["if step == 2","if step == 3","if step == 4","RelayInk.transmit","RelayInk.suppress",
  'label("ocular_relay_gap"','label("ocular_relay_glycine"',"ocularPulse(right, 264, right, 294, t, 2"])assert(relay.includes(token),token);
for(const token of ["step == 1 || step == 2","migrating: step == 2","0..<8","if step == 3",
  "step == 4 && (2...4).contains(i)","if step != 4"])assert(cornea.includes(token),token);
for(const color of ["598F86","86598E","AA6B31","307C6E","659F9B","CA8D78","8D8EB3","6F9FB8"]){
  assert(view.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(ocular_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(!all.includes("Timer"));assert(!all.includes("Image("));
for(const tag of ["atlas-function-rpe-visual-cycle-art","atlas-function-dim-light-relay-art","atlas-function-corneal-surface-renewal-art"])assert(view.includes(tag));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "RPE_VISUAL_CYCLE", "DIM_LIGHT_RELAY", "CORNEAL_SURFACE_RENEWAL": GalaxySSIHealthAtlasOcularView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["OcularMotion","OcularView","PigmentDrawing","RodRelayDrawing","CorneaDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 ocular source audit: three five-stage courses, retinoid transfer/conversion and RPE65, rod-bipolar/AII ON-OFF branches, staggered limbal migration, corneal stratification/shedding and bounded bilingual labels. No native compilation/pixels verified.");
