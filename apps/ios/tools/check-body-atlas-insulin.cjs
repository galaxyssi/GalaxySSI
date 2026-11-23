// Source/resource integration audit, not Swift execution or native playback.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasInsulinStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasInsulinMotion.swift"),view=local("GalaxySSIHealthAtlasInsulinView.swift"),scenes=local("GalaxySSIHealthAtlasInsulinScenes.swift"),all=motion+view+scenes;
for(const [swift,kotlin] of [
  ["fusionStart = 0.54","FUSION_START = .54f"],["1 - ease(interval(t, 0.04, 0.68))","1f - ease(interval(t, .04f, .68f))"],
  ["ease(interval(t, 0.04, 0.34))","ease(interval(t, .04f, .34f))"],["ease(interval(t, 0, fusionStart))","ease(interval(t, 0f, FUSION_START))"],
  ["ease(interval(t, fusionStart, 0.72))","ease(interval(t, FUSION_START, .72f))"],
  ["0.60 + 0.075 * Double(index), 0.90 + 0.04 * Double(index)",".60f + .075f * index, .90f + .04f * index"],
  ["239 - 64 * Self.approach(fraction)","239f - 64f * HealthAtlasInsulinDiagram.approach(t)"],
  ["fraction * (1.15 + open * 0.25) + Double(i) / 5","t * (1.15f + open * .25f) + i / 5f"],
  ["Double(i) < (open - 0.4) / 0.6 * 5","i < (open - .4f) / .6f * 5f"],
  ["222 - 132 * f","222f - 132f * f"],["185 + f * 52","185f + f * 52f"],
  ["0.38 + 0.59 * open",".38f + .59f * open"],["87 + 153 * min(f, passage)","87f + 153f * minOf(f, passage)"],
  ["(y - 163) * 0.29","(y - 163f) * .29f"],["open > 0.67 || y < 127","open > .67f || y < 127f"],
  ["open > 0.64","open > .64f"],["aperture < 0.09","aperture < .09f"],["177 - 94 * f","177f - 94f * f"],
  ["5 + 20 * pore","5f + 20f * pore"],["4 + 8 * open","4f + 8f * open"],["open < 0.40","open < .40f"],
  ["t * 1.1 + Double(i) / 6","t * 1.1f + i / 6f"],["2 * min(x - 8, 352 - x)","2f * minOf(x - 8f, 352f - x)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
const block=source.match(/private val bloodRoute = PathMeasure\(Path\(\).apply \{([\s\S]*?)\n    \}, false\)/);assert(block);
const expected=[...block[1].matchAll(/(?:moveTo|quadTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
const actual=[[190,111],...[...motion.matchAll(/\.init\(kind: \.quad, points: \[([^\]]+)\]/g)].map(m=>[...m[1].matchAll(/\.init\(x: ([\d.]+), y: ([\d.]+)\)/g)].flatMap(p=>[Number(p[1]),Number(p[2])]))];
assert.deepEqual(actual,expected);
for(const token of ["var body = membrane","gate - 18, y: y - 8, width: 36, height: 16","FillStyle(eoFill: true)",
  "drawing.stroke(membrane, Self.membrane, 8)","drawing.stroke(membrane, 0xECC6A0, 5.5)",
  "!(147...216).contains(x)","HealthAtlasFunctionIslet","atlas-function-insulin-secretion-art"])assert(all.includes(token),token);
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_insulin_art_(\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_insulin_art_'+key+'"'),key);
}
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-insulin"],{cwd:root,stdio:"inherit"});
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "INSULIN_SECRETION": GalaxySSIHealthAtlasInsulinView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["InsulinMotion","InsulinView","InsulinScenes"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 insulin source audit: five stages, distinct ion-channel/fusion/release thresholds, source blood route, membrane pore and channel clipping, original gradient islet and both languages. Native compilation/pixels unverified.");
