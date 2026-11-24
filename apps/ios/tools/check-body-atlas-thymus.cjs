// Pinned source geometry/formulas only; not native compilation or immune-function validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasThymusStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Shapes","View","AnatomyDrawing","CellDrawing","DynamicsDrawing"].map(n=>"GalaxySSIHealthAtlasThymus"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),motion=files[0],shapes=files[1];
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>Number(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
const fromShape=name=>source.match(new RegExp("private val "+name+" = shape \\{([^}]+)\\}"))[1];
for(const name of ["tissue","medulla","shoulders","lung","thymicLobe","entryVessel","exitVessel"]){
  const to=shapes.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(fromShape(name)),name);
}
for(const name of ["enter","migrate","leave"]){
  const start=motion.indexOf("static let "+name+" = Route"),end=motion.indexOf("\n  static let ",start+1),block=motion.slice(start,end<0?motion.length:end);
  const first=block.match(/start: \.init\(x: ([\d.]+), y: ([\d.]+)\)/);
  const commands=[...block.matchAll(/\.init\(kind: \.(\w+), points: \[([^\]]+)\]\)/g)].map(m=>[
    {cubic:"cubicTo",quad:"quadTo",line:"lineTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>Number(v[1]))
  ]);
  assert.deepEqual([["moveTo",Number(first[1]),Number(first[2])],...commands],fromCommands(fromShape(name)),name);
}
for(const [swift,kotlin] of [
  ["ramp(t, start: 0, end: 0.55)","ramp(t, 0f, .55f)"],
  ["119 + 27 * contact","119f + 27f * contact"],["126 - 9 * contact","126f - 9f * contact"],
  ["ramp(t, start: 0.47, end: 0.8)","ramp(t, .47f, .8f)"],["selected: t >= 0.72","if (t >= .72f) selected else early"],
  ["ramp(t, start: 0, end: 0.46)","ramp(t, 0f, .46f)"],
  ["ramp(t, start: 0.46, end: 0.89)","ramp(t, .46f, .89f)"],
  ["170 + 24 * approach","170f + 24f * approach"],["186 + 6 * approach","186f + 6f * approach"],
  ["8.5 - 3 * removal","8.5f - 3f * removal"],
  ["Int(255 * (1 - removal))","(255 * (1f - removal)).toInt()"],
  ["Int(185 * (1 - removal))","(185 * (1f - removal)).toInt()"],
  ["0.025 + 0.90 * t",".025f + .90f * t"],
  ["for row in 0...13","for (row in 0..13)"],["for col in 0...15","for (col in 0..15)"],
  ["(row * 17 + col * 13) % 7","(row * 17 + col * 13) % 7"],
  ["88 + 15 * col + (row % 2) * 5 - seed","88f + 15f * col + (row % 2) * 5f - seed"],
  ["88 + 15 * row + seed","88f + 15f * row + seed"],
  ["1.2 + Double(seed) * 0.13","1.2f + seed * .13f"],
  ["146 + 22 * col - row % 2 * 6","146f + 22f * col - row % 2 * 6f"],
  ["151 + 21 * row + (col * 11 % 7)","151f + 21f * row + (col * 11 % 7)"],
  ["160.0 / 255","paint.alpha = 160"],["dash: [2.5,4]","floatArrayOf(2.5f, 4f)"],
  ["thymusAlpha(alpha * 5 / 8)","paint.alpha = alpha * 5 / 8"],
  ["166 + 44 * t,220 + 8 * wave(t * 0.5)","166f + 44f * t, 220f + 8f * wave(t * .5f)"],
  ["x - textWidth / 2 - 9,338,3.4","x - textWidth / 2f - 9f, 338f, 3.4f"],
  ["lobe.scaleBy(x: -1, y: 1.04)","c.scale(-1f, 1.04f, 51.5f, 67f)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["A26476","B48171","805E9A","287C70","986329","527F9B","687177","F5D8DF","DFA8BB","FFECD6","F3CCAF","F5EAE4","BCA7A0","C6E1DF","D995AA","E5A9B8","C98DA6","DAAB9B","F5D5D7","D1E7EE","F9F0C7","EDBDCB","F4BD9D","F9FAF4","F0F4E9"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(thymus_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["cortex.clip(to: ThymusAnatomy.tissue)","medulla.clip(to: ThymusAnatomy.medulla)","if frame.removal < 1","if frame.removal > 0","thymusAlpha(frame.debrisAlpha)","thymusAlpha(Int(200 * (1 - frame.signal)))","position: 1,width: 360,height: 360","7 * Double(end.direction.dx)","context; local.opacity *="])assert(all.includes(token),token);
assert(all.includes("atlas-function-thymic-selection-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "THYMIC_SELECTION": GalaxySSIHealthAtlasThymusView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 thymus source audit: seven exact outlines/three travel routes, clipped tissue densities, positive/negative selection timing, integer layer alpha, dashed travel and bilingual labels. No native compilation/pixels verified.");
