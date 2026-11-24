// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasErectorSupportStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasErectorGeometry.swift","GalaxySSIHealthAtlasErectorMotion.swift","GalaxySSIHealthAtlasErectorPosteriorDrawing.swift","GalaxySSIHealthAtlasErectorTrunkDrawing.swift","GalaxySSIHealthAtlasErectorBandDrawing.swift","GalaxySSIHealthAtlasErectorLabelsDrawing.swift","GalaxySSIHealthAtlasErectorView.swift"];
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


const geometry=local("GalaxySSIHealthAtlasErectorGeometry.swift"),motion=local("GalaxySSIHealthAtlasErectorMotion.swift");
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(shapes.length,2);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
const sourceBlock=n=>source.match(new RegExp("private fun "+n+"\\([\\s\\S]*?\\) \\{([\\s\\S]*?)(?=\\n    private fun)"))[1];
const trunk=geometry.match(/static func trunk[\s\S]*?return Path \{ p in([\s\S]*?)\n  \}/)[1];
assert.deepEqual(toCommands(trunk),fromCommands(sourceBlock("drawTrunk")),"deforming trunk");
const trace=geometry.match(/static func trace[\s\S]*?return Path \{ p in([\s\S]*?)\n  \}/)[1];
assert.deepEqual(toCommands(trace),fromCommands(sourceBlock("trace")),"33-point spine/band trace");
const nativeRoute=geometry.match(/extensionRoute = [\s\S]*?start:\.init\(x:([^,]+),y:([^)]+)\)[\s\S]*?points:\[\.init\(x:([^,]+),y:([^)]+)\),\.init\(x:([^,]+),y:([^)]+)\)/);
assert(nativeRoute);
assert.deepEqual([["moveTo",...nativeRoute.slice(1,3).map(norm)],["quadTo",...nativeRoute.slice(3).map(norm)]],fromCommands(sourceBlock("extensionArc")),"extension indicator track");
for(const[swift,kotlin]of[
 ["step == 1 ? 1-ease : 0","if (step == 1) 1f - ease else 0f"],
 ["0.42+0.58*sin(.pi*ease)",".42f + .58f * sin(PI.toFloat() * ease)"],
 ["0.42+0.58*ease",".42f + .58f * ease"],["0.25+0.12*ease",".25f + .12f * ease"],
 ["49*flexion*pow(max(0,(250-y)/185),1.45)","49f * flexion * ((250f - y) / 185f).coerceAtLeast(0f).pow(1.45f)"],
 ["151-13*sin((y-69)*(2 * .pi/198))+shift(y,flexion)","151f - 13f * sin((y - 69f) * (2f * PI.toFloat() / 198f)) + shift(y, flexion)"],
 ["top+(bottom-top)*Double(i)/32","top + (bottom - top) * i / 32f"],
 ["Double(Int(25+155*emphasis))/255","(25f + 155f * emphasis).toInt()"],
 ["Double(Int(70+110*motion.posteriorEmphasis))/255","(70f + 110f * emphasis).toInt()"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of [
 '(1+sin(2 * .pi*(t-0.25)))/2','for i in 1...32','spineX(y,flexion)+offset*(1-0.3*Double(i)/32)',
 'stride(from:76.0,through:244,by:14)','atan2(m.spineX(y+1,flexion)-x,1)*(-180 / .pi)',
 'g.trace(flexion,0,72,252)','g.trace(motion.flexion,-23,77,258)','g.trace(motion.flexion,-16,71,258)',
 'stroke(p,edge,7.3); stroke(p,fill,5)','copy(c).stroke(p,edge,2.8)',
 'CGRect(x:0,y:42,width:360,height:280)','Image("HealthAtlasFunctionErector")',
 'for side in [-1.0,1.0]','CGRect(x:x-8,y:147,width:16,height:37)',
 'at(g.extensionRoute,ease)','arrow(151,44,139,50,Self.blue)',
 'Supported and loaded chapters intentionally retain the same neutral geometry.',
 'if step == 2 { art.erectorSupport() }','if step == 3 { art.erectorLoad() }',
 'art.erectorTrunk(motion.flexion); art.erectorBands(motion)',
 'bendX:242','let edge = ty > y ? y+6 : y-15, bend = bendX ?? x',
 'if bend != x','label(key,x,y,maxWidth)',
 'accessibilityIdentifier("atlas-function-erector-support-art")'
])assert(all.includes(token),token);
const actualKeys=calls(all,/\b(erectorKey)\(/g).filter(c=>c.args[0].startsWith('"'));
const originalKeys=calls(source,/\b(key)\(c, /g).filter(c=>c.args[0].startsWith("R.string"));
assert.equal(actualKeys.length,8);assert.equal(originalKeys.length,8);
const inks={farInk:"0x896D91",nearInk:"0xA3667C",boneEdge:"0x7E9898",coral:"Self.coral",teal:"Self.teal",blue:"Self.blue"};
const canonical=v=>norm(v.replaceAll("motion.flexion","flexion").replaceAll("POSTERIOR_TOP","42").replace("bendX =","bendX:"));
const keys=cs=>cs.map(c=>c.args.map((v,i)=>canonical(i===0?v:(inks[v]||v)))).sort((a,b)=>a[0].localeCompare(b[0]));
const expected=originalKeys.map(c=>({args:c.args.map((v,i)=>i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v)}));
assert.deepEqual(keys(actualKeys),keys(expected),"mapped and posterior label anchors");
const originalLabels=calls(source,/\b(label)\(c, /g).filter(c=>c.args[0].startsWith("R.string")),nativeLabels=calls(all,/\b(label)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(originalLabels.length,2);assert.deepEqual(nativeLabels.map(c=>c.args.map(norm)),originalLabels.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v))));
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g))
 for(const lang of["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
const view=local("GalaxySSIHealthAtlasErectorView.swift");
assert(view.indexOf("art.erectorSupport")<view.indexOf("art.erectorTrunk"));assert(view.indexOf("art.erectorLoad")<view.indexOf("art.erectorTrunk"));
const shift=(y,f)=>49*f*Math.pow(Math.max(0,(250-y)/185),1.45),spineX=(y,f)=>151-13*Math.sin((y-69)*(2*Math.PI/198))+shift(y,f);
for(const t of[0,.2,.5,.8,1]){
 const e=t*t*(3-2*t);
 for(const step of[2,3]){
  const f=step===1?1-e:0;assert.equal(f,0);
  const points=Array.from({length:33},(_,i)=>{const y=72+(252-72)*i/32;return[spineX(y,f),y];});
  assert.deepEqual(points,Array.from({length:33},(_,i)=>{const y=72+(252-72)*i/32;return[spineX(y,0),y];}));
 }
 assert.equal(shift(250,1-e),0);assert.equal(shift(300,1-e),0);
}
assert.equal(Array.from({length:13},(_,i)=>76+14*i).at(-1),244);
const raw=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/res/drawable/health_atlas_erector_spinae_plate.xml"],{cwd:root,encoding:"utf8"});
const ordered=require("./body-atlas-ordered-vector.cjs"),paths=ordered(raw);
assert.equal(paths.length,19);assert.deepEqual(paths.flatMap((p,i)=>p._atlasMirrorX?[i]:[]),[14,15,16,17,18]);
assert.equal(paths.filter(p=>p["aapt:attr"]).length,8);
assert.throws(()=>ordered(raw.replace('android:scaleX="-1"','android:scaleX="0.5"')),/Unsupported atlas group transform/);
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="ERECTOR_SUPPORT");
assert.equal(story.durationMs,16000);assert.deepEqual(story.owners,["erector-spinae"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["columns","extension","supported","loaded"]);assert.equal(story.references.length,3);
assert.deepEqual(story.related,[{entryID:"muscle",storyID:"MUSCLE_MOTION"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "ERECTOR_SUPPORT": GalaxySSIHealthAtlasErectorView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-erector"],{cwd:root,stdio:"inherit"});
console.log("Android #4384 erector: 2 fixed outlines/exact trunk, 33-point paired/spinal traces, neutral geometry invariance, vertebral tilt/emphasis and 10 bilingual placements, ordered mirrored plate checked; no native compilation/pixels verified.");
