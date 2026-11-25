// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPlacentalExchangeStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasPlacentalGeometry.swift","GalaxySSIHealthAtlasPlacentalRoutes.swift","GalaxySSIHealthAtlasPlacentalMotion.swift","GalaxySSIHealthAtlasPlacentalAnatomyDrawing.swift","GalaxySSIHealthAtlasPlacentalFlowDrawing.swift","GalaxySSIHealthAtlasPlacentalTransferDrawing.swift","GalaxySSIHealthAtlasPlacentalView.swift","GalaxySSIHealthAtlasPlacentalLabelsDrawing.swift"];
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


const geometry=local("GalaxySSIHealthAtlasPlacentalGeometry.swift"),routes=local("GalaxySSIHealthAtlasPlacentalRoutes.swift"),motion=local("GalaxySSIHealthAtlasPlacentalMotion.swift");
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(shapes.length,7);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
for(const name of ["maternal","fetal"]){
 const native=routes.match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
 const start=native.match(/start:\s*\.init\(x:\s*([^,]+),\s*y:\s*([^)]+)\)/);
 const cs=[["moveTo",norm(start[1]),norm(start[2])],...[...native.matchAll(/kind:\s*\.(line|quad|cubic),\s*points:\s*\[([^\n]+)\]/g)].map(m=>[
 {line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]:\s*([^,)]+)/g)].map(v=>norm(v[1]))])];
 assert.deepEqual(cs,fromCommands(shapes.find(m=>m[1]===name+"Route")[2]),name);
}
const originalNuclei=[...source.match(/private val nuclei = arrayOf\(([\s\S]*?)\n    \)/)[1].matchAll(/floatArrayOf\(([^)]+)\)/g)].map(m=>m[1].split(",").map(s=>Number(norm(s))));
const actualNuclei=[...geometry.slice(geometry.indexOf("static let nuclei")).matchAll(/\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)/g)].map(m=>m.slice(1).map(Number));
assert.equal(originalNuclei.length,12);assert.deepEqual(actualNuclei,originalNuclei);
const labels=local("GalaxySSIHealthAtlasPlacentalLabelsDrawing.swift");
const expected=calls(source,/\b(leader)\(c, /g).filter(c=>c.args[0].startsWith("R.string"));
const actual=calls(labels,/\b(placentalLeader)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(expected.length,8);
assert.deepEqual(actual.map(c=>c.args.map(norm)),expected.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v))));
const sourceLabels=calls(source,/\b(label)\(c, /g).filter(c=>c.args[0].startsWith("R.string"));
const nativeLabels=calls(all,/\b(label)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(sourceLabels.length,8);
assert.deepEqual(nativeLabels.map(c=>c.args.map(norm)),sourceLabels.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v))));
const diamond=source.match(/private fun diamond\([^\n]*\) \{([\s\S]*?)(?=\n    private fun)/)[1];
assert.deepEqual(toCommands(local("GalaxySSIHealthAtlasPlacentalTransferDrawing.swift")),fromCommands(diamond),"diamond glyph");
for(const [swift,kotlin]of[
 ["4*f*(1-f)","4f * f * (1f - f)"],["phase(t)+Double(index)/3","phase(t) + index / 3f"],["f-Double(Int(f))","f - f.toInt()"],
 ["f*f*(3-2*f)","f * f * (3f - 2f * f)"],
 ["transfer(t,0.08,0.79)","transfer(t, .08f, .79f)"],["transfer(t,0.20,0.91)","transfer(t, .20f, .91f)"],["transfer(t,0.07,0.89)","transfer(t, .07f, .89f)"],
 ["117+45*oxygen","117f + 45f * oxygen"],["158-42*carbon","158f - 42f * carbon"],["115+44*travel","115f + 44f * travel"],
 ["min(1,progress*12,(1-progress)*12)","minOf(1f, progress * 12f, (1f - progress) * 12f)"],
 ["placentalTransporter(138.8,179)","transporter(c, 138.8f, 179f)"],["placentalTransporter(146.2,179)","transporter(c, 146.2f, 179f)"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of[
 'Image("HealthAtlasFunctionPlacenta")','CGRect(x:20,y:53,width:320,height:249)',
 "210.2-r,y:202.4-r","12+6*GalaxySSIHealthAtlasPlacentalMotion.emphasis(t)",
 "stroke(ring,0xFDF4DA,3.4); stroke(ring,0x3E7582,1.4)",
 "gradient(g.field,92,263,0xF8E6DF,0xE9BFC0)","gradient(g.surface,92,257,0xD9A2A2,0xB77987)",
 "gradient(g.core,93,250,0xF0D8C0,0xE6B494)",
 "c.clip(to:g.surface)","art.stroke(g.fetalRoute,0x527681,18); art.stroke(g.fetalRoute,0xB2D2D2,14)",
 "routeChapter ? 0xA66070 : 0xBD8990","routeChapter ? 0x3E7582 : 0x6A949B","let count = routeChapter ? 3 : 2",
 "dash:[3,4],dashPhase:0","placentalRouteArrow(r.maternal,0.10,maternal)","placentalRouteArrow(r.maternal,0.89,maternal)",
 "placentalRouteArrow(r.fetal,0.08,fetal)","placentalRouteArrow(r.fetal,0.87,fetal)",
 "sample.direction.dx","sample.direction.dy","arrow(x-6*dx,y-6*dy,x+6*dx,y+6*dy,color)",
 "startAngle:.degrees(110),endAngle:.degrees(250),clockwise:false",
 "CGAffineTransform(a:5.1,b:0,c:0,d:20.5,tx:142.9,ty:181.5)",
 "CGAffineTransform(a:4.9,b:0,c:0,d:19,tx:154.1,ty:181)",
 "Trace adjacent surfaces separately, without suggesting a connecting channel.",
 "below ? 5 : -15",'accessibilityIdentifier("atlas-function-placental-exchange-art")'
])assert(all.includes(token),token);
const interfaceSource=source.match(/private fun interfaceFocus[\s\S]*?(?=\n    private fun)/)[0];
const arcs=[...interfaceSource.matchAll(/c.drawArc\(([^)]+)\)/g)].map(m=>m[1].split(",").slice(0,6).map(s=>Number(norm(s))));
assert.equal(arcs.length,2);
assert.deepEqual(arcs.map(([x1,y1,x2,y2,a,b])=>[(x2-x1)/2,(y2-y1)/2,(x1+x2)/2,(y1+y2)/2,a,a+b]).map(row=>row.map(v=>+v.toFixed(9))),
 [[5.1,20.5,142.9,181.5,110,250],[4.9,19,154.1,181,110,250]]);
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g))
 for(const lang of["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
const view=local("GalaxySSIHealthAtlasPlacentalView.swift");
assert(view.indexOf("art.placentalVillus")<view.indexOf("art.placentalFlows"));
assert(view.indexOf("art.placentalGlucose")<view.indexOf("art.placentalAnatomyLabels"));
for(const [n,method]of[[1,"RouteKey()"],[2,"Interface(t)"],[3,"Gases(t)"],[4,"Glucose(t)"]])assert(view.includes("case "+n+": art.placental"+method));
const emphasis=t=>4*t*(1-t),transfer=(t,a,b)=>{const f=Math.min(1,Math.max(0,(t-a)/(b-a)));return f*f*(3-2*f);};
assert.equal(emphasis(0),0);assert.equal(emphasis(.5),1);assert.equal(emphasis(1),0);
for(const[a,b]of[[.08,.79],[.20,.91],[.07,.89]]){
 assert.equal(transfer(a,a,b),0);assert.equal(transfer(b,a,b),1);assert(Math.abs(transfer((a+b)/2,a,b)-.5)<1e-12);
}
for(const t of[0,.25,.5,.75,1])for(let i=0;i<3;i++){const f=t+i/3,p=f-Math.trunc(f),size=Math.min(1,p*12,(1-p)*12);assert(p>=0&&p<1&&size>=0&&size<=1);}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="PLACENTAL_EXCHANGE");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["placenta","cell-trophoblast"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["orient","routes","interface","gases","nutrients"]);assert.equal(story.references.length,4);
for(const ref of story.references)assert(source.includes(ref.url));
assert.deepEqual(story.related,[{entryID:"capillaries",storyID:"ENDOTHELIAL_EXCHANGE"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "PLACENTAL_EXCHANGE": GalaxySSIHealthAtlasPlacentalView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-placenta"],{cwd:root,stdio:"inherit"});
console.log("Android #4384 placental exchange: 7 fixed paths/2 distinct routes, 12 nuclear poses, 16 bilingual placements, separate interface arcs and transfer/flow rules plus original plate checked; no native compilation/pixels verified.");
