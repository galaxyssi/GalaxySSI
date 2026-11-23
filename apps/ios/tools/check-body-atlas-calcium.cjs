// Pinned geometry/source wiring only; no native compilation or endocrine-model acceptance.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCalciumFeedbackStoryView.kt"],{cwd:root,encoding:"utf8"});
const motion=local("GalaxySSIHealthAtlasCalciumMotion.swift"),view=local("GalaxySSIHealthAtlasCalciumView.swift"),particle=local("GalaxySSIHealthAtlasCalciumParticleDrawing.swift"),neck=local("GalaxySSIHealthAtlasCalciumParathyroidDrawing.swift"),response=local("GalaxySSIHealthAtlasCalciumResponseDrawing.swift"),all=motion+view+particle+neck+response;
for(const name of ["neckBlood","release","tubule","renalBlood","retention","activeVitaminD","villus","villusBlood","uptake","intestinalSignal"]){
  const block=source.match(new RegExp("private val "+name+" = (?:track\\()?Path\\(\\).apply \\{([^}]+)\\}"));assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const c=JSON.parse("["+motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"))[1]+"]");
  assert.deepEqual([[c[0],c[1]],...c.slice(2)],expected,name);
}
for(const name of ["thyroidLobe","chiefCell","kidney","renalCortex"]){
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
  ["calcium = 1 - 0.66 * ease; hormone = 0","1f - .66f * ease, 0f"],
  ["calcium = 0.34; hormone = 0.24 + 0.76 * ease",".34f, .24f + .76f * ease"],
  ["calcium = 0.34 + 0.66 * ease; hormone = 1 - 0.8 * ease",".34f + .66f * ease, 1f - .8f * ease"],
  ["safe(strength) * Double(count) - Double(index)","strength * count - i"],
  ["min(1, min(8 * f, 8 * (1 - f)))","minOf(1f, 8f * f, 8f * (1f - f))"],
  ["wrap(safe(t) + Double(index) / Double(count))","wrap(t + i.toFloat() / count)"],
  ["CalciumNeckMotion.wrap(0.62 * t + Double(i) / 7)","wrap(.62f * t + i / 7f)"],
  ["153 + 8 * wave(f + Double(i) * 0.3)","153f + 8f * wave(f + i * .3f)"],
  ["local.scaleBy(x: -side, y: 1)","c.scale(-side.toFloat(), 1f, 88f, 0f)"],
  ["Int(255 * calcium)","opacity(teal, calcium)"],
  ["CGPoint(x: 330, y: 266)","lineTo(330f, 266f)"],["CGPoint(x: 30, y: 291)","lineTo(30f, 291f)"],
  ["position: Double($0) / 41","i / 41f"],
  ["width - 2.8","width - 2.8f"],["x - 2.4, y + 1.4, 3.5","x - 2.4f, y + 1.4f, 3.5f"],["x + 2.8, y - 1.5, 2.8","x + 2.8f, y - 1.5f, 2.8f"]
]){assert(all.includes(native),native);assert(source.includes(android),android);}
for(const token of ["case 2: art.calciumRenalResponse(t)","case 3: art.calciumIntestinalResponse(t)","case .pth:","case .vitaminD:","case .calcium:",
  "local.opacity *= Double(min(255, max(0, alpha))) / 255", "local.rotate(by: .degrees(45))", "CGRect(x: -4, y: -4, width: 8, height: 8)",
  "cargo: .pth, count: 5, strength: hormone", "cargo: .calcium, count: 4", "cargo: .calcium, count: 5", "cargo: .vitaminD, count: 3", "if hormone > 0",
  "(1...40).compactMap", "stroke(tubule, CalciumResponseShapes.gold, 29)","stroke(tubule, 0xF8DFB2, 26)", "stroke(tubule, 0xFFF2D4, 15)"])assert(all.includes(token),token);
for(const color of ["915D6A","F3C5C9","64727A","9B661F","F1C67D","F7C6B9","D68D96","FFE7D3","EAB4B3","F7C6BE","D9949D","FFEBD4","EFB6AE","E9D4EB","D6E7DD","F3BCB2","BA7D8F"]){
  assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
for(const key of new Set([...source.matchAll(/string\.health_atlas_(calcium_feedback_story_art_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(view.includes("atlas-function-parathyroid-feedback-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "PARATHYROID_FEEDBACK": GalaxySSIHealthAtlasCalciumView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["CalciumMotion","CalciumView","CalciumParticleDrawing","CalciumParathyroidDrawing","CalciumResponseDrawing"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 calcium source audit: ten exact tracks/four outlines, calcium/PTH feedback strength, distinct calcium/PTH/vitamin-D markers, renal retention/activation, intestinal uptake and bilingual labels. No native compilation/pixels verified.");
