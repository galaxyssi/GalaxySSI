// Pinned source geometry/formulas only; not native compilation or respiratory-function validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasBrainstemRhythmStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Shapes","View","ChestDrawing","HeadDrawing","FlowDrawing"].map(n=>"GalaxySSIHealthAtlasBrainstem"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),motion=files[0],shapes=files[1];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replaceAll("GalaxySSIHealthAtlasBrainstemMotion.","").replace(/\s/g,"");
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
const trace=source.match(/private fun Path.traceAirway\(\) \{([^}]+)\}/)[1];
const sourcePath=name=>source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1].replace("traceAirway()",trace);
for(const name of ["body","brain","folds","stem","cord","bronchi"]){
  const to=shapes.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(sourcePath(name)),name);
}
for(const name of ["descending","leftNerve","rightNerve","airway","airRoute"]){
  const start=motion.indexOf("static let "+name+" = Route"),end=motion.indexOf("\n  static let ",start+1),block=motion.slice(start,end<0?motion.length:end);
  const first=block.match(/start: \.init\(x: ([\d.]+), y: ([\d.]+)\)/);
  const commands=[...block.matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]\)/g)].map(m=>[
    {cubic:"cubicTo",quad:"quadTo",line:"lineTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>v[1])
  ]);
  assert.deepEqual([["moveTo",first[1],first[2]],...commands],fromCommands(sourcePath(name)),name);
}
for(const name of ["lung","diaphragm"]){
  const from=source.match(new RegExp(name+"\\.rewind\\(\\)([\\s\\S]*?)stroke\\(c, "+name+"|"+name+"\\.rewind\\(\\)([\\s\\S]*?)shaded\\(c, "+name));
  assert(from,name);
  const to=shapes.match(new RegExp("static func "+name+"[\\s\\S]*?Path \\{ p in([\\s\\S]*?)\\n    \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from[1]||from[2]),name+" deformation");
}
for(const name of ["network","connections"]){
  const from=source.match(new RegExp(name+" = (?:floatArrayOf|intArrayOf)\\(([^)]+)\\)"))[1].split(",").map(v=>Number(norm(v)));
  const to=motion.match(new RegExp(name+" = \\[([^\\]]+)\\]"))[1].split(",").map(Number);
  assert.deepEqual(to,from,name);
}
for(const [swift,kotlin] of [
  ["expiration = time / 0.79","val expiration = t / .79f"],
  ["step == 3 ? Self.ease(time) : step == 4 ? 1 - Self.ease(expiration) : 0","4 -> 1f - ease(expiration)"],
  ["Self.envelope((time * 2).truncatingRemainder(dividingBy: 1))","envelope(t * 2f % 1f)"],
  ["Self.envelope(time / 0.26)","envelope(t / .26f)"],
  ["Self.envelope((time - 0.81) / 0.19)","envelope((t - .81f) / .19f)"],
  ["let travel = t / 0.91","val travel = t / .91f"],
  ["travel <= 0.29","travel <= .29f"],["(travel - 0.29) / 0.71","(travel - .29f) / .71f"],
  ["1.44 * t - 0.19 * Double(index)","1.44f * t - .19f * i"],
  ["(0.08...1).contains(travel)","travel !in .08f..1f"],
  ["head - 0.077 * direction","head - .077f * direction"],
  ["276 + 10 * expansion","276f + 10f * expansion"],
  ["56 + 5 * expansion","56f + 5f * expansion"],
  ["(side == 0 ? 265.0 : 271.0) + 16 * expansion","(if (side == 0) 265f else 271f) + 16f * expansion"],
  ["side == 0 ? 0.0 : 9.0","if (side == 0) 0f else 9f"],
  ["end - 0.23","end - .23f"],["if step == 4 && frame.expiration < 1","if (step == 4 && expiration < 1f)"],
  ["Int(220 * BrainstemNetwork.envelope(t))","(220f * pulse).toInt()"],
  ["3.4 + 2.8 * burst","3.4f + 2.8f * burst"],
  ["if burst > 0.25","if (burst > .25f)"],
  ["contracting ? 8 : 7","if (contracting) 8f else 7f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["657482","69518E","AD98BB","356E8E","AB5661","F9E9D9","F2D8D0","F8CADB","E5AABF","FFE1D8","E9B0B2","C69B94","B47C93","C187A1","CDB7DF","E2B6A9","B77887","CE939D","EFAC9A","EDC0AE","B48676","F1D3B3","F5DCC0","A78DB5","E0C7E4","8B70A3","D2BAE0"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(brainstem_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["local.clip(to: lung)","local.translateBy(x: 181, y: 0)","side == 0 ? -1 : 1","path.trimmedPath(from: CGFloat(max(0,end - 0.23)),to: CGFloat(end))","if step == 2","if step == 3","if let branch = progress.branch","pulse.opacity *="])assert(all.includes(token),token);
assert(all.includes("atlas-function-brainstem-rhythm-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "BRAINSTEM_RHYTHM": GalaxySSIHealthAtlasBrainstemView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 brainstem source audit: six exact outlines/five routes, lung/diaphragm curves, network topology, motor branching/trails, respiratory gating and bilingual labels. No native compilation/pixels verified.");
