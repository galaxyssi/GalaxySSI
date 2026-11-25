// Pinned source/resource audit, not Swift execution, native pixels or calibrated physiology.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=name=>cp.execFileSync("git",["show",sha+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:20_000_000});
const source=show("java/com/galaxyssi/chat/HealthAtlasHomeostasisStoryView.kt").toString();
const sweatSource=show("java/com/galaxyssi/chat/HealthAtlasSweatView.kt").toString();
const motion=local("GalaxySSIHealthAtlasHomeostasisMotion.swift"),view=local("GalaxySSIHealthAtlasHomeostasisView.swift");
const glucagon=local("GalaxySSIHealthAtlasGlucagonDrawing.swift"),sweat=local("GalaxySSIHealthAtlasSweatDrawing.swift"),all=motion+view+glucagon+sweat;
for(const name of ["nerve","alphaExit","liverEntry","glucoseExit","sweatDuct"]){
  const block=name==="sweatDuct"?sweatSource.match(/fun eccrineDuctPath\(\) = Path\(\).apply \{([^}]+)\}/):
    source.match(new RegExp("private val "+name+" by lazy \\{ route \\{([^}]+)\\}"));
  assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
for(const [swift,kotlin] of [
  ["1 - safePhase(fraction) * (humid ? 0.35 : 0.91)","1f - HealthAtlasFunctionStory.safePhase(fraction) * (if (humid) .35f else .91f)"],
  ["1 - 0.72 * safePhase(fraction)","1f - .72f * HealthAtlasFunctionStory.safePhase(fraction)"],
  ["max(3, Int(12 * Self.glycogenRemaining(fraction)))","(12f * HealthAtlasHomeostasisMotion.glycogenRemaining(t)).toInt().coerceAtLeast(3)"],
  ["6 - Int(t * 4)","6 - (t * 4f).toInt()"],["t * 1.24 + Double(i) / 6","t * 1.24f + i / 6f"],
  ["t * 1.30 + Double(i) / 4","t * 1.30f + i / 4f"],["t > 0.38","t > .38f"],
  ["t * 1.19 + Double(i) / 6","t * 1.19f + i / 6f"],["1 - 0.68 * Motion.loop","1f - .68f * loop"],
  ["0.43 * (1 - Motion.loop"," .43f * (1f - loop"],["0.24 * (1 - Motion.loop",".24f * (1f - loop"],
  ["5.5 + 12 * t","5.5f + 12f * t"],["21 * sqrt(Motion.liquidRemaining(t, humid: humid))","21f * sqrt(HealthAtlasHomeostasisMotion.liquidRemaining(t, humid))"],
  ["humid ? 2 : 5","if (humid) 2 else 5"],["humid ? 0.85 : 1.43","if (humid) .85f else 1.43f"],
  ["humid ? 15 : 12","if (humid) 15f else 12f"],["humid ? 44 : 66","if (humid) 44f else 66f"],
  ["baseY - 2.2 * r","baseY - 2.2f * r"],["baseY - 1.74 * r","baseY - 1.74f * r"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["local.translateBy(x: 0, y: 42)","HealthAtlasFunctionAlpha","HealthAtlasLiver","Motion.glucoseExit"])assert(glucagon.includes(token),token);
for(const token of ["local.translateBy(x: 0, y: 56)","HealthAtlasFunctionSweatGland","if !humid",
  "Motion.sweatDuct","drawing.rounded(x - 2.8","Self.salt"])assert(sweat.includes(token),token);
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_home_(\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_home_'+key+'"'),key);
}
const folder=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasLiver.imageset");
const filename=JSON.parse(fs.readFileSync(path.join(folder,"Contents.json"))).images[0].filename;
assert(show("res/drawable-nodpi/health_atlas_liver.png").equals(fs.readFileSync(path.join(folder,filename))));
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-homeostasis"],{cwd:root,stdio:"inherit"});
assert(view.includes("atlas-function-sweat-cooling-art"));assert(view.includes("atlas-function-glucagon-response-art"));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "GLUCAGON_RESPONSE", "SWEAT_COOLING": GalaxySSIHealthAtlasHomeostasisView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["HomeostasisMotion","HomeostasisView","GlucagonDrawing","SweatDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 homeostasis source audit: two five-stage courses, five exact routes including eleven-segment eccrine duct, glycogen/relative-liquid rules, reverse transport/salt recovery, dry/humid evaporation and original art. Native compilation/pixels unverified.");
