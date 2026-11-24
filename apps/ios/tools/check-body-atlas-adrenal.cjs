// Pinned source geometry/formulas only; not native compilation or endocrine-function validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasAdrenalMedullaStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","View","PrimitivesDrawing","LocatorDrawing","SignalReleaseDrawing","CirculationDrawing"].map(n=>"GalaxySSIHealthAtlasAdrenal"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),geometry=files[1];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\s/g,"");
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
const sourcePath=name=>source.match(new RegExp("private val "+name+" = "+(name==="entryTrack"?"track\\(":"")+"Path\\(\\).apply \\{([^}]+)\\}"))[1];
for(const name of ["kidney","gland","cortex","medulla","receivingCell"]){
  const to=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(sourcePath(name)),name);
}
for(const name of ["cortex","medulla","nerve","nerveBranch","capillary","entryTrack","restingVessel","recoveryCurve"]){
  const start=geometry.indexOf("static let "+name+"Route"),end=geometry.indexOf("\n  static ",start+1),block=geometry.slice(start,end);
  const first=block.match(/start: \.init\(x: ([\d.]+), y: ([\d.]+)\)/);
  const commands=[...block.matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]\)/g)].map(m=>[
    {cubic:"cubicTo",quad:"quadTo",line:"lineTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>v[1])
  ]);
  // Cortex/medulla close at the same endpoint; their close operation has zero added length.
  assert.deepEqual([["moveTo",first[1],first[2]],...commands],fromCommands(sourcePath(name)).filter(c=>c[0]!=="close"),name+" route");
}
const membraneSource=source.match(/with\(secretingCell\) \{([\s\S]*?)\n        \}/)[1];
const membraneNative=geometry.match(/static func secretingCell[\s\S]*?Path \{ p in([\s\S]*?)\n    \}/)[1];
assert.deepEqual(toCommands(membraneNative),fromCommands(membraneSource),"opening membrane control points");
assert(geometry.includes("if pore > 0"));assert(source.includes("if (pore > 0f)"));
const sourceLeaders=[...source.matchAll(/leader\(c, string\.health_atlas_(\w+), ([\d.f, ]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
const nativeLeaders=[...all.matchAll(/adrenalLeader\("([^"]+)",([\d.,]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
assert.equal(sourceLeaders.length,13);assert.deepEqual(nativeLeaders,sourceLeaders,"leader positions");
const sourceLabels=[...source.matchAll(/label\(c, string\.health_atlas_(\w+), ([\d.f, ]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
const nativeLabels=[...all.matchAll(/label\("([^"]+)",([\d.,]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]).sort();
assert.deepEqual(nativeLabels,sourceLabels,"direct labels");
for(const [swift,kotlin] of [
  ["outer = t < 0.47, fraction = outer ? t / 0.47 : (t - 0.47) / 0.53","val fraction = if (outer) t / .47f else (t - .47f) / .53f"],
  ["ease((1 - fraction) * 4)","ease((1f - fraction) * 4f)"],
  ["(safe(t) - 0.14 * Double(index)) / 0.68","(t - .14f * i) / .68f"],
  ["(safe(t) - 0.54 - 0.14 * Double(index)) / 0.25","(t - .54f - .14f * i) / .25f"],
  ["ease(safe(t) / 0.46)","ease(t / .46f)"],
  ["ease((safe(t) - 0.46) / 0.12)","ease((t - .46f) / .12f)"],
  ["center = 184.0, mouth = 2 + 4 * pore","val mouth = 2f + 4f * pore"],
  ["(safe(t) - 0.47 - Double(index) * 0.043) / 0.31","(t - .47f - i * .043f) / .31f"],
  ["184 + (Double(index) - 2.5) * (1.3 + 5 * f)","center + (i - 2.5f) * (1.3f + 5f * f)"],
  ["206 + (55 + 5 * Double(index % 3)) * f","206f + (55f + 5f * (i % 3)) * f"],
  ["1 - 0.42 * f","1f - .42f * f"],
  ["safe(t) * 1.08 - Double(index) * 0.11 + 0.15","t * 1.08f - i * .11f + .15f"],
  ["min(1,min(14 * phase,12 * (1 - phase)))","minOf(1f, 14f * phase, 12f * (1f - phase))"],
  ["safe(2 + 8 * remaining - Double(index))","(2f + 8f * remaining - i).coerceIn(0f, 1f)"],
  ["0.64 * t + Double(index) * 0.113",".64f * t + i * .113f"],
  ["min(1,min(10 * f,10 * (1 - f))) * strength","minOf(1f, 10f * f, 10f * (1f - f)) * strength"],
  ["phase + Double(index) * 0.21","phase + i * .21f"],
  ["min(1,min(f * 16,(1 - f) * 16))","minOf(1f, f * 16f, (1f - f) * 16f)"],
  ["0.74 * t",".74f * t"],["0.52 * t",".52f * t"],
  ["Int(255 * safe(value))","(alpha.coerceIn(0f, 1f) * 255f)"],
  ["Double(i) / 18","i / 18f"],
  ["215 + Double(i) * 7.5","215f + i * 7.5f"],
  ["12 * wave(0.11 * Double(i))","12f * wave(.11f * i)"],
  ["8 * wave(Double(i) * 0.37)","8f * wave(i * .37f)"],
  ["11 * wave(Double(i) * 0.39)","11f * wave(i * .39f)"],
  ["width - 2.6","width - 2.6f"],["width - 9","width - 9f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["5A6C72","96623D","8B5969","986568","6D4A80","A36571","8C682D","DFA2A3","BD7780","F6DBA3","DFA26C","E8B9B7","C78E9D","FFE7D3","E9B4AA","D9989E","CC8791","C48961","D4A4AD","B57D8C","D6B3C9","A37999","AA7F9D","F1D7DD","A57492","D99AA2","F4C4C4","CE7F88","EBB1B4","BA9DBF"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/(?:R\.)?string\.health_atlas_(adrenal_medulla_story_art_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["radial.clip(to: AdrenalLocator.cortex)","edge.trimmedPath(from: 0,to: CGFloat(frame.end))","recovery.trimmedPath(from: 0,to: CGFloat(t))",
  "if pore == 0","guard alpha > 0","local.opacity *=","local.rotate(by: .degrees(45))","local.translateBy(x: 70, y: 77); local.scaleBy(x: 0.38, y: 0.38); local.translateBy(x: -105, y: -134)",
  "for i in 0...5","for i in 0...7","for i in 0...9","ty > y ? y + 5 : y - 15"
])assert(all.includes(token),token);
assert(all.includes("atlas-function-adrenal-medulla-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "ADRENAL_MEDULLA_SIGNAL": GalaxySSIHealthAtlasAdrenalView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 adrenal source audit: five outlines/eight routes, dynamic vesicle pocket, neural/release/circulation windows, residual background, exact label anchors and bilingual resources. No native compilation/pixels verified.");
