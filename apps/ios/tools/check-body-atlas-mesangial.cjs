// Pinned geometry/progress/resource checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMesangialStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["Motion","Geometry","Routes","View","OverviewDrawing","SectionDrawing","CellDrawing","LabelsDrawing"].map(n=>"GalaxySSIHealthAtlasMesangial"+n+".swift");
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n");
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
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
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)].filter(m=>m[2].includes("moveTo"));
assert.equal(shapes.length,8);
for(const [,name,block] of shapes){
  const native=files[1].match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
  assert.deepEqual(toCommands(native),fromCommands(block),name);
}
const outlineSource=source.match(/private fun Path.sectionOutline\(tension: Float\) \{([\s\S]*?)\n    \}/)[1];
const outlineNative=files[1].match(/static func sectionOutline[\s\S]*?var p = Path\(\)([\s\S]*?)return p/)[1];
assert.deepEqual(toCommands(outlineNative),fromCommands(outlineSource),"hinged free-edge outline");
const routeBlocks=[...files[2].matchAll(/Track\(\.init\(start: ([\s\S]*?)\n    \]\)\)/g)];
const nativeRoutes=routeBlocks.map(m=>{
  const start=m[1].match(/\.init\(x: ([^,]+), y: ([^)]+)\)/);
  const commands=[...m[1].matchAll(/\.init\(kind: \.(quad|cubic), points: \[([^\]]+)\]/g)].map(c=>[c[1]==="quad"?"quadTo":"cubicTo",...[...c[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))]);
  return [["moveTo",...start.slice(1).map(norm)],...commands];
});
const tuft=fromCommands(shapes.find(m=>m[1]==="tuft")[2]);
const wall=fromCommands(source.match(/private val wallTrack = track\(Path\(\).apply \{([^}]+)\}/)[1]);
const curve=s=>{const values=s.split(",").map(norm);assert.equal(values.length,6);return [["moveTo",...values.slice(0,2)],["quadTo",...values.slice(2)]];};
const fibers=[...source.match(/private val fibers = listOf\(([\s\S]*?)\n    \)/)[1].matchAll(/curve\(([^)]+)\)/g)].map(m=>curve(m[1]));
const uptake=curve(source.match(/private val uptakeTrack = track\(curve\(([^)]+)\)/)[1]);
assert.equal(fibers.length,4);assert.equal(nativeRoutes.length,7);assert.deepEqual(nativeRoutes,[tuft,wall,...fibers,uptake],"ordered source tracks");
const labels=[...source.matchAll(/label\(c, R.string.health_atlas_(\w+), ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
const nativeLabels=[...all.matchAll(/label\("([^"]+)", ([^)]+)\)/g)].map(m=>[m[1],...m[2].split(",").map(norm)]);
assert.equal(labels.length,8);assert.deepEqual(nativeLabels,labels,"overview/uptake labels");
const leaders=[...source.matchAll(/leader\(c, ([^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
const nativeLeaders=[...all.matchAll(/mesangialLeader\(([^_][^)]+)\)/g)].map(m=>m[1].split(",").map(norm));
assert.equal(leaders.length,6);assert.deepEqual(nativeLeaders,leaders,"leader anchors");
for(const [key] of labels)for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_'+key+'"'),key);
for(const color of new Set([...source.matchAll(/0xff([0-9a-f]{6})/g)].map(m=>m[1].toUpperCase())))assert(all.includes("0x"+color),color);
assert(files[0].includes("case locate, boundary, support, uptake, tension"));
for(const [swift,kotlin] of [
  ["loopHinge = 137.0","LOOP_HINGE = 137f"],
  ["f * f * (3 - 2 * f)","f * f * (3f - 2f * f)"],
  ["1 - (1 - f) * (1 - f)","1f - (1f - f) * (1f - f)"],
  ["case .support: return f * f","SUPPORT -> f * f"],
  ["case .uptake: return f","UPTAKE -> f"],
  ["smooth(f / 0.7)","smooth(f / .7f)"],["smooth((1 - f) / 0.3)","smooth((1f - f) / .3f)"],
  ["1 - 0.13 * tension","1f - .13f * tension"],
  ["hinge + (value - hinge) * GalaxySSIHealthAtlasMesangialMotion.loopScale(tension)","LOOP_HINGE + (value - LOOP_HINGE) * loopScale(tension)"],
  ["0.4 + 0.6 * min(1, max(0, (f - Double(index) * 0.055) / 0.835))",".4f + .6f * ((f - i * .055f) / .835f).coerceIn(0f, 1f)"],
  ["reach - 0.25, reach, 0xA37435, 3.4","reach - .25f, reach, 0xffa37435, 3.4f"],
  ["0.72 * f, 0.17 + 0.72 * f"," .72f * f, .17f + .72f * f"],
  ["x: 86 - 3 * f, y: 52 - 3 * f, width: 26 + 6 * f, height: 24 + 6 * f","86f - 3f * f, 52f - 3f * f, 112f + 3f * f, 76f + 3f * f"],
  ["f - 0.30, f + 0.05","f - .30f, f + .05f"],
  ["if f > 0.35","if (f > .35f)"],
  ["(f - 0.35) / 0.65","(f - .35f) / .65f"],
  ["Double(Int(light * 255)) / 255","(light * 255).toLong()"],
  ["y: 1 - 0.12 * tension","1f - .12f * tension"],
  ["min(1, max(0, f / 0.72))","(f / .72f).coerceIn(0f, 1f)"],
  ["4 + 1.5 * min(1, max(0, (f - 0.48) / 0.24))","4f + 1.5f * ((f - .48f) / .24f).coerceIn(0f, 1f)"],
  ["1 - 0.52 * min(1, max(0, (f - 0.72) / 0.28))","1f - .52f * ((f - .72f) / .28f).coerceIn(0f, 1f)"],
  ["x - 2 * size, y, 2.2 * size","x - 2f * size, y, 2.2f * size"],
  ["x + 1.8 * size, y + 1.3 * size, 1.9 * size","x + 1.8f * size, y + 1.3f * size, 1.9f * size"],
  ["x + 0.4 * size, y - 2.4 * size, 1.8 * size","x + .4f * size, y - 2.4f * size, 1.8f * size"]
]){assert(all.includes(swift),swift);assert(source.includes(kotlin),kotlin);}
for(const token of [
  "static let relaxedOutline = sectionOutline(0)","let edge = tension == 0 ? Geometry.relaxedOutline : Geometry.sectionOutline(tension)",
  "local.translateBy(x: Motion.loopHinge, y: 208)","local.translateBy(x: -Motion.loopHinge, y: -208)",
  "copy(local).mesangialLumen(Geometry.leftLumen, 69, 184)","mesangialLumen(Geometry.rightLumen, 195, 180)",
  "art.mesangialOverview(stage == .locate ? f : nil)","if let f {","stage.progress(story.fraction(phase))",
  "tension = stage == .tension ? f : 0","mesangialRedCell(x, y, -26)","mesangialRedCell(x + 14, y + 25, 32)","mesangialRedCell(x - 5, y + 49, -9)",
  "local.translateBy(x: 138, y: 227)","local.translateBy(x: -138, y: -227)",
  "at(GalaxySSIHealthAtlasMesangialRoutes.uptake.route, frame.travel)","mesangialDebris(251, 253, 1)",
  "let from = max(0, start), to = min(1, end)","guard to > from else { return }","atlas-function-mesangial-support-art"
])assert(all.includes(token),token);
assert(files[3].indexOf("art.mesangialCell(tension)")>files[3].indexOf("art.mesangialSweep(fiber"));
const catalogue=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"),"utf8"));
const story=catalogue.stories.find(s=>s.id==="MESANGIAL_SUPPORT");
const chapters=[...source.matchAll(/\w+\(R.string.(health_atlas_mesangial_story_\w+), R.string.(health_atlas_mesangial_story_\w+)\)/g)].map(m=>({title:m[1],caption:m[2]}));
assert.equal(chapters.length,5);assert.deepEqual(story.chapters,chapters);
assert.equal(story.durationMs,Number(source.match(/DURATION_MS = ([\d_]+)L/)[1].replaceAll("_","")));
const references=[...source.matchAll(/const val (?:STRUCTURE_SOURCE|UPTAKE_SOURCE) = "([^"]+)"/g)].map(m=>m[1]);
assert.equal(references.length,2);for(const url of references)assert(story.references.some(r=>r.url===url),url);
// Source-matched scalar checks, not Swift/native execution.
const smooth=f=>f*f*(3-2*f),tension=f=>f<.7?smooth(f/.7):smooth((1-f)/.3);
assert.equal(tension(0),0);assert(Math.abs(tension(.7)-1)<1e-12);assert.equal(tension(1),0);
for(let i=0;i<=1000;i++){const t=tension(i/1000);assert(t>=0&&t<=1);const scale=1-.13*t;assert(scale>=.87);assert.equal(137+(137-137)*scale,137);}
assert(!all.includes("Timer"));assert(!all.includes("Image("));assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "MESANGIAL_SUPPORT": GalaxySSIHealthAtlasMesangialView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names)assert.equal(project.split(name+" in Sources").length-1,2,name);
console.log("Android #4384 mesangial source audit: eight exact outlines/hinged free edge, seven ordered tracks, five nonlinear progress rules, paired lumen/cell transforms, finite fiber/boundary sweeps, matrix-side vesicle uptake, bilingual anchors and references. No native compilation/pixels verified.");
