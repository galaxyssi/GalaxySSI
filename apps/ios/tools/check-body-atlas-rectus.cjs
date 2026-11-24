// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasRectusFlexionStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasRectusGeometry.swift","GalaxySSIHealthAtlasRectusMotion.swift","GalaxySSIHealthAtlasRectusContours.swift","GalaxySSIHealthAtlasRectusDeflection.swift","GalaxySSIHealthAtlasRectusDrawing.swift","GalaxySSIHealthAtlasRectusLabelsDrawing.swift","GalaxySSIHealthAtlasRectusView.swift"];
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


const geometry=local("GalaxySSIHealthAtlasRectusGeometry.swift"),motion=local("GalaxySSIHealthAtlasRectusMotion.swift"),cache=local("GalaxySSIHealthAtlasRectusDeflection.swift"),sampler=local("GalaxySSIHealthAtlasRectusContours.swift");
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(shapes.length,11);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
 for(const command of fromCommands(body))for(const n of command.slice(1))assert(Number.isFinite(Number(n))&&Number(n)>=0&&Number(n)<=360,name);
}
const sourceNames=[...new Set([...source.matchAll(/deflect\((\w+)\)/g)].map(m=>m[1]))];
const cacheNames=[...cache.matchAll(/static let (\w+) = GalaxySSIHealthAtlasRectusContours\(G\.(\w+)\)/g)].map(m=>{assert.equal(m[1],m[2]);return m[1];});
assert.equal(sourceNames.length,9);assert.deepEqual(cacheNames,sourceNames);
const count=sourceNames.map(n=>fromCommands(shapes.find(m=>m[1]===n)[2]));
assert.equal(count.reduce((a,cs)=>a+cs.filter(c=>c[0]==="moveTo").length,0),26);
assert.equal(count.reduce((a,cs)=>a+cs.filter(c=>c[0]==="close").length,0),5);
for(const name of["poses","effort"]){
 const expected=source.match(new RegExp("private val "+name+" = floatArrayOf\\(([^)]+)\\)"))[1].split(",").map(s=>Number(norm(s)));
 const actual=motion.match(new RegExp("static let "+name+": \\[Double\\] = \\[([^\\]]+)\\]"))[1].split(",").map(Number);
 assert.deepEqual(actual,expected,name);assert.equal(actual.length,6);
}
for(const[swift,kotlin]of[
 ["y >= 260 || bend < 0.0001","y >= 260f || bend < .0001f"],
 ["260-y","260f - y"],["min(104,rise)","minOf(104f, rise)"],["bend*arc/104","bend * arc / 104f"],["104/bend","104f / bend"],
 ["x-150","x - 150f"],["rise-arc","rise - arc"],["sin(angle*0.5)","sin(angle * .5f)"],
 ["150+2*radius*halfSin*halfSin+upper*sin(angle)+side*cos(angle)","150f + 2f * radius * halfSin * halfSin + upper * sin(angle) + side * cos(angle)"],
 ["260-radius*sin(angle)-upper*cos(angle)+side*sin(angle)","260f - radius * sin(angle) - upper * cos(angle) + side * sin(angle)"],
 ["Double(Int(50*motion.tone))/255","(50f * tone).toInt()"],["1+0.6*motion.tone","1f + .6f * tone"],
 ["step != 4 || t < 0.92","step != 4 || t < .92f"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of[
 "0.57*Self.lerp(Self.poses[step],Self.poses[step+1],ease)","Self.lerp(Self.effort[step],Self.effort[step+1],ease)",
 "let count = max(1,Int(length/3))","(0...count).map","path.trimmedPath(from:0,to:CGFloat(Double(i)/Double(count))).cgPath.currentPoint",
 "case .moveToPoint:","case .addLineToPoint:","case .addQuadCurveToPoint:","case .addCurveToPoint:","case .closeSubpath:",
 "finish()","length += hypot(start.x-end.x,start.y-end.y)","path.closeSubpath(); end = start; closed = true",
 "GalaxySSIHealthAtlasCurveLength.bezier([end,control,next])","GalaxySSIHealthAtlasCurveLength.bezier([end,first,second,next])",
 "guard motion.bend >= 0.0001, let contours else { return source }","if i == 0 { return start }",
 "if i == 0 { p.move(to:mapped) } else { p.addLine(to:mapped) }","if contour.closed { p.closeSubpath() }",
 "rectusTissue(g.pelvis,239,306,0xF8F4E7,0xD7CBB5,0x998A77)","stroke(g.pelvicDetail,0xB7A68F,1.65)",
 "rectusTissue(d.wall.deflect(motion),69,281,0xE7F2EE,0xCCDEDB,0x91A7A5)",
 "rectusTissue(d.ribCage.deflect(motion),80,169,0xFCF8EB,0xDFD7C5,0x998A77)",
 "rectusTissue(belly,137,260,0xEDC4BD,0xC08788,0xA06269)","copy(tint).fill(belly,0xA25361)",
 "rectusDirection(step >= 3)","ty > y ? y+6 : y-17",'accessibilityIdentifier("atlas-function-rectus-trunk-flexion-art")'
])assert(all.includes(token),token);
assert(!sampler.includes("Timer"));assert(!local("GalaxySSIHealthAtlasRectusDrawing.swift").includes("CurveLength"));
const labels=local("GalaxySSIHealthAtlasRectusLabelsDrawing.swift"),expected=calls(source,/\b(leader)\(c, /g).filter(c=>c.args[0].startsWith("R.string")),actual=calls(labels,/\b(rectusLeader)\(/g).filter(c=>c.args[0].startsWith('"'));
const inks={boneInk:"0x998A77",rectusInk:"0xA06269",blue:"Self.blue"};
assert.equal(expected.length,5);assert.equal(actual.length,5);
assert.deepEqual(actual.map(c=>c.args.slice(0,-1).map(norm)),expected.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':inks[v]||v))));
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g)){
 assert(all.includes('"'+key+'"'),key);
 for(const lang of["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
}
const direction=source.match(/private fun motion\([^\n]*\) \{([\s\S]*?)(?=\n    private fun)/)[1];
assert.deepEqual(toCommands(local("GalaxySSIHealthAtlasRectusDrawing.swift")),fromCommands(direction),"fixed direction arc");
assert(all.includes("arrow(243,44,233,46,Self.blue)"));assert(all.includes("arrow(290,61,297,68,Self.blue)"));
const map=(x,y,bend)=>{
 if(y>=260||bend<.0001)return[x,y];
 const rise=260-y,arc=Math.min(104,rise),a=bend*arc/104,r=104/bend,side=x-150,upper=rise-arc,h=Math.sin(a*.5);
 return[150+2*r*h*h+upper*Math.sin(a)+side*Math.cos(a),260-r*Math.sin(a)-upper*Math.cos(a)+side*Math.sin(a)];
};
for(const bend of[0,.000099,.0001,.04,.1881,.57]){
 for(const[x,y]of[[209,260],[138,274],[180,308]])assert.deepEqual(map(x,y,bend),[x,y]);
 if(bend>=.0001){
  const mid=map(150,156,bend),upper=map(150,73,bend),r=104/bend;
  assert(Math.abs(mid[0]-(150+r*(1-Math.cos(bend))))<1e-8);
  assert(Math.abs(mid[1]-(260-r*Math.sin(bend)))<1e-8);
  assert(Math.abs(Math.hypot(upper[0]-mid[0],upper[1]-mid[1])-83)<1e-8);
 }
}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="RECTUS_TRUNK_FLEXION");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["rectus-abdominis"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["align","engage","flex","return","relax"]);assert.equal(story.references.length,3);
assert.deepEqual(story.related,[{entryID:"muscle",storyID:"MUSCLE_MOTION"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "RECTUS_TRUNK_FLEXION": GalaxySSIHealthAtlasRectusView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 rectus: 11 exact outlines, 9 deflected sources/26 contours, source pose/tone and lumbar mapping, native sampler contracts, stationary pelvis and 5 mapped bilingual anchors checked; no native compilation/sampling/pixels verified.");
