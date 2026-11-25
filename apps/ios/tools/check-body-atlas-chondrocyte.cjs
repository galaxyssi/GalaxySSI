// Pinned source geometry/formulas only; not native compilation or cartilage-function validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasChondrocyteStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","View","MatrixDrawing","MarkersDrawing","SecretionDrawing","LabelsDrawing"].map(n=>"GalaxySSIHealthAtlasChondrocyte"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n"),geometry=files[1];
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
const fromCommands=block=>[...block.matchAll(/(moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)|(close)\(\)/g)].map(m=>m[3]?["close"]:[m[1],...m[2].split(",").map(norm)]);
const toCommands=block=>[...block.matchAll(/p\.(move|addLine|addQuadCurve|addCurve)\(([^;\n]+?)\)(?=\s*(?:;|\n|$))|p\.(closeSubpath)\(\)/g)].map(m=>{
  if(m[3])return ["close"];
  const n=[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]));
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[m[1]],...(n.length>2?[...n.slice(2),...n.slice(0,2)]:n)];
});
for(const name of ["patch","reticulum"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
const profileSource=source.match(/private fun profile[\s\S]*?Path\(\).apply \{([^}]+)\}/)[1];
const profileNative=geometry.match(/static func profile[\s\S]*?Path \{ p in([\s\S]*?)\n    \}/)[1];
assert.deepEqual(toCommands(profileNative),fromCommands(profileSource),"profile contour");
for(const name of ["territory","rim","lacuna","cell"]){
  const from=source.match(new RegExp("private val "+name+" = profile\\(([^)]+)\\)"))[1].split(",").map(norm);
  const to=geometry.match(new RegExp("static let "+name+" = profile\\(([^)]+)\\)"))[1].split(",").map(norm);
  assert.deepEqual(to,from,name);
}
const neighbors=[...source.matchAll(/neighbor\(([\d., f]+)\)/g)].map(m=>m[1].split(",").map(norm));
const nativeNeighbors=[...geometry.matchAll(/Neighbor\(([\d.,]+)\)/g)].map(m=>m[1].split(",").map(norm));
assert.equal(neighbors.length,4);assert.deepEqual(nativeNeighbors,neighbors);
for(const name of ["fibrils","collagenRoutes","collagenJoins","deposits"]){
  const from=source.match(new RegExp("private val "+name+" = listOf\\(([\\s\\S]*?)\\n    \\)"))[1];
  const start=geometry.indexOf("static let "+name),end=geometry.indexOf("\n  static let ",start+1),to=geometry.slice(start,end);
  const expected=[...from.matchAll(/curve\(([^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
  const actual=[...to.matchAll(/curve\(([^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
  assert.equal(expected.length,{fibrils:19,collagenRoutes:2,collagenJoins:2,deposits:3}[name]);
  assert.deepEqual(actual,expected,name);
}
const depositPoses=[...source.matchAll(/Deposit\(([-\d.]+)f, ([-\d.]+)f, ([-\d.]+)f/g)].map(m=>m.slice(1).map(Number));
const nativePoses=[...geometry.matchAll(/\.init\(x: ([-\d.]+), y: ([-\d.]+), angle: ([-\d.]+), route:/g)].map(m=>m.slice(1).map(Number));
assert.deepEqual(nativePoses,depositPoses);
const carrier=s=>s.match(/(?:private val|static let) carrier = curve\(([^)]+)\)/)[1].split(",").map(norm);
assert.deepEqual(carrier(geometry),carrier(source));
assert(geometry.includes("[lacuna,rim,territory,path(fibrils[8])]"));
assert(source.includes("listOf(track(lacuna), track(rim), track(territory), track(fibrils[8]))"));
for(const [swift,kotlin] of [
  ["184 + 4.5 * Double(i)","184f + 4.5f * i"],["195 - Double(i) * 2","195f - i * 2f"],
  ["0.18 + 0.82 * Self.ease(t,from: 0.03,to: 0.95)",".18f + .82f * ease(t, .03f, .95f)"],
  ["Self.ease(t,from: 0,to: 0.36) * (1 - Self.ease(t,from: 0.38,to: 0.96))","ease(t, 0f, .36f) * (1f - ease(t, .38f, .96f))"],
  ["1 - 0.19 * squeeze","1f - .19f * squeeze"],
  ["177 + (y - 177) * scale","MID_Y + (y - MID_Y) * scale"],
  ["0.04 + Double(index) * 0.21,to: 0.57 + Double(index) * 0.19",".04f + i * .21f, .57f + i * .19f"],
  ["0.53 + Double(index) * 0.19,to: 0.83 + Double(index) * 0.17",".53f + i * .19f, .83f + i * .17f"],
  ["Double(index) * 0.16,to: 0.56 + Double(index) * 0.20","index * .16f, .56f + index * .20f"],
  ["(t - 0.13 * Double(index)) / 0.56","(t - .13f * index) / .56f"],
  ["* 1.34","f * 1.34f"],
  ["Int(111 * hydration * (1 - 0.56 * squeeze))","(111f * hydration * (1f - .56f * squeeze)).toInt()"],
  ["Int(215 * Self.ease(t,from: 0,to: 0.15) * (1 - Self.ease(t,from: 0.35,to: 0.65)))","(215f * ease(t, 0f, .15f) * (1f - ease(t, .35f, .65f))).toInt()"],
  ["0.04 + 0.063 * Double(index),to: 0.72 + 0.066 * Double(index)",".04f + .063f * i, .72f + .066f * i"],
  ["step < 4 ? 139 - 40 * advance : 99 + 40 * squeeze","if (step < 4) 139f - 40f * advance else 99f + 40f * squeeze"],
  ["60 + 132 * advance : 192 - 75 * squeeze","60f + 132f * advance else 192f - 75f * squeeze"],
  ["7 + 5 * hydration","7f + 5f * hydration"],
  ["13 + 5 * frame.squeeze","13f + 5f * squeeze"],
  ["angle: -62 + (deposit.angle + 62) * f,scale: 0.55 + 0.45 * f","-62f + (deposit.angle + 62f) * f, .55f + .45f * f"],
  ["head - 0.34","head - .34f"],
  ["Double(sample.direction.dx) * 4.5","tangent[0] * 4.5f"],
  ["x - length * 0.19","x - length * .19f"],["x + length * 0.12","x + length * .12f"],
  ["x + length * 0.28","x + length * .28f"],
  ["let yy = -5 - Double(i) * 4","val yy = -5f - i * 4f"],
  ["width = i == 4 ? 4.0 : 7.0","if (i == 4) 4f else 7f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const color of ["6D9E92","488779","9A627F","A77784","974E69","976733","397F9C","52656A","E5F2E8","BAD9D3","CDE8DE","9FC7BE","AED6C9","81B5AC","FFEEE1","DCACC2","93BDB1","79C8DA","997F58","B3D3C9","8DB1AA","D6B8C9","E7EEE3","739C91","B08BAD","825C85","BD9AB8","8E668D","FAF1EE","BD8DA8","A16B83","286E63","A28864","F9ECD2","ADC4BA"]){
  assert(all.includes("0x"+color),color);assert(source.toLowerCase().includes("0xff"+color.toLowerCase()),color);
}
for(const color of ["1A386E65","B1F9F2E7","EAFFF8E8"]){assert(all.includes("0x"+color));assert(source.toLowerCase().includes("0x"+color.toLowerCase()));}
for(const key of new Set([...source.matchAll(/R\.string\.health_atlas_(chondrocyte_story_label_\w+)/g)].map(m=>m[1]))){
  assert(all.includes('"'+key+'"'),key);
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
}
for(const y of [148,158,108,201,215])assert(all.includes("mappedY("+y+",scale: scaleY)"),"mapped label "+y);
for(const token of ["clipped.clip(to: ChondrocyteMatrix.patch)","tissue.translateBy(x: 180, y: 177); tissue.scaleBy(x: 1, y: frame.scaleY); tissue.translateBy(x: -180, y: -177)",
  "inside.chondrocyteMatrix(frame); inside.chondrocyteCell()","if step > 1 { inside.chondrocyteCollagen(1) }","if step > 2 { inside.chondrocyteAggrecan(1) }",
  "if step == 4 { art.chondrocyteCompression(frame) }","local.opacity *=","ride > 0 && ride < 1","if f == 1","guard to > 0, from < 1, from < to","path.trimmedPath(from: CGFloat(start),to: CGFloat(end))"
])assert(all.includes(token),token);
assert(all.includes("atlas-function-chondrocyte-matrix-art"));assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "CHONDROCYTE_MATRIX": GalaxySSIHealthAtlasChondrocyteView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 chondrocyte source audit: exact patch/reticulum/profile geometry, nineteen fibrils/four collagen/three deposit routes, hydration/compression mapping, particle semantics and bilingual labels. No native compilation/pixels verified.");
