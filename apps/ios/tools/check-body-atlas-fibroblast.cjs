// Pinned source geometry/formulas only; not native compilation or tissue-repair validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasFibroblastStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Shapes","View","TissueDrawing","MatrixDrawing"].map(n=>"GalaxySSIHealthAtlasFibroblast"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),motion=files[0],shapes=files[1];
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(v=>Number(v.trim().replace(/f$/,"")))]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([-\d.]+)/g)].map(v=>Number(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
for(const name of ["dermis","side","epidermalBand","epidermalTop","epidermalEdge","surfaceDetail","cell","cellDetail"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=shapes.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
for(const name of ["scaffold","outgoing"]){
  const start=source.indexOf("private val "+name),end=source.indexOf("private val ",start+1),block=source.slice(start,end);
  const expected=[...block.matchAll(/Fiber\(([^)]+)\)/g)].map(m=>m[1].split(",").map(s=>Number(s.trim().replace(/f$/,""))));
  const nativeStart=motion.indexOf("static let "+name),nativeEnd=motion.indexOf("\n  static let ",nativeStart+1),native=motion.slice(nativeStart,nativeEnd);
  const actual=[...native.matchAll(/\.init\(([\d.,]+)\)/g)].map(m=>m[1].split(",").map(Number));
  assert.equal(expected.length,name==="scaffold"?11:8);assert.deepEqual(actual,expected,name);
}
for(const name of ["olderFiber","renewedFiber"]){
  const expected=source.match(new RegExp("private val "+name+" = Fiber\\(([^)]+)\\)"))[1].split(",").map(s=>Number(s.trim().replace(/f$/,"")));
  const actual=motion.match(new RegExp("static let "+name+" = Fiber\\(([^)]+)\\)"))[1].split(",").map(Number);
  assert.deepEqual(actual,expected,name);
}
for(const token of [
  "start = .init(x: x0, y: y0); control1 = .init(x: x1, y: y1); control2 = .init(x: x2, y: y2); end = .init(x: x3, y: y3)",
  "a.x + (b.x - a.x) * fraction","a.y + (b.y - a.y) * fraction",
  "start: mix(start,target.start),control1: mix(control1,target.control1),control2: mix(control2,target.control2),end: mix(end,target.end)",
  ".init(kind: .cubic, points: [control1,control2,end])",
  "path.trimmedPath(from: CGFloat(from),to: CGFloat(to))","guard to > from","local.opacity *=",
  "if step == 0","for index in [1,6]","if step == 1","if step >= 2","if growth == 1","if turnover > 0"
])assert(all.includes(token),token);
for(const [swift,kotlin] of [
  ["eased(t,from: 0.06,to: 0.92)","eased(t, .06f, .92f)"],
  ["eased(t,from: 0.08,to: 0.92)","eased(t, .08f, .92f)"],
  ["0.05 + 0.11 * Double(index),to: 0.54 + 0.13 * Double(index)",".05f + .11f * i, .54f + .13f * i"],
  ["eased(t,from: 0.45,to: 0.75) * (1 - eased(t,from: 0.82,to: 1))","eased(t, .45f, .75f) * (1f - eased(t, .82f, 1f))"],
  ["(t - 0.19 * Double(index)) / 0.78","(t - .19f * i) / .78f"],
  ["4 * pulse * (1 - pulse)","4f * pulse * (1f - pulse)"],
  ["7 + 40 * pulse, Int(185 * alpha)","7f + 40f * pulse"],
  ["Int(125 * focus)","(125f * focus).toInt()"],
  ["let head = t * 1.25","val head = t * 1.25f"],
  ["start: head - 0.25,end: head","head - .25f, head"],
  ["Int(255 * alpha)","(255f * alpha).toInt()"],
  ["width + 2.3","width + 2.3f"],
  ["end: turnover,color: FibroblastMatrixInk.collagen,width: 2.7,alpha: turnover","drawSegment(c, 0f, turnover, collagenInk, 2.7f, turnover)"],
  ["alpha: 1 - turnover","2.7f, 1f - turnover"],
  ["rounded(39,107,326,281,17,0x186B514A)","rounded(c, 39f, 107f, 326f, 281f, 17f, 0x186b514a)"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["AA757E","397F76","547F9E","665969","FFEEE7","ECD0D8","FFECDB","F0BCB0","E0D8F2","AF93C7","DFB4BE","C28A99","D99A92","FFF3E4","634372","F6ECFC","FFF4E9","FFE0A9"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(fibroblast_story_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
assert(all.includes("art.fibroblastPatch(); art.fibroblastMatrix(step: step,t: t); art.fibroblastCell(); art.fibroblastLabels()"));
assert(all.includes("atlas-function-fibroblast-matrix-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "FIBROBLAST_MATRIX": GalaxySSIHealthAtlasFibroblastView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 fibroblast source audit: eight exact outlines, eleven scaffold/four paired outgoing/two turnover fibers, control-point interpolation, repair cues, alpha/trim ordering and bilingual labels. No native compilation/pixels verified.");
