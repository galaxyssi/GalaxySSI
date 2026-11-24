// Pinned source/geometry checks only; not native compilation or physiological validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasSplenicFilterStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Shapes","View","AnatomyDrawing","CellDrawing","DynamicsDrawing"].map(n=>"GalaxySSIHealthAtlasSplenic"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),motion=files[0],shapes=files[1];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replaceAll("extension","reach").replaceAll("SLIT_Y","210").replaceAll("slitY","210").replace(/\s/g,"");
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
const spleenSource=source.match(/private val spleen = Path\(\).apply \{([^}]+)\}/)[1];
const spleenNative=shapes.match(/static let spleen = Path \{ p in([\s\S]*?)\n  \}/)[1];
assert.deepEqual(toCommands(spleenNative),fromCommands(spleenSource),"spleen outline");
const macrophageSource=source.match(/cellMembrane.apply \{([^}]+)\}/)[1];
const macrophageNative=shapes.match(/static func macrophage[\s\S]*?Path \{ p in([\s\S]*?)\n    \}/)[1];
assert.deepEqual(toCommands(macrophageNative),fromCommands(macrophageSource),"deforming macrophage");
for(const name of ["approach","sinusRun","reuseRun"]){
  const from=source.match(new RegExp("private val "+name+" = track\\(Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const start=motion.indexOf("static let "+name+" = Route"),end=motion.indexOf("\n  static let ",start+1);
  const block=motion.slice(start,end<0?motion.length:end);
  const nativeStart=block.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
  const actual=[["moveTo",norm(nativeStart[1]),norm(nativeStart[2])],...[...block.matchAll(/cubic\(\[([^\]]+)\]\)/g)].map(m=>["cubicTo",...m[1].split(",").map(norm)])];
  assert.deepEqual(actual,fromCommands(from),name);
}
assert.deepEqual(motion.match(/wallSegments = \[([^\]]+)\]/)[1].split(",").map(Number),source.match(/wallSegments = floatArrayOf\(([^)]+)\)/)[1].split(",").map(s=>Number(s.trim().replace(/f$/,""))));
for(const [swift,kotlin] of [
  ["wallLeft = 198.0, wallRight = 216.0, slitY = 210.0, retainedX = 176.0","const val WALL_LEFT = 198f"],
  ["ease(1 - abs(x - 207) / 41)","ease(1f - abs(x - 207f) / 41f)"],
  ["mix(22, 33, pinch(x))","mix(22f, 33f, pinch)"],
  ["(0..<64).map","for (i in 0 until 64)"],
  ["2 * Double.pi * Double(i) / 64","2f * PI.toFloat() * i / 64f"],
  ["mix(5, 13, ease(fromWall / 13))","mix(5f, 13f, ease(fromWall / 13f))"],
  ["mix(1.9, 5.5, ease(max(wallLeft - x, max(x - wallRight, 0)) / 13))","mix(1.9f, 5.5f, ease(maxOf(WALL_LEFT - x, x - WALL_RIGHT, 0f) / 13f))"],
  ["ease(t / 0.48) * (1 - ease((t - 0.56) / 0.44))","ease(t / .48f) * (1f - ease((t - .56f) / .44f))"],
  ["y: mix(slitY, 259, ease(t / 0.82))","mix(SLIT_Y, 259f, ease(t / .82f))"],
  ["scale: mix(0.96, 0.85, f), angle: -18 * f","mix(.96f, .85f, f), -18f * f"],
  ["sweep: 360 * ease((t - 0.43) / 0.57)","360f * ease((t - .43f) / .57f)"],
  ["t - 0.14 - 0.08 * Double(index)","t - .14f - .08f * i"],
  ["ease(time / 0.67) * (1 - 0.10 * Double(index))","f * (1f - .10f * i)"],
  ["ease(time / 0.16)","ease((t - .14f - .08f * i) / .16f)"],
  ["0.32 + 0.51 * t",".32f + .51f * t"],
  ["SplenicFlow.mix(128,307,SplenicFlow.ease(t))","mix(128f, 307f, ease(t))"],
  ["SplenicFlow.ease(t / 0.67)","ease(t / .67f)"],
  ["SplenicFlow.ease(t / 0.30)","ease(t / .30f)"],
  ["CGRect(x: 24, y: 141, width: 312, height: 170), cornerRadius: 17","RectF(24f, 141f, 336f, 311f)"],
  ["local.rotate(by: .degrees(-90))","c.rotate(-90f)"],
  ["CGRect(x: top - bottom, y: 0, width: bottom - top, height: SplenicWall.wallRight - SplenicWall.wallLeft), cornerRadius: 5","c.drawRoundRect(top - bottom, 0f, 0f, WALL_RIGHT - WALL_LEFT, 5f, 5f, paint)"],
  ["start: 185,sweep: 97","185f, 97f, false, paint"],
  ["start: 196,sweep: 119","196f, 119f, false, paint"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["A35669","80475E","67988E","EAC3B5","627A77","97632D","F2A9A7","BD7188","FFF1E7","F6D9D0","F0FAF4","CFE9E2","B9DBCF","8EBBB0","EDDFB7","D9B680","FFB0AB","D56C79","E8A8B5","AD627D","C77784","F1A8AA","D48E94","F5E5BD"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(splenic_filter_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const token of ["field.clip(to: GalaxySSIHealthAtlasSplenicShapes.field)","if step != 1","lessFlexible: true","outline.closeSubpath()","if t > 0.43","if breakdown < 1","if reuse.size > 0","if abs(sweep) >= 360"])assert(all.includes(token),token);
assert(all.includes("atlas-function-splenic-filter-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "SPLENIC_FILTER": GalaxySSIHealthAtlasSplenicView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 splenic source audit: spleen/macrophage outlines, three routes, 64-point slit deformation, retention/capture/recycling formulas, clipped tissue and bilingual labels. No native compilation/pixels verified.");
