// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasScapularRotationStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasScapularGeometry.swift","GalaxySSIHealthAtlasScapularMotion.swift","GalaxySSIHealthAtlasScapularPose.swift","GalaxySSIHealthAtlasScapularAnatomyDrawing.swift","GalaxySSIHealthAtlasScapularMuscleDrawing.swift","GalaxySSIHealthAtlasScapularSignalDrawing.swift","GalaxySSIHealthAtlasScapularLabelsDrawing.swift","GalaxySSIHealthAtlasScapularView.swift"];
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


const geometry=local("GalaxySSIHealthAtlasScapularGeometry.swift"),motion=local("GalaxySSIHealthAtlasScapularMotion.swift");
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(shapes.length,4);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
const ribArgs=calls(source.match(/private val ribs = arrayOf\(([\s\S]*?)\n    \)/)[1],/\b(rib)\(/g).map(c=>c.args.map(norm));
const nativeRibs=[...geometry.slice(geometry.indexOf("static let ribs")).matchAll(/Path \{ p in([^}]+)\}/g)].map(m=>toCommands(m[1]).flatMap(c=>c.slice(1)));
assert.equal(ribArgs.length,7);assert.deepEqual(nativeRibs,ribArgs,"seven original rib curves");
for(const name of ["sites","ribEnds"]){
 const expected=source.match(new RegExp("private val "+name+" = floatArrayOf\\(([^)]+)\\)"))[1].split(",").map(s=>Number(norm(s)));
 const actual=[...motion.match(new RegExp("static let "+name+": \\[CGPoint\\] = \\[([^\\n]+)"))[1].matchAll(/[xy]:([^,)]+)/g)].map(m=>Number(m[1]));
 assert.deepEqual(actual,expected,name);
}
const sourceBlock=n=>source.match(new RegExp("private fun "+n+"\\([\\s\\S]*?\\) \\{([\\s\\S]*?)(?=\\n    private fun)"))[1];
const muscles=local("GalaxySSIHealthAtlasScapularMuscleDrawing.swift");
for(const[name,file]of[
 ["drawClavicle",local("GalaxySSIHealthAtlasScapularAnatomyDrawing.swift")],
 ["drawSerratus",muscles.split("func scapularTrapezius")[0]],
 ["drawFan",muscles.split("private func scapularFan")[1]]
]) assert.deepEqual(toCommands(file),fromCommands(sourceBlock(name)),name+" contours and fibers");
for(const[swift,kotlin]of[
 ["0.18*ease",".18f * ease"],["0.18+0.41*ease",".18f + .41f * ease"],["0.59+0.41*ease",".59f + .41f * ease"],["1-ease","1f - ease"],
 ["Self.rotation(-36*pose, 212, 153, 2*pose, -6*pose)","turn.postTranslate(2f * pose, -6f * pose)"],
 ["Self.rotation(-116*pose, 251, 142, points[5].x-251, points[5].y-142)","armTurn.postTranslate(socketX - 251f, socketY - 142f)"],
 ["max(0,1-abs(4*t-Double(band)-0.5))","(1f - kotlin.math.abs(4f * t - band - .5f)).coerceAtLeast(0f)"],
 ["0.38+0.26*frame.amount",".38f + .26f * pose"],["span*0.76","span * .76f"],
 ["Double(Int(180*focus))/255","(180f * focus).toInt()"],["1+0.6*emphasis","1f + .6f * emphasis"],["0.9+focus*0.9",".9f + focus * .9f"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of [
 "Continuous 2D teaching poses, without fixed forces or on/off muscle phases.",
 "GalaxySSIHealthAtlasScapularMotion.sites.map { $0.applying(turn) }",
 "tx: px-px*c+py*s+dx, ty: py-px*s-py*c+dy",
 "arm.concatenate(frame.arm)","blade.concatenate(frame.turn)",
 "m.blend(pts[6].x,pts[4].x,f)","m.blend(pts[6].y,pts[4].y,f)",
 "for i in 0...4","Double(i)/4","m.ribEnds[i].x","m.ribEnds[i].y",
 "pts[end].x-(start == end ? 13 : 0)","pts[end].y+(start == end ? 6 : 0)",
 "m.regionFocus(start,reveal)","for i in 1...5","Double(i)/6",
 "step == 0 ? t : -1","step == 0 ? t : 1","if (1...3).contains(step)",
 "if step >= 3","returning:step == 4","if step == 3 || step == 4",
 "x = pts[5].x, y = pts[5].y, dx = x-pts[2].x, dy = y-pts[2].y",
 "x+4*dx*inv,y+4*dy*inv,x+31*dx*inv,y+31*dy*inv",
 "offset = returning ? 12.0 : -12.0","tx+offset,ty+16,tx-offset,ty+16",
 "line(x1,y1,x2,y2,Self.cream,4.4)","m.blend(p.x,dx,0.10)",
 "ty > y ? y+7 : y-17","x < 80 ? 86 : 108",'accessibilityIdentifier("atlas-function-scapular-rotation-art")'
])assert(all.includes(token),token);
const sourceFans=calls(sourceBlock("drawTrapezius"),/\b(drawFan)\(c, /g);
const actualFans=calls(muscles,/\b(scapularFan)\(frame,/g);
assert.equal(sourceFans.length,3);assert.equal(actualFans.length,3);
const colors={upperFill:[49,125,"0xEFCBD1","0xD49CB4"],middleFill:[102,159,"0xE8D2E9","0xC1A0C2"],lowerFill:[147,274,"0xD9CBE7","0xAA9BC8"]};
const inks={roseInk:"0x9C5F79",mauveInk:"0x846280",plumInk:"0x735D8C",serratusInk:"0x477E79",blue:"Self.blue"};
for(let i=0;i<3;i++){
 const a=sourceFans[i].args;
 const expected=[String(Number(a[0])/2),String(Number(a[1])/2),...a.slice(2,6),...colors[a[6]].map(String),inks[a[7]],a[8]].map(norm);
 assert.deepEqual(actualFans[i].args.map(norm),expected,"fan mapping "+i);
}
const originalKeys=calls(source,/\b(key)\(c, /g).filter(c=>c.args[0].startsWith("R.string"));
const actualKeys=calls(all,/\b(scapularKey)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(originalKeys.length,7);assert.equal(actualKeys.length,7);
const aliases=s=>s.replace(/pts\[(\d+)\]/g,(_,n)=>"pts["+Math.floor(+n/2)+"]."+(+n%2?"y":"x"))
 .replace(/if \(step == 0\) regionFocus\((\d), t\) else 0f/g,"step == 0 ? regionFocus($1,t) : 0")
 .replace(/roseInk|mauveInk|plumInk|serratusInk|\bblue\b/g,s=>inks[s]);
for(const c of originalKeys){
 const expected=c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':aliases(v)));
 assert(actualKeys.some(c=>JSON.stringify(c.args.map(norm))===JSON.stringify(expected)),expected);
}
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g)){
 assert(all.includes('"'+key+'"'),key);
 for(const lang of ["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
}
const view=local("GalaxySSIHealthAtlasScapularView.swift"),order=["art.scapularFoundation","art.scapularSerratus","art.scapularBones","art.scapularTrapezius","art.scapularPulls","art.scapularSocket","art.scapularLabels"];
for(let i=1;i<order.length;i++)assert(view.indexOf(order[i-1])<view.indexOf(order[i]),"layer order");
const matrix=(p,angle,center,shift)=>{const a=angle*Math.PI/180,c=Math.cos(a),s=Math.sin(a),[px,py]=center,[dx,dy]=shift;return [c*p[0]-s*p[1]+px-px*c+py*s+dx,s*p[0]+c*p[1]+py-px*s-py*c+dy];};
const sites=[253,114,243,125,193,143,187,153,194,247,251,142,181,177];
for(const pose of[0,.18,.59,.8,1]){
 const pts=Array.from({length:7},(_,i)=>matrix(sites.slice(i*2,i*2+2),-36*pose,[212,153],[2*pose,-6*pose]));
 const socket=pts[5],head=matrix([251,142],-116*pose,[251,142],[socket[0]-251,socket[1]-142]);
 assert(Math.hypot(head[0]-socket[0],head[1]-socket[1])<1e-10);
 const delta=[socket[0]-pts[2][0],socket[1]-pts[2][1]],len=Math.hypot(...delta);
 assert(Math.abs(Math.hypot(27*delta[0]/len,27*delta[1]/len)-27)<1e-10);
}
assert(Math.abs((.18+.41)-.59)<1e-12);assert.equal(.59+.41,1);
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="SCAPULAR_ROTATION");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["trapezius","scapula"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["regions","clavicle","coupling","rotation","return"]);assert.equal(story.references.length,4);
assert.deepEqual(story.related,[{entryID:"deltoid",storyID:"DELTOID_LIFT"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "SCAPULAR_ROTATION": GalaxySSIHealthAtlasScapularView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 scapular rotation: 4 fixed outlines/7 ribs, 12 anchor pairs, exact fan/serratus/clavicle paths, attached transforms, directed force/socket cues and 7 bilingual keys checked; no native compilation/pixels verified.");
