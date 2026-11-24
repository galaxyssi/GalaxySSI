// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasMicrogliaStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasMicrogliaGeometry.swift","GalaxySSIHealthAtlasMicrogliaArbor.swift","GalaxySSIHealthAtlasMicrogliaMotion.swift","GalaxySSIHealthAtlasMicrogliaBackgroundDrawing.swift","GalaxySSIHealthAtlasMicrogliaCellDrawing.swift","GalaxySSIHealthAtlasMicrogliaDigestDrawing.swift","GalaxySSIHealthAtlasMicrogliaLabelsDrawing.swift","GalaxySSIHealthAtlasMicrogliaView.swift"];
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n),"utf8"),files=names.map(local),all=files.join("\n");
const norm=s=>s.replace(/(\d)f\b/g,"$1").replace(/\b[Mm]\./g,"").replace(/Double\(([^()]*)\)/g,"$1").replace(/\s/g,"").replace(/(^|[^\d])\.(\d)/g,"$10.$2");
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


const geometry=local("GalaxySSIHealthAtlasMicrogliaGeometry.swift"),arbor=local("GalaxySSIHealthAtlasMicrogliaArbor.swift");
const shapes=[...source.matchAll(/private val (soma|neuron) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(shapes.length,2);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
const fibers=[...source.match(/private val neuropil = listOf\(([\s\S]*?)\n    \)/)[1].matchAll(/Path\(\).apply \{([^}]+)\}/g)].map(m=>fromCommands(m[1]));
const nativeFibers=[...geometry.slice(geometry.indexOf("static let neuropil")).matchAll(/Path \{ p in([^}]+)\}/g)].map(m=>toCommands(m[1]));
assert.equal(fibers.length,8);assert.deepEqual(nativeFibers,fibers);
const branches=calls(source,/\b(branch)\(c, /g).map(c=>c.args.map(norm));
const nativeBranches=calls(arbor,/\.(init)\(/g).map(c=>c.args.map(norm));
for(const args of [...branches,...nativeBranches])assert.equal(args.length,8,"complete branch coordinates/taper");
assert(!/(^|[\s(,])\.\d/m.test(arbor),"Swift numeric literals need a leading zero");
assert.equal(branches.length,23);assert.deepEqual(nativeBranches,branches,"ordered proximal/distal branch endpoints and taper");
const branch=source.match(/private fun branch\([\s\S]*?\) \{([\s\S]*?)\n    \}/)[1];
const nativeBranch=local("GalaxySSIHealthAtlasMicrogliaCellDrawing.swift").split("private func microgliaBranch")[1];
assert.deepEqual(toCommands(nativeBranch),fromCommands(branch),"normal-offset tapered outline");
const pocket=source.match(/private fun pocket\([^\n]*\) \{([\s\S]*?)\n    \}/)[1];
const nativePocket=local("GalaxySSIHealthAtlasMicrogliaDigestDrawing.swift").split("func microgliaFragments")[0];
assert.deepEqual(toCommands(nativePocket),fromCommands(pocket),"closing pocket contour");
for(const [swift,kotlin] of [
 ["t+0.31","t + .31f"],["1.55*t","1.55f * t"],["cycle+0.31","cycle + .31f"],["cycle+0.62","cycle + .62f"],
 ["ease(t, 0.08, 0.88)","ease(t, .08f, .88f)"],["ease(t, 0.24, 0.77)","ease(t, .24f, .77f)"],
 ["ease(t, 0.15, 0.88)","ease(t, .15f, .88f)"],["f*f*(3-2*f)","f * f * (3f - 2f * f)"],
 ["closure >= 0.98","closure >= .98f"],["x-13+30*closure","x - 13f + 30f * closure"],["11-9*closure","11f - 9f * closure"],
 ["remain > 0.04","remain > .04f"],["remain*1.45","remain * 1.45f"],
 ["i*73 % 328","i * 73 % 328"],["i*57 % 319","i * 57 % 319"],
 ["254+8*Double(i)+1.3*wave(t+Double(i)*0.22)","254f + 8f * i + 1.3f * wave(t + i * .22f)"],
 ["86+(1-remain)*Double(i % 3-1)*11","86f + (1f - remain) * (i % 3 - 1) * 11f"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of [
 "CGRect(x: 1, y: 1, width: 358, height: 358)","for i in 0...45","0x509490B5 : 0x4091B8AE","0x99F8FAFC","0x5796AAB6",
 "step == 1 ? 1.0 : (step == 2 || step == 3) ? 0.28 : 0.58",
 "step == 2 ? GalaxySSIHealthAtlasMicrogliaMotion.ease(t, 0.08, 0.88) : (step == 3 || step == 4) ? 1 : 0",
 "motion*sin(2 * .pi*cycle)","motion*sin(2 * .pi*(cycle+0.31))","motion*sin(2 * .pi*(cycle+0.62))",
 "c.translateBy(x: 286, y: 217); c.rotate(by: .degrees(151))","c.scaleBy(x: 0.48, y: 0.48); c.translateBy(x: -153, y: -172)",
 "clipped.clip(to: field)","clipped.translateBy(x: offsetX, y: offsetY); clipped.scaleBy(x: zoom, y: zoom)",
 "zoom = close ? 1.55 : 1","offsetX = close ? -138.0 : 0","offsetY = close ? -80.0 : 0",
 "c.rotate(by: .degrees(-14))","x+nx*base/2","let nx = -dy/length, ny = dx/length",
 "ty > y ? 5 : -14","offsetX+247*scale, offsetY+151*scale",
 'accessibilityIdentifier("atlas-function-microglia-surveillance-art")'
])assert(all.includes(token),token);
const view=local("GalaxySSIHealthAtlasMicrogliaView.swift");
assert(view.indexOf("clipped.clip(to: field)")<view.indexOf("clipped.translateBy"));
assert(view.indexOf("microgliaBackground")<view.indexOf("microgliaArbor"));
assert(view.indexOf("microgliaArbor")<view.indexOf("microgliaPocket"));
assert(view.indexOf("detail.microgliaPocket")<view.indexOf("art.microgliaLabels"));
const labels=local("GalaxySSIHealthAtlasMicrogliaLabelsDrawing.swift");
const sourceLabels=calls(source,/\b(callout)\(c, /g).filter(c=>c.args[0].includes("R.string"));
assert.equal(sourceLabels.length,6);
const aliases=s=>s.replace("R.string.health_atlas_",'"').replace(/^("\w+)$/,'$1"').replaceAll("arborEdge","0x36786C").replaceAll("nerve","0x8E86AD").replaceAll("debrisInk","0x9B6458");
const nativeLabels=calls(labels,/\b(microgliaCallout)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.deepEqual(nativeLabels.map(c=>c.args.map(norm)),sourceLabels.map(c=>c.args.map(s=>norm(aliases(s)))));
for(const [,key]of source.matchAll(/R.string.health_atlas_(\w+)/g))
 for(const lang of ["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
const ease=(t,a,b)=>{const f=Math.min(1,Math.max(0,(t-a)/(b-a)));return f*f*(3-2*f);};
for(const[a,b]of[[.08,.88],[.24,.77],[.15,.88]]){
 assert.equal(ease(a,a,b),0);assert.equal(ease(b,a,b),1);assert(Math.abs(ease((a+b)/2,a,b)-.5)<1e-12);
}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="MICROGLIA_SURVEILLANCE");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["cell-microglia"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["reside","survey","approach","engulf","digest"]);
assert.equal(story.references.length,3);
assert.deepEqual(story.related,[{entryID:"cell-astrocyte",storyID:"ASTROCYTE_SUPPORT"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "MICROGLIA_SURVEILLANCE": GalaxySSIHealthAtlasMicrogliaView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 microglia: 10 exact fixed paths, 23 ordered tapered branches, scan/reach/engulf/digest windows, clipped zoom/transformed anchors and 6 bilingual callouts checked; no native compilation/pixels verified.");
