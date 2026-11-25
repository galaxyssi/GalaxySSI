// Pinned geometry/source wiring only; no native compilation or secretion-model validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSalivaStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasSalivaMotion.swift"),view=local("GalaxySSIHealthAtlasSalivaView.swift"),drawing=local("GalaxySSIHealthAtlasSalivaDrawing.swift"),all=motion+view+drawing;
const commands=block=>[...block.matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
const parotid=source.match(/private val parotidDuct = shape \{([^}]+)\}/)[1];
const mouthExtension=source.match(/private val mouthTrack = track\(Path\(parotidDuct\).apply \{([^}]+)\}/)[1];
for(const [name,block] of [["cheekTrack",parotid],["mouthTrack",parotid+mouthExtension],
  ...["fluidTrack","proteinTrack"].map(name=>[name,source.match(new RegExp("private val "+name+" = track\\(shape \\{([^}]+)\\}"))[1]])]){
  const c=JSON.parse("["+motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"))[1]+"]");
  assert.deepEqual([[c[0],c[1]],...c.slice(2)],commands(block),name);
}
for(const name of ["head","mouth","tongue","jaw","acinarCell","lumen"]){
  const from=source.match(new RegExp("private val "+name+" = shape \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="addCurve"||m[1]==="addQuadCurve"?[m[1]==="addCurve"?"cubicTo":"quadTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
  });assert.deepEqual(actual,expected,name);
}
for(const [swift,kotlin] of [
  ["end * (safe(t) + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1)","end * ((t + i.toFloat() / count) % 1f)"],
  ["173 + 152 * (safe(t) + Double(index) / 7).truncatingRemainder(dividingBy: 1)","173f + 152f * ((t + i / 7f) % 1f)"],
  ["209 + 11 * t, y: 262 - 30 * t","209f + 11f * t, 262f - 30f * t"],["284 - 11 * t, y: 300 - 30 * t","284f - 11f * t, 300f - 30f * t"],
  ["29 - 16 * t","29f - 16f * t"],["(t + 0.5).truncatingRemainder(dividingBy: 1)","(t + .5f) % 1f"],
  ["x + 0.68 * Double(i) * r","x + .68f * i * r"],["i == 0 ? 0.55 : 0.27","if (i == 0) .55f else .27f"],
  ["r * 0.62","r * .62f"],["r * 0.13","r * .13f"],
  ["169 + 23 * Double(i)","169f + 23f * i"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["if step == 0", "if step == 4", "case 0, 1:","case 2:","case 3:","case 4:", "step == 1 && angle == 240",
  "stride(from: 60, through: 300, by: 60)","local.translateBy(x: 111, y: 267); local.rotate(by: .degrees(Double(angle)))",
  "count: 3, end: 0.88, radius: 2.3", "count: 4, end: 1, radius: 2.4", "count: 4, end: 1, radius: 2.25",
  "salivaDuctWall(237, 255); salivaDuctWall(277, 295)","if i % 3 == 0","arrow(209, 262, 220, 232, Self.violet)","arrow(284, 300, 273, 270, Self.teal)"])assert(all.includes(token),token);
for(const color of ["9E6574","62666D","B9E1E8","397F95","E8BB64","FFE8D8","EDC0B2","FFEADB","E9ACAC","E9BD81","D9ABD0","B7D4B0","F7E8DF","E5BACB","C6A2CB"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(saliva_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-saliva-secretion-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "SALIVA_SECRETION": GalaxySSIHealthAtlasSalivaView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["SalivaMotion","SalivaView","SalivaDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 saliva source audit: six source outlines, four exact tracks, five-angle acinar cutaway, fluid/protein release, directional sodium/potassium exchange, mouth flow and bilingual labels. No native compilation/pixels verified.");
