// Pinned source geometry/formulas only; not native compilation or tissue-renewal validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasEndometriumStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","View","SectionDrawing","GlandDrawing","RepairDrawing","LabelsDrawing"].map(n=>"GalaxySSIHealthAtlasEndometrium"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),geometry=files[1];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replaceAll("Motion.basal","BASAL").replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm).filter(Boolean)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
for(const name of ["uterus","uterineCavity"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
const guideSource=fromCommands(source.match(/private val sectionGuide = track\(Path\(\).apply \{([^}]+)\}/)[1]);
const guide=geometry.match(/static let sectionGuide = Route([\s\S]*?)\n  \]\)/)[1];
const guideStart=guide.match(/start: \.init\(x: ([\d.]+), y: ([\d.]+)\)/);
const guideCommands=[...guide.matchAll(/\.init\(kind: \.line, points: \[\.init\(x: ([\d.]+), y: ([\d.]+)\)\]/g)].map(m=>["lineTo",...m.slice(1)]);
assert.deepEqual([["moveTo",...guideStart.slice(1)],...guideCommands],guideSource,"section guide");
const channelSource=source.match(/private fun drawGland[\s\S]*?channel.rewind\(\)([\s\S]*?)c.save\(\)/)[1];
const channelNative=geometry.slice(geometry.indexOf("static func channel"));
const nativeStart=channelNative.match(/return \.init\(start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
const nativeCurves=[...channelNative.matchAll(/commands.append\(\.init\(kind: \.cubic, points: \[([^\]]+)\]\)\)/g)].map(m=>["cubicTo",...[...m[1].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
assert.deepEqual([["moveTo",...nativeStart.slice(1).map(norm)],...nativeCurves],fromCommands(channelSource),"gland control points");
const fragmentSource=source.match(/private fun drawFragments[\s\S]*?path.rewind\(\)([\s\S]*?)path.close\(\)/)[1]+"close()";
const fragmentNative=files[5].match(/func endometriumFragments[\s\S]*?var path = Path\(\);([\s\S]*?)var local = art.context/)[1].replaceAll("path.","p.");
assert.deepEqual(toCommands(fragmentNative),fromCommands(fragmentSource),"fragment contour");
const sourceCalls=source.replace("if (step == 1) 250f else 216f","stromaTarget");
const nativeCalls=all.replace("step == 1 ? 250 : 216","stromaTarget");
const expectedCalls=[...sourceCalls.matchAll(/callout\(c, R\.string\.health_atlas_(\w+), (true|false),([^)]*)\)/g)].map(m=>[m[1],m[2],...m[3].split(",").map(norm)]).sort();
const actualCalls=[...nativeCalls.matchAll(/endometriumCallout\("([^"]+)",left: (true|false),([^)]*)\)/g)].map(m=>[m[1],m[2],...m[3].replace(/(?:anchorX|anchorY|y): /g,"").split(",").map(norm)]).sort();
assert.equal(expectedCalls.length,9);assert.deepEqual(actualCalls,expectedCalls,"stage-specific callout anchors");
for(const [swift,kotlin] of [
  ["left = 106.0, right = 254.0, basal = 244.0, muscle = 281.0","const val BASAL = 244f"],
  ["glandSites = [129.0,177,228]","glandSites = floatArrayOf(129f, 177f, 228f)"],
  ["244 - (244 - 161)","BASAL - (BASAL - 161f)"],
  ["ramp(t,from: 0.05,to: 0.91)","ramp(t, .05f, .91f)"],
  ["161 - 12","161f - 12f"],["ramp(t,from: 0.02,to: 0.75)","ramp(t, .02f, .75f)"],
  ["ramp(t,from: 0.08,to: 0.78)","ramp(t, .08f, .78f)"],
  ["erosion = step == 3 ? t : nil","if (step == 3) t else null"],
  ["1.6 * wave((x - left) / 52) * (depth / 95)","1.6f * wave((x - LEFT) / 52f) * (depth / 95f)"],
  ["0.11 + 0.24 * abs(wave((x - 182) / 145)) + 0.08 * wave((x - left) / 45)",".11f + .24f * abs(wave((x - 182f) / 145f)) + .08f * wave((x - LEFT) / 45f)"],
  ["basal - (depth - ripple) * (1 - ramp(erosion,from: lag,to: lag + 0.47))","BASAL - (depth - ripple) * (1f - ramp(erosion, lag, lag + .47f))"],
  ["Double(index * 31 % 133)","(i * 31 % 133)"],["index % 3 == 0","i % 3 == 0"],
  ["0.13 + Double(index * 19 % 73) / 100",".13f + (i * 19 % 73) / 100f"],
  ["frame.top == basal","top == BASAL"],
  ["3.2 - 0.5 * rounding","3.2f - .5f * rounding"],["1.1 + 1.1 * rounding","1.1f + 1.1f * rounding"],
  ["index == 1 ? -1.0 : 1.0","if (i == 1) -1f else 1f"],
  ["10 + 3.4 * bend","10f + 3.4f * bend"],
  ["width - 5.3","width - 5.3f"],
  ["0.14 + 0.12 * Double(particle) + 0.05 * Double(gland),to: 0.84 + 0.06 * Double(particle)",".14f + .12f * j + .05f * i, .84f + .06f * j"],
  ["(1 - travel) * (0.62 - 0.17 * Double(particle))","(1f - travel) * (.62f - .17f * j)"],
  ["1.2 + 1.2 * ramp(t,from: 0.18,to: 0.58)","1.2f + 1.2f * ramp(t, .18f, .58f)"],
  ["0.06 + Double(index) * 0.14,to: 0.6 + Double(index) * 0.12",".06f + i * .14f, .6f + i * .12f"],
  ["ramp(move,from: 0,to: 0.18) * (1 - ramp(move,from: 0.64,to: 1))","ramp(move, 0f, .18f) * (1f - ramp(move, .64f, 1f))"],
  ["Int(215 * opacity)","(215 * opacity).toInt()"],
  ["3 + 24 * ramp(t,from: 0.04 + Double(index) * 0.07,to: 0.85 + Double(index) * 0.06)","3f + 24f * ramp(t, .04f + i * .07f, .85f + i * .06f)"],
  ["ramp(erosion,from: 0.56,to: 0.96)","ramp(erosion, .56f, .96f)"],
  ["guard radius > 3","if (radius <= 3f) return"],
  ["x - 3,EndometriumRepair.basal - 1","x - 3f, BASAL - 1f"],
  ["x + 3,EndometriumRepair.basal - 1","x + 3f, BASAL - 1f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["96576D","50686E","E1EEEA","F9DDD6","EDBEC9","DDA2B3","D490A6","D39083","E3AD91","BF8A83","EAB6A3","9D6268","A8BDB7","AF736F","BF869D","A5707C","AC7087","B87B92","B7788A","EFB1B9","AD782F","BB788C","9C8586"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(endometrium_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["for i in 1...40","var tissue = profile","tissue.closeSubpath()","frame.top < EndometriumTissue.basal","CGRect(x: 106, y: 117, width: 148, height: 127)",
  "surface(x,top: frame.top,erosion: nil)","secreting: frame.step == 2","local.clip(to: tissue)","outside.addPath(tissue)","local.clip(to: outside,style: FillStyle(eoFill: true))",
  "endometriumOutside(section.tissue).endometriumRepairEdge","let art = endometriumOutside(tissue)","Double(fragment.alpha) / 255","frame.erosion != nil || frame.step == 4"
])assert(all.includes(token),token);
assert.equal((source.match(/clipOutPath\(tissue\)/g)||[]).length,2);
assert(all.includes("atlas-function-endometrium-renewal-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "ENDOMETRIUM_RENEWAL": GalaxySSIHealthAtlasEndometriumView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 endometrium source audit: exact uterus/guide/gland/fragment paths, erosion/stromal/secretion windows, retained basal layer, tissue/complement clip wiring, repair openings and bilingual anchors. No native compilation/pixels verified.");
