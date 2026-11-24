// Pinned source geometry/formulas only; not native compilation or acid-secretion validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGastricAcidStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","View","PlateDrawing","LocatorDrawing","TransportDrawing","FeedbackDrawing"].map(n=>"GalaxySSIHealthAtlasGastricAcid"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),geometry=files[1];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\s/g,"");
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
const sourcePath=name=>source.match(new RegExp("private val "+name+" = "+(name.endsWith("Track")?"track\\(":"")+"shape \\{([^}]+)\\}"))[1];
for(const name of ["stomach","folds","gland","glandSpace","cell","vessel","canaliculus","feedbackReturn"]){
  const to=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(sourcePath(name)),name);
}
for(const name of ["locatorTrack","secretionTrack"]){
  const start=geometry.indexOf("static let "+name),end=geometry.indexOf("\n  static ",start+1),block=geometry.slice(start,end<0?geometry.length:end);
  const first=block.match(/start: \.init\(x: ([\d.]+), y: ([\d.]+)\)/);
  const commands=[...block.matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]\)/g)].map(m=>[
    {cubic:"cubicTo",quad:"quadTo",line:"lineTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>v[1])
  ]);
  assert.deepEqual([["moveTo",first[1],first[2]],...commands],fromCommands(sourcePath(name)),name);
}
const sourceCallouts=[...source.matchAll(/callout\(c, R\.string\.health_atlas_(\w+),([\s\S]*?)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
const nativeCallouts=[...all.matchAll(/gastricAcidCallout\("([^"]+)",([\d.,]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
assert.equal(sourceCallouts.length,11);assert.deepEqual(nativeCallouts,sourceCallouts,"callout anchors");
const sourceKeys=[...source.matchAll(/key\(c, R\.string\.health_atlas_(\w+), ([\d.]+)f, (\w+)\)/g)].map(m=>m.slice(1)).sort();
const nativeKeys=[...all.matchAll(/gastricAcidKey\("([^"]+)",([\d.]+),color: GastricTransport\.(\w+)\)/g)].map(m=>m.slice(1)).sort();
assert.deepEqual(nativeKeys,sourceKeys,"ion legend positions/types");
for(const [name,start,end] of [["locate",0.04,0.82],["histamine",0.02,0.43],["recruit",0.26,0.92],["exchange",0.1,0.86],["chloride",0.04,0.64],["lumen",0.18,0.98],["feedback",0.06,0.7]]){
  const sourceRamp=source.match(new RegExp("fun "+name+"\\(t: Float\\) = ease\\(t, ([\\d.]+)f, ([\\d.]+)f\\)"));
  const nativeRamp=files[0].match(new RegExp("func "+name+"\\(_ t: Double\\) -> Double \\{ ease\\(t,start: ([\\d.]+),end: ([\\d.]+)\\)"));
  assert(sourceRamp&&nativeRamp,name);
  assert.deepEqual(sourceRamp.slice(1).map(Number),[start,end],name+" source");
  assert.deepEqual(nativeRamp.slice(1).map(Number),[start,end],name+" native");
}
for(const [swift,kotlin] of [
  ["1 - 0.74 * ease(t,start: 0.32,end: 0.93)","1f - .74f * ease(t, .32f, .93f)"],
  ["lumen(t) * 1.16 - 0.15 * Double(index)","flow * 1.16f - .15f * i"],
  ["f > 0.01 && f < 0.98","f > .01f && f < .98f"],
  ["Int(156 * acidity)","(156f * acidity).toInt()"],
  ["fraction < 0.92","fraction < .92f"],
  ["7 * (1 - fraction * 0.55)","7f * (1f - fraction * .55f)"],
  ["198 + 18 * q,103 + 47 * q","198f + 18f * q, 103f + 47f * q"],
  ["245 - 5 * q,131 + 20 * q","245f - 5f * q, 131f + 20f * q"],
  ["if p < 0.99","if (p < .99f)"],
  ["117 + 55 * p","117f + 55f * p"],["172 - 55 * p","172f - 55f * p"],
  ["219 - 49 * p","219f - 49f * p"],
  ["3 + 4 * output","3f + 4f * output"],
  ["291 - 33 * output","291f - 33f * output"],
  ["181 + 40 * ((p - 0.3) / 0.7)","181f + 40f * ((p - .3f) / .7f)"],
  ["9 + 3 * (1 - p)","9f + 3f * (1f - p)"],
  ["15 + 3 * wave(p * 0.5)","15f + 3f * wave(p * .5f)"],
  ["226 - Double(i) * 1.7,156 + 21 * Double(i)","226f - i * 1.7f, 156f + 21f * i"],
  ["268 + 1.6 * Double(i % 2),157 + 21 * Double(i)","268f + 1.6f * (i % 2), 157f + 21f * i"],
  ["[(130,142,-58),(157,99,-24),(235,116,27),(224,241,-37),(113,203,64)]","mitochondrion(c, 130f, 142f, -58f)"],
  ["if color == GastricTransport.chloride","if (color == chloride)"],
  ["if color == GastricTransport.potassium","if (color == potassium)"],
  ["rounded(x - 3.6,y - 3.6,x + 3.6,y + 3.6,1,color)","rounded(c, x - 3.6f, y - 3.6f, x + 3.6f, y + 3.6f, 1f, color)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["98606D","CE8B94","626B70","9B632E","D4EBEA","527B83","A64337","705387","28766E","F5C8B7","D9888A","F8DDD0","E0A9AA","FFEAD0","E3A298","DFB1CC","B886AA","F9D6C5","F1B59E","EBC4C1","BE89A9","A76379","ECC2C6","A46F98","E5A07B","EFC2A1","DDC2D4","E8D5E5"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(gastric_acid_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["gastricAcidCellPlate(GalaxySSIHealthAtlasGastricAcidMotion.lumen(t))","acid.opacity *=",
  "local.translateBy(x: 73, y: -44); local.scaleBy(x: 0.76, y: 0.76)","arrow(207,117,207,172,GastricTransport.acid)","arrow(226,172,226,117,GastricTransport.potassium)",
  "arrow(208,219,208,170,GastricTransport.chloride)","x - 62,337","label(key,x,342,111)","label(key,x,y,width)","if p > 0.3"
])assert(all.includes(token),token);
assert(!files[3].includes("clip("),"canaliculus remains open to the external lumen, not clipped to the cell");
assert(all.includes("atlas-function-parietal-secretion-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "GASTRIC_ACID_SECRETION": GalaxySSIHealthAtlasGastricAcidView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 gastric acid source audit: eight exact outlines/two routes, seven ramp windows/nonzero feedback floor, opposite exchange lanes, distinct ion markers, callout anchors and bilingual resources. No native compilation/pixels verified.");
