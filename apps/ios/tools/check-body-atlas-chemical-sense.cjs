// Pinned source/geometry integration only; no native Swift or Canvas execution.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasChemicalSenseStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasChemicalSenseMotion.swift"),view=local("GalaxySSIHealthAtlasChemicalSenseView.swift");
const smell=local("GalaxySSIHealthAtlasSmellDrawing.swift"),taste=local("GalaxySSIHealthAtlasTasteDrawing.swift"),all=motion+view+smell+taste;
for(const name of ["airway","tasteNerve"]){
  const block=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"));assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
for(const [swift,kotlin] of [
  ["(safePhase(t) - startsAt - 0.078 * Double(index)) * 1.55","(HealthAtlasFunctionStory.safePhase(t) - startsAt - .078f * index) * 1.55f"],
  ["variant ? [1, 2] : [0, 2]","if (variant) listOf(1, 2) else listOf(0, 2)"],
  ["Double(79 + i * 94)","79f + i * 94f"],["[x-10,195,x+13,171,x,130]","cubicTo(x - 10f, 195f, x + 13f, 171f, x, 130f)"],
  ["[x-3,100,x,88]","quadTo(x - 3f, 100f, x, 88f)"],["active && i != 1","active && i != 1"],
  ["149 + 118 * f","149f + 118f * f"],["t > 0.52","t > .52f"],["startsAt: 0.2","t, 0, .2f"],
  ["startsAt: 0.12","t, i, .12f"],["t * 2.1).truncatingRemainder(dividingBy: 1)","t * 2.1f % 1f"],
  ["step <= 2","step <= 2"],["step >= 3","step >= 3"],["111 + 115 * t","111f + 115f * t"],
  ["Double(i - 2) * (9 - f * 6)","(i - 2) * (9f - f * 6f)"],["248 + 24 * f","248f + 24f * f"],
  ["2 * wave(t + Double(i))","2f * wave(t + i)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["mirrored.translateBy(x: 0, y: 360)","mirrored.scaleBy(x: 1, y: -1)",
  "case 1, 2: smellReceptors(active: step == 2, t: t)","case 3: smellBulb(t)","default: corticalPattern(t)",
  "0xA1B4AE","0x9DABA8"])assert(smell.includes(token),token);
for(const token of ["if step == 0","a == 0 && step >= 2","if step == 4","chemicalParticles(Motion.tasteNerve, t, Self.blue, 4)"])assert(taste.includes(token),token);
assert(view.includes("min(2 * x - 8, min(712 - 2 * x, 145))"));
assert(!all.includes("Timer"));assert(!all.includes("Image("));
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(sense_(?:smell|taste)_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-olfaction-art"));assert(view.includes("atlas-function-taste-signal-art"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "OLFACTION", "TASTE_SIGNAL": GalaxySSIHealthAtlasChemicalSenseView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["ChemicalSenseMotion","ChemicalSenseView","SmellDrawing","TasteDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 chemical-sense source audit: two five-stage courses, source airway/nerve/three receptor routes, delayed non-looping transfer, mirrored receptor layer, odor channel combinations, taste pore/ATP/nerve stages and bounded bilingual labels. No native compilation/pixels verified.");
