// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGanglionRelayStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasGanglionGeometry.swift","GalaxySSIHealthAtlasGanglionRoutes.swift","GalaxySSIHealthAtlasGanglionLabelsDrawing.swift","GalaxySSIHealthAtlasGanglionMotion.swift","GalaxySSIHealthAtlasGanglionDrawing.swift","GalaxySSIHealthAtlasGanglionSensoryDrawing.swift","GalaxySSIHealthAtlasGanglionAutonomicDrawing.swift","GalaxySSIHealthAtlasGanglionSatelliteDrawing.swift","GalaxySSIHealthAtlasGanglionView.swift"];
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


const geometry=local("GalaxySSIHealthAtlasGanglionGeometry.swift"),routes=local("GalaxySSIHealthAtlasGanglionRoutes.swift"),motion=local("GalaxySSIHealthAtlasGanglionMotion.swift");
const shapes=[...source.matchAll(/private val (\w+) = shape \{([^}]+)\}/g)];
assert.equal(shapes.length,15);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
for(const[name,shape]of[["sensoryTrack","sensoryAxon"],["inputTrack","input"],["outputTrack","output"]]){
 const native=routes.match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
 const start=native.match(/start:\s*\.init\(x:\s*([^,]+),\s*y:\s*([^)]+)\)/);
 const cs=[["moveTo",norm(start[1]),norm(start[2])],...[...native.matchAll(/kind:\s*\.(line|quad|cubic),\s*points:\s*\[([^\n]+)\]/g)].map(m=>[
 {line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]:\s*([^,)]+)/g)].map(v=>norm(v[1]))])];
 assert.deepEqual(cs,fromCommands(shapes.find(m=>m[1]===shape)[2]),name);
}
const labels=local("GalaxySSIHealthAtlasGanglionLabelsDrawing.swift");
const original=calls(source,/\b(callout)\(c, /g).filter(c=>c.args[0].startsWith("string."));
const native=calls(labels,/\b(ganglionCallout)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(original.length,15);
assert.deepEqual(native.map(c=>c.args.map(norm)),original.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("string.health_atlas_","")+'"':v))));
for(const[,key]of source.matchAll(/string.health_atlas_(\w+)/g))
 for(const lang of["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
for(const[swift,kotlin]of[
 ["window(t,0.05,0.94)","window(t, .05f, .94f)"],["window(t,0.05,0.43)","window(t, .05f, .43f)"],
 ["window(t,0.59,0.95)","window(t, .59f, .95f)"],["1-abs(safe(t)-0.51)/0.08","1f - abs(HealthAtlasFunctionStory.safePhase(t) - .51f) / .08f"],
 ["1-abs(2*safe(t)-1)","1f - abs(2f * HealthAtlasFunctionStory.safePhase(t) - 1f)"],["f*f*(3-2*f)","f * f * (3f - 2f * f)"],
 ["215-32*GalaxySSIHealthAtlasGanglionMotion.satellite(t)","215 - 32 * motion.satellite(t)"],
 ["width+3.1","width + 3.1f"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of[
 "if f > 0 && f < 1","if incoming > 0 && incoming < 1","if outgoing > 0 && outgoing < 1","if contact > 0",
 "disc(158,159,1.55*contact,0x96602C)","disc(161,164,1.45*contact,0x96602C)",
 "let contrast = UInt32(Int(215-32*GalaxySSIHealthAtlasGanglionMotion.satellite(t)))","let space: UInt32 = 0xFFFFE700 | contrast",
 "case 0: art.ganglionSensory(t)","case 1: art.ganglionAutonomic(t)","case 2: art.ganglionSatellite(t)",
 "y+(ty > y ? 5 : -14)","disc(tx,ty,1.65,0x617473,border:Self.cream)",
 'accessibilityIdentifier("atlas-function-ganglion-relay-art")'
])assert(all.includes(token),token);
for(const[name,nativeName]of[["quietSoma","ganglionQuietSoma"],["nucleus","ganglionNucleus"]]){
 const expected=calls(source,new RegExp("\\b("+name+")\\(c, ","g")).map(c=>c.args.map(norm));
 const actual=calls(all,new RegExp("\\b("+nativeName+")\\(","g")).filter(c=>/^\d/.test(c.args[0])).map(c=>c.args.map(norm));
 assert.deepEqual(actual,expected,name);
}
const gradients={
 capsuleFill:[90,257,"0xFCF4E7","0xE8CFB6"],cordFill:[116,229,"0xF6DFCD","0xD5AAAD"],
 somaFill:[91,214,"0xFFECD6","0xDFA295"],postFill:[126,226,"0xF4D5C9","0xCD929A"],
 gliaFill:[94,245,"0xD7EADD","0x91BEB0"],localSomaFill:[111,228,"0xFFEDDA","0xE2AC9D"]
};
const ink={nerveEdge:"0x996A64",softNerve:"0xC49A83",gliaEdge:"0x4F8178",preInk:"0x96602C",postInk:"0x91566D",sensoryInk:"0x326C78"};
for(const[name,values]of Object.entries(gradients)){
 const expected=source.match(new RegExp("private val "+name+" = shade\\(([^)]+)\\)"))[1].split(",").map(s=>norm(s).toUpperCase().replace("0XFF","0X"));
 assert.deepEqual(values.map(v=>String(v).toUpperCase()),expected,name);
}
const fromTissues=calls(source,/\b(tissue)\(c, /g).map(c=>[c.args[0],...gradients[c.args[1]].map(String),ink[c.args[2]]].map(norm));
const toTissues=calls(all,/\b(ganglionTissue)\(/g).filter(c=>c.args[0].startsWith("g.")).map(c=>c.args.map(s=>norm(s.replace(/^g\./,""))));
assert.deepEqual(toTissues,fromTissues,"source gradient fills and borders");
const fromFibers=calls(source,/\b(fiber)\(c, /g).map(c=>[c.args[0],ink[c.args[1]],c.args[2]].map(norm));
const toFibers=calls(all,/\b(ganglionFiber)\(/g).filter(c=>c.args[0].startsWith("g.")).map(c=>c.args.map(s=>norm(s.replace(/^g\./,""))));
assert.deepEqual(toFibers,fromFibers,"sensory/autonomic fiber identity and widths");
const window=(t,a,b)=>{const f=Math.max(0,Math.min(1,(t-a)/(b-a)));return f*f*(3-2*f);},contact=t=>Math.min(1,Math.max(0,1-Math.abs(t-.51)/.08));
for(const[a,b]of[[.05,.94],[.05,.43],[.59,.95]]){
 assert.equal(window(a,a,b),0);assert.equal(window(b,a,b),1);assert(Math.abs(window((a+b)/2,a,b)-.5)<1e-12);
}
assert.equal(contact(.51),1);assert(contact(.43)<1e-12);assert(contact(.59)<1e-12);
for(const t of[0,.25,.5,.75,1]){
 const s=1-Math.abs(2*t-1),color=(0xFFFFE700|Math.trunc(215-32*s))>>>0;
 assert.equal(color>>>24,255);assert.equal((color>>>8)&255,231);assert.equal(color&255,t===.5?183:t===.25||t===.75?199:215);
}
const assignment=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGanglionRelayAssignment.kt"],{cwd:root,encoding:"utf8"});
for(const[name,index]of[["SENSORY",0],["AUTONOMIC",1],["SATELLITE",2]])assert(assignment.includes("const val "+name+" = "+index));
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="GANGLION_RELAY");
assert.equal(story.durationMs,15000);assert.deepEqual(story.owners,["ganglia","cell-satellite-glial-cell"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["sensory","autonomic","satellite"]);assert.equal(story.references.length,6);
// Preserve Kotlin's serialized Float phase, not a recomputed JavaScript Double.
assert.equal(data.entryPhases["cell-satellite-glial-cell"].GANGLION_RELAY,0.6666667);
assert.deepEqual(story.related,[{entryID:"autonomic-nerves",storyID:"AUTONOMIC_RELAY"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "GANGLION_RELAY": GalaxySSIHealthAtlasGanglionView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 ganglion relay: 15 exact paths/3 ordered signal tracks, sensory bypass/autonomic handoff timing, satellite contrast/entry phase, original tissues/fibers and 15 bilingual anchors checked; no native compilation/pixels verified.");
