// Pinned geometry/source wiring only; no native compilation or coordination-model acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCerebellumStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasCerebellumMotion.swift"),view=local("GalaxySSIHealthAtlasCerebellumView.swift"),anatomy=local("GalaxySSIHealthAtlasCerebellumAnatomyDrawing.swift"),reach=local("GalaxySSIHealthAtlasCerebellumReachDrawing.swift"),all=motion+view+anatomy+reach;
for(const name of ["cerebrum","gyri","brainstem","cerebellum","whiteMatter","sleeve","forearm"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=view.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  const expected=[...from.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
  const actual=[...to.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
    if(m[3])return ["close"];
    const n=[...m[2].matchAll(/[xy]: (-?[\d.]+)/g)].map(v=>Number(v[1]));
    return m[1]==="addCurve"||m[1]==="addQuadCurve"?[m[1]==="addCurve"?"cubicTo":"quadTo",...n.slice(2),...n.slice(0,2)]:[m[1]==="move"?"moveTo":"lineTo",...n];
  });assert.deepEqual(actual,expected,name);
}
for(const [native,android] of [
  ["0.36 * smooth(t)",".36f * smooth(t)"],["0.36 + 0.18 * smooth(t)",".36f + .18f * smooth(t)"],["0.54 + 0.46 * smooth(t)",".54f + .46f * smooth(t)"],
  ["1 - smooth(t / 0.18)","1f - smooth(t / .18f)"],["smooth((t - 0.18) / 0.30)","smooth((t - .18f) / .30f)"],
  ["1 - smooth((t - 0.48) / 0.18)","1f - smooth((t - .48f) / .18f)"],["smooth((t - 0.66) / 0.34)","smooth((t - .66f) / .34f)"],
  ["t < 0.18 ? 1 : t < 0.66 ? 0.67 : 0.32","t < .66f -> .67f"],
  ["212 + (318 - 212) * p","START_X + (TARGET_X - START_X) * progress"],
  ["187 + (162 - 187) * p - 24 * arc + 22 * d * arc * arc","START_Y + (TARGET_Y - START_Y) * progress - 24f * arc + 22f * deviation * arc * arc"],
  ["(distance * distance + 81 * 81 - 98 * 98) / (2 * distance)","(distance * distance + upper * upper - lower * lower) / (2f * distance)"],
  ["sqrt(max(0, 81 * 81 - along * along))","sqrt((upper * upper - along * along).coerceAtLeast(0f))"],
  ["164 + (along * dx - bend * dy) / distance","shoulderX + (along * dx - bend * dy) / distance"],
  ["243 + (along * dy + bend * dx) / distance","shoulderY + (along * dy + bend * dx) / distance"],
  ["(t - delay) / (1 - delay)","(time - delay) / (1f - delay)"],
  ["progress * Double(i) / 32","progress * i / 32f"],["dash: dashed ? [5, 4] : []","floatArrayOf(5f, 4f)"],
  ["(t >= 0.18 && t < 0.48) || t >= 0.66","(t >= .18f && t < .48f) || t >= .66f"],
  ["progress < 0.85","progress < .85f"]
]){assert(all.includes(native),native);assert(source.includes(android),android);}
for(const token of ["local.clip(to: CerebellumAnatomy.cerebellum)","for i in 0...5","for i in 1...32", "case 0:","case 4:",
  "deviation: step == 4 ? 1 : 0", "if (1...3).contains(step) || laterReach", "if step != 0", "if step == 1", "if step == 2",
  "delay: 0.18", "delay: 0.29", "upper.translateBy(x: 164, y: 243)","lower.translateBy(x: finger.x, y: finger.y)",
  "dashed ? 1.7 : 2.4", "lower.rotate(by: .degrees(arm.lowerAngle))"])assert(all.includes(token),token);
for(const color of ["657984","4B7095","8B657E","A76B83","FCE7D9","E6B5B9","EFD0DC","CE92AB","E5E1C8","C7AA93","FFE1C6","E4AC98","C8E4DB","85B3AB","F7EEEB","CDDCD8"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(cerebellum_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-cerebellar-coordination-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "CEREBELLAR_COORDINATION": GalaxySSIHealthAtlasCerebellumView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["CerebellumMotion","CerebellumView","CerebellumAnatomyDrawing","CerebellumReachDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 cerebellum source audit: seven exact outlines, source repeat/deviation timing, fixed-length two-link arm, predicted/actual traces, error comparison and delayed feedback with bilingual labels. No native compilation/pixels verified.");
