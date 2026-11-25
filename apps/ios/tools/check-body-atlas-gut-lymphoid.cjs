// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGutLymphoidStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasGutLymphoidGeometry.swift","GalaxySSIHealthAtlasGutLymphoidRoutes.swift","GalaxySSIHealthAtlasGutLymphoidMotion.swift","GalaxySSIHealthAtlasGutLymphoidCellDrawing.swift","GalaxySSIHealthAtlasGutLymphoidLocatorDrawing.swift","GalaxySSIHealthAtlasGutLymphoidSamplingDrawing.swift","GalaxySSIHealthAtlasGutLymphoidRecognitionDrawing.swift","GalaxySSIHealthAtlasGutLymphoidDefenseDrawing.swift","GalaxySSIHealthAtlasGutLymphoidView.swift","GalaxySSIHealthAtlasGutLymphoidLabelsDrawing.swift"];
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


const geometry=local("GalaxySSIHealthAtlasGutLymphoidGeometry.swift"),routes=local("GalaxySSIHealthAtlasGutLymphoidRoutes.swift"),motion=local("GalaxySSIHealthAtlasGutLymphoidMotion.swift");
const helpers=Object.fromEntries([...source.matchAll(/private fun Path\.(\w+)\(\) \{([^}]+)\}/g)].map(m=>[m[1],m[2]]));
const expand=b=>b.replace(/(\w+)\(\)/g,(m,n)=>helpers[n]||m);
const shapes=[...source.matchAll(/private val (\w+) = shape \{([^}]+)\}/g)];assert.equal(shapes.length,8);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(expand(body)),name);
}
const defs=[["domeTrack",shapes.find(m=>m[1]==="dome")[2]],...[...source.matchAll(/private val (\w+) = track\(shape \{([^}]+)\}/g)].map(m=>[m[1],m[2]])];
assert.equal(defs.length,5);
for(const[name,body]of defs){
 const native=routes.match(new RegExp("static let "+name+" = Track\\(([\\s\\S]*?)\\n  \\]\\)\\)"))[1];
 const start=native.match(/start:\s*\.init\(x:\s*([^,]+),\s*y:\s*([^)]+)\)/);
 const cs=[["moveTo",norm(start[1]),norm(start[2])],...[...native.matchAll(/kind:\s*\.(line|quad|cubic),\s*points:\s*\[([^\n]+)\]/g)].map(m=>[
 {line:"lineTo",quad:"quadTo",cubic:"cubicTo"}[m[1]],...[...m[2].matchAll(/[xy]:\s*([^,)]+)/g)].map(v=>norm(v[1]))])];
 assert.deepEqual(cs,fromCommands(expand(body)),name);assert(cs.length-1<=16);
}
const sourceBlock=n=>source.match(new RegExp("private fun "+n+"\\([\\s\\S]*?\\) \\{([\\s\\S]*?)(?=\\n    private fun)"))[1];
const cells=local("GalaxySSIHealthAtlasGutLymphoidCellDrawing.swift");
assert.deepEqual(toCommands(cells),fromCommands(sourceBlock("dendritic")),"six dendritic processes");
const nativeAntibody=cells.split("func gutLymphoidAntibody")[1].split("func gutLymphoidProtein")[0];
assert.deepEqual(calls(nativeAntibody,/\b(line)\(/g).map(c=>c.args.map(norm)),calls(sourceBlock("antibody"),/\b(line)\(c, /g).map(c=>c.args.map(norm)),"dimeric antibody glyph");
const labels=local("GalaxySSIHealthAtlasGutLymphoidLabelsDrawing.swift");
const sourceLabels=calls(source,/\b(label)\(c, /g).filter(c=>c.args[0].startsWith("R.string")),nativeLabels=calls(labels,/\b(label)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(sourceLabels.length,17);assert.deepEqual(nativeLabels.map(c=>c.args.map(norm)),sourceLabels.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v))));
const sourceLeaders=calls(source,/\b(leader)\(c, /g),nativeLeaders=calls(labels,/\b(gutLymphoidLeader)\(/g).filter(c=>!c.args[0].startsWith("_"));
assert.equal(sourceLeaders.length,14);assert.deepEqual(nativeLeaders.map(c=>c.args.map(norm)),sourceLeaders.map(c=>c.args.map(norm)));
for(const[swift,kotlin]of[
 ["ease(t,0,0.48)","ease(t, 0f, .48f)"],["ease(t,0.38,0.94)","ease(t, .38f, .94f)"],
 ["1+0.14*ease(t,0.04,0.68)","1f + .14f * ease(t, .04f, .68f)"],["1+0.13*ease(t,0.28,0.94)","1f + .13f * ease(t, .28f, .94f)"],
 ["ease(t,0.05,0.94)","ease(t, .05f, .94f)"],["ease(t,0.10,0.76)","ease(t, .10f, .76f)"],["ease(t,0.36,0.64)","ease(t, .36f, .64f)"],
 ["ease(t,0.03+Double(index)*0.23,0.70+Double(index)*0.14)","ease(t, .03f + index * .23f, .70f + index * .14f)"],
 ["progress*(1-0.095*Double(index))","progress * (1f - .095f * index)"],
 ["267-41*approach","267f - 41f * approach"],["258-34*approach","258f - 34f * approach"],["182+24*approach","182f + 24f * approach"],
 ["222+8*(1-approach)","222f + 8f * (1f - approach)"],["2.7*display","2.7f * display"],
 ["Double(Int(199-65*t))/255","(199f - 65f * t).toInt()"],["1.18-0.18*t","1.18f - .18f * t"],
 ["Double(i/5)-0.5","i / 5 - .5f"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of[
 'Image("HealthAtlasFunctionGutLymphoidLocator")','Image("HealthAtlasFunctionGutLymphoidComparison")',
 'CGRect(x:0,y:40,width:360,height:280)','gutLymphoidZoom(0,175,92,183,left)','gutLymphoidZoom(175,360,266,183,right)',
 'c.clip(to:Path(CGRect(x:left,y:119,width:right-left,height:149)))',
 'c.translateBy(x:x,y:y); c.scaleBy(x:amount,y:amount); c.translateBy(x:-x,y:-y)',
 'startAngle:.degrees(-100),endAngle:.degrees(-100+52+296*t),clockwise:false',
 'CGAffineTransform(a:rx*scale,b:0,c:0,d:ry*scale,tx:x,ty:y)','copy(c).stroke(p,color,2)',
 '(1..<46).compactMap','position:Double($0)/46','(1..<17).compactMap','Double(i)/17',
 'if x < 152 || x > 187','if (135...167).contains(y)','if display > 0',
 'gutLymphoidProtein(44,60,4.5)','gutLymphoidDendritic(182)','gutLymphoidDendritic(tip)',
 'if i == 0 || progress > 0','at(r.igaTrack.route,m.igaDistance(progress,i))','gutLymphoidAntibody(x,y,y < 122)',
 'secreted ? Self.teal : Self.blue','secreted ? 0xD9EAD8 : Self.cream','c.rotate(by:.degrees(-25))',
 'gutLymphoidFollicle(91,247,37,39)','gutLymphoidFollicle(288,249,31,39)',
 'gutLymphoidFill(g.mucosa,124,305,0xF5DBC8,0xD8A9B8,0x976C78)',
 'gutLymphoidFill(g.mucusBand,92,123,0xE5F1E8,0xAFD4CF,0xA4C6C0)',
 'gutLymphoidFill(g.surfaceEpithelium,118,166,0xF7D5BB,0xE3A7A0,0x976C78)',
 'accessibilityIdentifier("atlas-function-gut-lymphoid-sampling-art")'
])assert(all.includes(token),token);
const defense=local("GalaxySSIHealthAtlasGutLymphoidDefenseDrawing.swift"),sampling=local("GalaxySSIHealthAtlasGutLymphoidSamplingDrawing.swift");
assert(!defense.includes("FunctionPath.sample"));assert(!sampling.includes("FunctionPath.sample"));
assert(defense.indexOf("g.mucusBand")<defense.indexOf("g.surfaceEpithelium"));
const ease=(t,a,b)=>{const p=Math.min(1,Math.max(0,(t-a)/(b-a)));return p*p*(3-2*p);};
for(const[a,b]of[[0,.48],[.38,.94],[.04,.68],[.28,.94],[.05,.94],[.10,.76],[.36,.64]]){
 assert.equal(ease(a,a,b),0);assert.equal(ease(b,a,b),1);assert(Math.abs(ease((a+b)/2,a,b)-.5)<1e-12);
}
for(let i=0;i<3;i++){
 const a=.03+.23*i,b=.70+.14*i;assert.equal(ease(a,a,b),0);assert.equal(ease(b,a,b),1);
 assert(Math.abs(ease(b,a,b)*(1-.095*i)-(1-.095*i))<1e-12);
}
assert.deepEqual(Array.from({length:10},(_,i)=>Math.trunc(i/5)),[0,0,0,0,0,1,1,1,1,1]);
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="GUT_LYMPHOID_SAMPLING");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["appendix","gut-associated-lymphoid-tissue"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["locate","compare","sample","recognize","defend"]);assert.equal(story.references.length,5);
assert.deepEqual(story.related,[{entryID:"ileum",storyID:"INTESTINAL_ABSORPTION"}]);
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g))
 for(const lang of["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "GUT_LYMPHOID_SAMPLING": GalaxySSIHealthAtlasGutLymphoidView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-gut-lymphoid"],{cwd:root,stdio:"inherit"});
console.log("Android #4384 gut lymphoid: 8 expanded outlines/5 ordered routes, cached epithelial samples, uptake/contact/display/indexed IgA, clipped local zooms, 17 bilingual placements/14 leaders and 2 original plates checked; no native compilation/sampling/pixels verified.");
