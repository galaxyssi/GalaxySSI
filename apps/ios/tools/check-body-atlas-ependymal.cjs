// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasEpendymalStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasEpendymalGeometry.swift","GalaxySSIHealthAtlasEpendymalRoutes.swift","GalaxySSIHealthAtlasEpendymalMotion.swift","GalaxySSIHealthAtlasEpendymalTissueDrawing.swift","GalaxySSIHealthAtlasEpendymalWallDrawing.swift","GalaxySSIHealthAtlasEpendymalCiliaDrawing.swift","GalaxySSIHealthAtlasEpendymalFlowDrawing.swift","GalaxySSIHealthAtlasEpendymalLabelsDrawing.swift","GalaxySSIHealthAtlasEpendymalView.swift"];
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


const geometry=local("GalaxySSIHealthAtlasEpendymalGeometry.swift"),routes=local("GalaxySSIHealthAtlasEpendymalRoutes.swift");
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)].filter(m=>m[1]!=="field");
assert.equal(shapes.length,6);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
for(const[name,shape]of[["singleRoute","channel"],["leftRoute","leftChannel"],["rightRoute","rightChannel"]]){
 const native=routes.match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
 const start=native.match(/start: \.init\(x: ([^,]+), y: ([^)]+)\)/);
 const cs=[["moveTo",norm(start[1]),norm(start[2])],...[...native.matchAll(/kind: \.(line|quad|cubic), points: \[([^\n]+)\]/g)].map(m=>[
 {line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]: ([^,)]+)/g)].map(v=>norm(v[1]))])];
 assert.deepEqual(cs,fromCommands(shapes.find(m=>m[1]===shape)[2]),name);
}
const sourceBlock=n=>source.match(new RegExp("private fun "+n+"\\([\\s\\S]*?\\) \\{([\\s\\S]*?)\\n    \\}"))[1];
for(const[name,file]of[["tissue","TissueDrawing"],["wallCell","WallDrawing"],["tuft","CiliaDrawing"]]){
 assert.deepEqual(toCommands(local("GalaxySSIHealthAtlasEpendymal"+file+".swift")),fromCommands(sourceBlock(name)),name+" dynamic outline(s)");
}
for(const [swift,kotlin] of [
 ["top+0.00063*offset*offset-0.026*offset","top + .00063f * offset * offset - .026f * offset"],
 ["2*t-Double(index)*0.19","2f * t - i * .19f"],
 ["1.55*t-Double(index)*0.18","1.55f * t - i * .18f"],
 ["2*t-Double(index)*0.29","2f * t - i * .29f"],
 ["3*t-Double(index)*0.23","3f * t - i * .23f"],
 ["phase-Double(i)*0.046","phase - i * .046f"],
 ["length-2*Double(abs(i))","length - 2f * kotlin.math.abs(i)"],
 ["base+direction*span*(0.20+0.53*sweep)","base + direction * span * (.20f + .53f * sweep)"],
 ["y-span*(1-0.38*recover)","y - span * (1f - .38f * recover)"],
 ["center+Double(index % 3-1)*2","center + (index % 3 - 1) * 2f"],
 ["middleY+depth*0.64","middleY + depth * .64f"],
 ["min(f*8, (1-f)*8, 1)","minOf(f * 8f, (1f - f) * 8f, 1f)"],
 ["(2.1+Double(i % 2)*0.7)*size","(2.1f + i % 2 * .7f) * size"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of [
 "return index == 2 ? 52 : 39","return step == 2 ? 41 : 31","for i in -1...count","for i in -2...2",
 "direction = step == 4 && i < 3 ? -1.0 : 1.0","close && i == 2","depth = close ? 94.0 : 62","top = close ? 193.0 : 202",
 "count = close ? 5 : 7","left = close ? 24.0 : 19","width = (360-2*left)/Double(count)",
 "recover = (1-cos(beat*2 * .pi))*0.5","sweep = wave(beat)","focused ? 2.55 : 1.85",
 "focused ? 187 : 191","focused ? 292 : 277","focused ? 0xDBF3EB : 0xE6EEF8","focused ? 0x8AC6C2 : 0xADB9D4",
 "c.rotate(by: .degrees(Double(index % 3-1)*13))","0x60928EAF, 4.7","0x93F2F1F8, 1.4",
 "CGRect(x: 1, y: 1, width: 358, height: 358)","local.clip(to: field)","c.clip(to: p)",
 "(Double(i)/Double(beads)+speed*t).truncatingRemainder(dividingBy: 1)",
 "ependymalStream(r.singleRoute, t, 1.4, 6)","ependymalStream(r.leftRoute, t, 1.25, 4)","ependymalStream(r.rightRoute, t+0.23, 1.25, 4)",
 "at(track.route, 0.77)","at(track.route, 0.85)","0x4477B9D1, 13","0xA0EEFBFF, 2",
 "c.translateBy(x: 74, y: 83); c.scaleBy(x: -1, y: 1); c.translateBy(x: -74, y: -83)",
 "ty > y ? 6 : -15","0xEDF6FB, 0xC0E0EC",'accessibilityIdentifier("atlas-function-ependymal-flow-art")'
])assert(all.includes(token),token);
const labels=local("GalaxySSIHealthAtlasEpendymalLabelsDrawing.swift");
const original=calls(source,/\b(callout)\(c, /g).filter(c=>c.args[0].includes("R.string"));
const native=calls(labels,/\b(ependymalCallout)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(original.length,6);
assert.deepEqual(native.map(c=>c.args.map(norm)),original.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v))));
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g)){
 assert(all.includes('"'+key+'"'),key);
 for(const lang of ["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),lang+":"+key);
}
const view=local("GalaxySSIHealthAtlasEpendymalView.swift");
assert(view.indexOf("local.clip(to: field)")<view.indexOf("art.gradient"));
assert(view.indexOf("art.ependymalTissue")<view.indexOf("art.ependymalWallCell"));
assert(view.indexOf("art.ependymalWallCell")<view.indexOf("art.ependymalTuft"));
assert(view.indexOf("art.ependymalTuft")<view.indexOf("art.ependymalLabels"));
const rim=(x,top)=>{const d=x-180;return top+.00063*d*d-.026*d;};
assert.equal(rim(180,202),202);assert(Math.abs(rim(0,202)-227.092)<1e-10);assert(Math.abs(rim(360,202)-217.732)<1e-10);
for(const beads of[4,6])for(const speed of[1.25,1.4])for(const t of[0,.23,.5,1,1.23])for(let i=0;i<beads;i++){
 const f=(i/beads+speed*t)%1,size=Math.min(f*8,(1-f)*8,1);assert(f>=0&&f<1&&size>=0&&size<=1);
}
for(const count of[5,7])assert.equal((count+2)*5,count===5?35:45);
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="EPENDYMAL_FLOW");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["cell-ependymal-cell"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["line","beat","wave","drift","routes"]);assert.equal(story.references.length,4);
assert.deepEqual(story.related,[{entryID:"brain",storyID:"SYNAPTIC_SIGNAL"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "EPENDYMAL_FLOW": GalaxySSIHealthAtlasEpendymalView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 ependymal: 6 fixed paths/3 ordered directional tracks, exact tissue/wall/ciliary templates, fixed bases/beat phase and recovery, clipped lining and wrapped endpoint-tapered streams, bilingual anchors checked; no native compilation/pixels verified.");
