// Pinned geometry/source wiring audit, not native execution or physiological validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasEndothelialStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasEndothelialMotion.swift"),view=local("GalaxySSIHealthAtlasEndothelialView.swift"),drawing=local("GalaxySSIHealthAtlasEndothelialDrawing.swift"),all=motion+view+drawing;
for(const name of ["tileSeam","lymph","tissueCell","soluteShape","proteinShape"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|lineTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addLine|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="addCurve"?["cubicTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
  });assert.deepEqual(actual,expected,name);
}
for(const [swift,kotlin] of [
  ["(time - 0.08 - 0.09 * Double(delay)) / 0.66","(t - .08f - .09f * delay) / .66f"],
  ["f * f * (3 - 2 * f)","f * f * (3f - 2f * f)"],
  ["121 + 17 * Double(i)","121f + 17f * i"],["194 + 9 * Double(i)","194f + 9f * i"],
  [".init(x: x - 6, y: y + 34), .init(x: x - 4, y: 262), .init(x: x + 2, y: 275)","cubicTo(x - 6f, y + 34f, x - 4f, 262f, x + 2f, 275f)"],
  [".init(x: x + 9, y: 292), .init(x: x + 31, y: 287 - 2 * Double(i))","quadTo(x + 9f, 292f, x + 31f, 287f - 2f * i)"],
  ["82 + 121 * down","82f + 121f * down"],["197 - 113 * up","197f - 113f * up"],
  ["72 + 19 * drift","72f + 19f * drift"],["214 + 20 * drift","214f + 20f * drift"],["285 + 23 * drift","285f + 23f * drift"],
  ["startY + (EndothelialMotion.waterTissueY(i) - startY) * f","startY + (waterTissueY(i) - startY) * f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of ["clipped.clip(to: EndothelialShapes.field)","case 1: tissue.arrow(176, 118, 176, 187, Self.blue)",
  "tissue.arrow(86, 117, 86, 191, Self.sienna)","tissue.arrow(201, 191, 201, 117, Self.sienna)",
  "case 4: tissue.arrow(103, 226, 103, 281, Self.teal)","if step == 4", "step == 0 ? 0 : step == 1 ? EndothelialMotion.travel(t, delay: i) : 1",
  "step < 2 ? 0 : step == 2 ? EndothelialMotion.travel(t) : 1","step == 2 ? EndothelialMotion.travel(t, delay: 1) : down",
  "step < 3 ? 0 : step == 3 ? EndothelialMotion.travel(t) : 1","active: step == 3"])assert(all.includes(token),token);
for(const color of ["EFF5E8","DEEADE","FFEAE2","F7C8C0","F6CEBB","DF9DA8","E0F3EA","AED5C9","86BED7","F1C17D","BC92CD","D8B6DD"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(endothelium_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-endothelial-exchange-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "ENDOTHELIAL_EXCHANGE": GalaxySSIHealthAtlasEndothelialView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["EndothelialMotion","EndothelialView","EndothelialDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 endothelial source audit: five outlines, three lymph routes, separate water filtration/opposing solute diffusion/protein retention/lymph collection, gradients and bounded bilingual legend. No native compilation/pixels verified.");
