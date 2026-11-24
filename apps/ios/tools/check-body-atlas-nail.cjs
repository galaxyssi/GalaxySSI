// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasNailStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","View","SectionDrawing","PlateDrawing","CellDrawing","LabelsDrawing"].map(n=>"GalaxySSIHealthAtlasNail"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n");
const constants={CURVE:"curve",ROOT_X:"rootX",MATRIX_END:"matrixEnd",BED_END:"bedEnd",THICKNESS:"thickness"};
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/Motion\./g,"").replaceAll("plateY","y").replace(/CURVE|ROOT_X|MATRIX_END|BED_END|THICKNESS/g,s=>constants[s]).replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
function split(text){
  const result=[];let depth=0,start=0;
  for(let i=0;i<text.length;i++){
    if(text[i]==="(")depth++;
    if(text[i]===")")depth--;
    if(text[i]===","&&depth===0){result.push(text.slice(start,i).trim());start=i+1;}
  }
  if(text.slice(start).trim())result.push(text.slice(start).trim());
  return result;
}
function calls(block,regex){
  const result=[];let m;
  while((m=regex.exec(block))){
    const start=regex.lastIndex;let end=start,depth=1;
    for(;end<block.length&&depth;end++){if(block[end]==="(")depth++;if(block[end]===")")depth--;}
    assert.equal(depth,0,"balanced "+m[1]);
    result.push({name:m[1],args:split(block.slice(start,end-1))});
    regex.lastIndex=end;
  }
  return result;
}
const fromCommands=block=>calls(block,/\b(moveTo|lineTo|quadTo|cubicTo|close|plateArc)\(/g).map(c=>
  c.name==="plateArc"?["arc",...c.args.slice(1).map(norm)]:[c.name,...c.args.map(norm)]);
const point=arg=>{
  const text=arg.slice(arg.indexOf("CGPoint(")+8,-1);
  return split(text).map(s=>norm(s.replace(/^[xy]:\s*/,"")));
};
const toCommands=block=>calls(block,/\b(?:p|path)\.(move|addLine|addQuadCurve|addCurve|closeSubpath)\(|\b(arc)\(/g).map(c=>{
  // The arc alternative has a separate capture group.
  if(!c.name)return ["arc",...c.args.slice(1).map(norm)];
  if(c.name==="closeSubpath")return ["close"];
  const points=c.args.map(point);
  return [{move:"moveTo",addLine:"lineTo",addQuadCurve:"quadTo",addCurve:"cubicTo"}[c.name],...(points.length>1?[...points.slice(1).flat(),...points[0]]:points.flat())];
});
for(const name of ["finger","outerSkin","fold","dorsalSkin","phalanx","matrix"]){
  const from=source.match(new RegExp("private val "+name+" = Path\\(\\).apply \\{([^}]+)\\}"))[1];
  const to=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(to),fromCommands(from),name);
}
const bedSource=source.match(/work.rewind\(\)([\s\S]*?)ink\(if \(emphasizeBed\)/)[1];
const bedNative=files[1].match(/static let bed = Path \{ p in([\s\S]*?)\n  \}/)[1];
assert.deepEqual(toCommands(bedNative),fromCommands(bedSource),"stationary bed");
const plateSource=source.match(/plate.rewind\(\)([\s\S]*?)ink\(cream\)/)[1];
const plateNative=files[1].match(/static func plate[\s\S]*?var p = Path\(\)([\s\S]*?)return p/)[1];
assert.deepEqual(toCommands(plateNative),fromCommands(plateSource),"dynamic plate");
const bandSource=source.match(/private fun band[\s\S]*?work.rewind\(\)([\s\S]*?)stroke\(c, work/)[1];
const bandNative=files[1].match(/static func band[\s\S]*?var p = Path\(\)([\s\S]*?)return p/)[1];
assert.deepEqual(toCommands(bandNative),fromCommands(bandSource),"clipped bands");
const arcSource=source.match(/private fun plateArc[^{]+\{([^}]+)\}/)[1];
const arcNative=files[1].match(/static func arc[^{]+\{([^}]+)\}/)[1];
assert.deepEqual(toCommands(arcNative),fromCommands(arcSource),"shared exact parabola");
for(const [key,native] of Object.entries(constants)){
  const number=Number(source.match(new RegExp("const val "+key+" = ([.\\d]+)f"))[1]);
  const value=Number(files[0].match(new RegExp("\\b"+native+" = ([.\\d]+)"))[1]);assert.equal(value,number,key);
}
const sourceLabels=[...source.matchAll(/callout\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeLabels=[...all.matchAll(/nailCallout\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(sourceLabels.length,5);assert.deepEqual(nativeLabels,sourceLabels,"callout anchors");
for(const [key] of sourceLabels)for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
for(const [swift,kotlin] of [
  ["let d = x - 206","val d = x - 206f"],["154 + curve * d * d","154f + CURVE * d * d"],
  ["(to - from) / 2, middle = from + half","val half = (to - from) / 2f"],
  ["12 * ease(t / 0.9)","12f * ease(t / .9f)"],
  ["12 + 23 * ease((t - 0.09) / 0.85)","12f + 23f * ease((t - .09f) / .85f)"],
  ["f * f * (3 - 2 * f)","f * f * (3f - 2f * f)"],
  ["(t - 0.13 - 0.12 * i) / 0.5","(t - .13f - .12f * i) / .5f"],
  ["x: 108 + i * 12, y: 190 - i * 4, separation: 3.6 * split, radius: 4.5 - 1.2 * split","val separation = 3.6f * split"],
  ["(t - i * 0.09) / 0.8","(t - i * .09f) / .8f"],
  ["(enter - 0.15) / 0.78","(enter - .15f) / .78f"],
  ["110 + 10 * i + 29 * enter","110f + 10f * i + 29f * enter"],
  ["startY = 190 - 3.4 * i","startY = 190f - 3.4f * i"],
  ["startY + (y(x) + 5.5 - startY) * enter","startY + (plateY(x) + 5.5f - startY) * enter"],
  ["rx: 3.5 + 4 * flatten, ry: 4.4 - 3.1 * flatten","val rx = 3.5f + 4f * flatten"],
  ["Int(255 * (1 - flatten))","(255f * (1f - flatten)).toInt()"],
  ["142 + 143 * GalaxySSIHealthAtlasNailMotion.ease(t)","142f + 143f * ease(t)"],
  ["168 + 45 * Double(i) + slide","168f + 45f * i + slide"],
  ["step == 4 && i < 2","step == 4 && i < 2"],
  ["11 * Motion.ease(t)","11f * ease(t)"],
  ["241 - 0.0009 * (x - 81) * (x - 81)","241f - .0009f * (x - 81f) * (x - 81f)"],
  ["265 - 0.0036 * (x - 199) * (x - 199)","265f - .0036f * (x - 199f) * (x - 199f)"],
  ["stride(from: 168.0, through: 265.0, by: 8)","for (x in 168..265 step 8)"],
  ["y + (elbowY < y ? -15 : 5)","y + if (elbowY < y) -15f else 5f"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "Geometry.plate(306 + slide)","art.nailSection(emphasizeBed: step == 4)","if step == 1 { art.nailDivision(t) }",
  "art.nailPlate(plate, tip: 306 + slide)","art.nailFold()","clipped.clip(to: GalaxySSIHealthAtlasNailGeometry.matrix)",
  "for side in [-1.0, 1]","frame.y - frame.radius - dx * 0.26","frame.y + frame.radius - dx * 0.26",
  "Double(frame.alpha) / 255","copy(local).disc(frame.x, frame.y, 1.45",
  "art.nailBand(Motion.bedEnd, tip, Motion.thickness / 2, Motion.thickness + 2",
  "art.nailBand(Motion.rootX, tip, 3, 1.2","art.nailBand(Motion.rootX, tip, 7, 1",
  "art.line(x - 1.6, Motion.y(x) + 2.5, x + 1.6, Motion.y(x) + 8.5",
  "atlas-function-nail-matrix-art"
])assert(all.includes(token),token);
assert.equal((files[4].match(/clipped.clip\(to: plate\)/g)||[]).length,3);
assert(files[2].indexOf("art.nailDivision(t)")<files[2].indexOf("art.nailPlate(plate"));
assert(files[2].indexOf("art.nailFold()")>files[2].indexOf("art.nailLandmarks("));
// Numerical checks exercise the matched source parabola, not Swift/native execution.
const y=x=>154+.0011*(x-206)**2,ease=t=>{const f=Math.min(1,Math.max(0,t));return f*f*(3-2*f);};
const slide=(step,t)=>step===3?12*ease(t/.9):step===4?12+23*ease((t-.09)/.85):0;
assert.equal(slide(3,1),slide(4,0));assert.equal(slide(4,1),35);
for(const [from,to,offset] of [[126,274,10],[161,274,9],[274,161,16],[126,338,0],[338,126,10]]){
  const half=(to-from)/2,middle=from+half,control=y(middle)-.0011*half*half+offset;
  for(let i=0;i<=100;i++){const t=i/100,x=from+(to-from)*t,q=(1-t)**2*(y(from)+offset)+2*(1-t)*t*control+t*t*(y(to)+offset);assert(Math.abs(q-y(x)-offset)<1e-9);}
}
assert(!all.includes("Timer"));assert(!all.includes("Image("));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "NAIL_MATRIX_GROWTH": GalaxySSIHealthAtlasNailView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 nail source audit: six fixed outlines, shared exact parabola/dynamic plate/bed/bands, continuous sliding, clipped matrix division, maturation/nuclear fade, stationary tissue layers and five bilingual callouts. No native compilation/pixels verified.");
