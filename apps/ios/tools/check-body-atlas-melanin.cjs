// Pinned geometry/source wiring only; no native compilation or UV-protection validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMelaninStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasMelaninMotion.swift"),view=local("GalaxySSIHealthAtlasMelaninView.swift"),tissue=local("GalaxySSIHealthAtlasMelaninTissueDrawing.swift"),drawing=local("GalaxySSIHealthAtlasMelaninDrawing.swift"),all=motion+view+tissue+drawing;
const section=(text,start,next)=>{const a=text.indexOf(start);assert(a>=0,start);const b=text.indexOf(next,a+start.length);return text.slice(a,b<0?text.length:b);};
for(const name of ["storage","arrivals","residentPigment"]){
  const from=section(source,"private val "+name,"private val");
  const to=section(motion,"static let "+name,"static let");
  const expected=[...from.matchAll(/Point\(([-\d.]+)f, ([-\d.]+)f\)/g)].map(m=>m.slice(1).map(Number));
  const actual=[...to.matchAll(/\.init\(x: ([-\d.]+), y: ([-\d.]+)\)/g)].map(m=>m.slice(1).map(Number));
  assert.deepEqual(actual,expected,name);
}
const sourceCells=section(source,"private val cells","private val recipient"),nativeCells=section(motion,"static let cells","static let storage");
const cells=[...sourceCells.matchAll(/Cell\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
const native=[...nativeCells.matchAll(/\.init\(x: ([\d.]+), y: ([\d.]+), rx: ([\d.]+), ry: ([\d.]+)\)/g)].map(m=>m.slice(1).map(Number));
assert.equal(cells.length,16);assert.deepEqual(native,cells);
const branches=section(source,"private val branches","private val branchTracks").replaceAll("tip.x","197f").replaceAll("tip.y","200f");
const expectedBranches=[...branches.matchAll(/Path\(\).apply \{([^}]+)\}/g)].map(m=>[...m[1].matchAll(/(?:moveTo|cubicTo)\(([^)]+)\)/g)].map(c=>c[1].split(",").map(v=>Number(v.trim().replace(/f$/,"")))));
const nativeBranches=[...section(motion,"static let branches","static let transferTracks").matchAll(/route\((\d+), (\d+), \[([^\]]+)\]\)/g)].map(m=>[[Number(m[1]),Number(m[2])],JSON.parse("["+m[3]+"]")]);
assert.equal(nativeBranches.length,3);assert.deepEqual(nativeBranches,expectedBranches);
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
const fromCommands=block=>[...block.matchAll(/(moveTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));return m[1]==="move"?["moveTo",...n]:["cubicTo",...n.slice(2),...n.slice(0,2)];
});
for(const name of ["recipient","donor"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
const waferSource=source.match(/private fun wafer[\s\S]*?path\.rewind\(\)([\s\S]*?)path\.close\(\)/)[1]+"close()";
const waferNative=view.match(/static func wafer[\s\S]*?return Path \{ p in([\s\S]*?)\n    \}/)[1];
assert.deepEqual(toCommands(waferNative),fromCommands(waferSource),"wafer contour");
for(const [swift,kotlin] of [
  ["0.22 + 0.78 * progress(t, start: Double(index) * 0.07, end: 0.52 + Double(index) * 0.07)",".22f + .78f * progress(t, i * .07f, .52f + i * .07f)"],
  ["0.69 + 0.13 * Double(index)",".69f + .13f * i"],["0.99 - 0.15 * Double(index)",".99f - .15f * i"],
  ["0.84 * progress(t, start: 0.11 * Double(branch), end: 0.95)",".84f * progress(t, .11f * i, .95f)"],
  ["(safe(time) - Double(index) * 0.21) / 0.52","(t - i * .21f) / .52f"],["if event < 0.24","if (event < .24f)"],
  ["progress(event, start: 0.24, end: 1)","progress(event, .24f, 1f)"],
  ["[206,197,213,target.y + 3,target.x,target.y]","cubicTo(206f, 197f, 213f, target.y + 3f, target.x, target.y)"],
  ["[228.0, 236, 243, 251, 259]","floatArrayOf(228f, 236f, 243f, 251f, 259f)"],
  ["[168.0, 163, 162, 163, 168]","floatArrayOf(168f, 163f, 162f, 163f, 168f)"],
  ["index < 3 ? 216 + 3 * Double(index) : start.x","if (index < 3) 216f + 3f * index else start.x"],
  ["0.58 + 0.04 * Double(index)",".58f + .04f * i"],
  ["index == 2 ? 122 : y - 70","if (i == 2) 122f else y - 70f"],
  ["index == 2 ? 170 : Int(195 - 155 * progress(end, start: y - 5, end: y + 9))","if (i == 2) 170 else (195f - 155f * progress(end, y - 5f, y + 9f)).toInt()"],
  ["Int(31 + 22 * wave(focus - 0.25))","(31f + 22f * wave(focus - .25f)).toInt()"],
  ["1 + 1.9 * amount","1f + 1.9f * amount"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["if step < 4", "case .envelope(let f)","case .core(let f)","sideBranchesOnly: true", "residentPigment.prefix(2)",
  "if let focus", "melaninAlpha(43).line", "melaninAlpha(uv.alpha).line", "max(80, uv.endY - 12)","case 1, 2:","height: 1.46 * r"])assert(all.includes(token),token);
for(const color of ["548E83","BDE4D2","774723","635C69","FFEEDC","EECAC1","FFE9D8","F0BFB8","FFEDDE","F2C3A8","CEF0DD","A5D3C6","FFD99E","AD794D","7963A7"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(melanin_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-melanin-transfer-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "MELANIN_TRANSFER": GalaxySSIHealthAtlasMelaninView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["MelaninMotion","MelaninView","MelaninTissueDrawing","MelaninDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 melanin source audit: source cell/wafer geometry and point sets, three branches/transfer tracks/five cap tracks, envelope-to-core handoff, UV cues and bilingual labels. No native compilation/pixels verified.");
