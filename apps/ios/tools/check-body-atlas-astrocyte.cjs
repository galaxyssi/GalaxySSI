// Pinned source geometry and wiring only; no native compilation or physiological validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasAstrocyteStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","View","Shapes","AnatomyDrawing","DynamicsDrawing"].map(n=>"GalaxySSIHealthAtlasAstrocyte"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),shapes=files[2];
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>Number(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
for(const name of ["sender","receiver","astrocyte","diamond"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=shapes.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
for(const [swift,kotlin] of [
  ["CGRect(x: 25, y: 283, width: 310, height: 37), cornerRadius: 13","addRoundRect(25f, 283f, 335f, 320f, 13f, 13f"],
  ["[(87,92), (115,91), (134,113)]","arrayOf(87f to 92f, 115f to 91f, 134f to 113f)"],
  ["0.22 + 0.09 * Double(index), duration: 0.38",".22f + .09f * i, .38f"],
  ["0.05 + 0.09 * Double(index), duration: 0.62",".05f + .09f * i, .62f"],
  ["0.10 + 0.10 * Double(index), duration: 0.51",".10f + .10f * i, .51f"],
  ["0.02 + 0.10 * Double(index), duration: 0.54",".02f + .10f * i, .54f"],
  ["0.09 + 0.16 * Double(index), duration: 0.54",".09f + .16f * i, .54f"],
  ["129 + 6 * Double(i), y = 149 + 3 * Double(i)","val x = 129f + 6f * i"],
  ["command(.quad, [x,133,x,y])","quadTo(x, 133f, x, y)"],
  ["[152,144 + offset,163,147 + offset,175,151 + offset]","cubicTo(152f, 144f + offset, 163f, 147f + offset, 175f, 151f + offset)"],
  ["[185,163 + offset,205,159 + offset,218,168 + offset]","cubicTo(185f, 163f + offset, 205f, 159f + offset, 218f, 168f + offset)"],
  ["[229,164 + offset,238 + offset,170 + offset]","quadTo(229f, 164f + offset, 238f + offset, 170f + offset)"],
  ["[220,148 + offset,216,117 + offset,183,100 + offset]","cubicTo(220f, 148f + offset, 216f, 117f + offset, 183f, 100f + offset)"],
  ["[159,88 + offset,125,91]","quadTo(159f, 88f + offset, 125f, 91f)"],
  ["[284,206,266,189]","quadTo(284f, 206f, 266f, 189f)"],
  ["[268,248,253,220]","quadTo(268f, 248f, 253f, 220f)"],
  ["[174,185,191,172]","quadTo(174f, 185f, 191f, 172f)"],
  ["if f < 0.58","if (f < .58f)"],
  ["112 + Double(i) * 3, 91 + Double(i % 2) * 3","112f + i * 3f, 91f + (i % 2) * 3f"],
  ["start: 0.58, duration: 0.19",".58f, .19f"],
  ["134 - response * 16","134f - response * 16f"],["171 + response * 17","171f + response * 17f"],
  ["5 + 9 * response","5f + 9f * response"],
  ["-62 + 96 * (Double(i) + t)","-62f + 96f * (i + t)"],
  ["301 + 2.5 * drift","301f + 2.5f * drift"],
  [".degrees(14 * drift)","14f * drift"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["FFEADA","EDBB9C","FFEAD9","E8BA9F","DFEFDA","8FCBBA","FFE2DD","EAB6BB","A2C7B9","86B1A3","79A697","FFE8D3","FAE0AB","C0874E","DE9CA7","EFB8BD","CD929E"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(astrocyte_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(all.includes("local.clip(to: vessel)"));assert(all.includes("if f < 1"));assert(all.includes("if f > 0"));
assert(all.includes("art.stroke(diamond, Self.cream, 1.1)"));
assert(all.includes('atlas-function-astrocyte-support-art'));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "ASTROCYTE_SUPPORT": GalaxySSIHealthAtlasAstrocyteView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 astrocyte source audit: four exact outlines, fifteen routes, delayed release/uptake/conversion/return/buffering, clipped capillary, particle semantics and bilingual labels. No native compilation/pixels verified.");
