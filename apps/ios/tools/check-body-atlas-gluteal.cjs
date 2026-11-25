// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGlutealExtensionStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasGlutealGeometry.swift","GalaxySSIHealthAtlasGlutealPose.swift","GalaxySSIHealthAtlasGlutealAnatomyDrawing.swift","GalaxySSIHealthAtlasGlutealMuscleDrawing.swift","GalaxySSIHealthAtlasGlutealDirectionDrawing.swift","GalaxySSIHealthAtlasGlutealSceneDrawing.swift","GalaxySSIHealthAtlasGlutealLabelsDrawing.swift","GalaxySSIHealthAtlasGlutealView.swift"];
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


const geometry=local("GalaxySSIHealthAtlasGlutealGeometry.swift"),pose=local("GalaxySSIHealthAtlasGlutealPose.swift");
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];assert.equal(shapes.length,5);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
for(const name of["origin","insertion"]){
 const expected=source.match(new RegExp("private val "+name+" = floatArrayOf\\(([^)]+)\\)"))[1].split(",").map(s=>Number(norm(s)));
 const actual=[...pose.match(new RegExp("static let "+name+": \\[CGPoint\\] = \\[([^\\n]+)"))[1].matchAll(/[xy]:([^,)]+)/g)].map(m=>Number(m[1]));
 assert.deepEqual(actual,expected,name);assert.equal(actual.length,name==="origin"?8:6);
}
const sourceBlock=n=>source.match(new RegExp("private fun "+n+"\\([\\s\\S]*?\\) \\{([\\s\\S]*?)(?=\\n    private fun)"))[1];
const indexed=s=>s.replace(/([ab])\[(\d+)\]/g,(_,a,i)=>a+"["+Math.floor(+i/2)+"]."+(+i%2?"y":"x"));
const glute=sourceBlock("drawGluteus"),nativeMuscle=geometry.match(/static func muscle[\s\S]*?return Path \{ p in([\s\S]*?)\n  \}/)[1];
assert.deepEqual(toCommands(nativeMuscle),fromCommands(indexed(glute.slice(0,glute.indexOf("tissue(c, muscle")))),"attached muscle");
assert.deepEqual(toCommands(local("GalaxySSIHealthAtlasGlutealMuscleDrawing.swift")),fromCommands(indexed(glute.slice(glute.indexOf("c.save()")))),"clipped fascicles/tendon");
assert.deepEqual(toCommands(local("GalaxySSIHealthAtlasGlutealAnatomyDrawing.swift")),fromCommands(sourceBlock("lumbar")),"lumbar contour");
for(const token of[
 "tx:190-190*c+173*s,ty:173-190*s-173*c","origins = Self.origin.map { $0.applying(pelvis) }","insertions = Self.insertion.map { $0.applying(femur) }",
 "pelvis.concatenate(frame.pelvis)","femur.concatenate(frame.femur)",
 "glutealAnatomy(frame,0); glutealSweep(150,58,44,ease)","glutealAnatomy(frame,0); glutealSweep(131,-61,-44,ease)",
 "GalaxySSIHealthAtlasGlutealPose(0,-32+44*ease)","GalaxySSIHealthAtlasGlutealPose(29-44*ease,0)",
 "left.translateBy(x:-8,y:70); left.scaleBy(x:0.54,y:0.54)",
 "right.translateBy(x:173,y:70); right.scaleBy(x:0.54,y:0.54)",
 "r.glutealLumbar(1,ghost:true); r.glutealAnatomy(.init(0,0),1-ease)","r.arrow(182,49,147,49,Self.teal)",
 "let a=frame.origins, b=frame.insertions","c.clip(to:shape)","for i in 1...6","Double(i)/7",
 "Double(a[0].x)+(Double(a[3].x)-Double(a[0].x))*f-9",
 "Double(a[0].y)+(Double(a[3].y)-Double(a[0].y))*f",
 "Double(b[0].x)+(Double(b[2].x)-Double(b[0].x))*f",
 "Double(b[0].y)+(Double(b[2].y)-Double(b[0].y))*f",
 "stroke(tendon,0xEEDBD5,3.3); stroke(tendon,0xA17E8D,1.15)",
 "Double(Int(80+120*focus))/255","r = 6+3*focus","focus = (1+wave(t-0.25))/2",
 "clockwise:span < 0","(start+span-(span > 0 ? 4 : -4)) * .pi/180",
 "190+radius*cos(theta),173+radius*sin(theta)","disc(190,173,6.5,Self.cream,border:Self.blue)",
 "34*flex*(1-f)*(1-f)","ghost ? 1.4 : 3.5","cornerRadius:3.4",
 'accessibilityIdentifier("atlas-function-gluteal-extension-art")'
])assert(all.includes(token),token);
for(const token of["blend(-32f, 12f, ease)","blend(29f, -15f, ease)","c.translate(-8f, 70f)","c.translate(173f, 70f)","c.scale(.54f, .54f)",
 "anatomy(c, 0f, 0f, 1f - ease)","lumbar(c, 1f, ghost = true)","(80f + 120f * focus).toInt()"])assert(source.includes(token),token);
const inks={muscleInk:"0x9E617A",boneInk:"0x779095",blue:"Self.blue"};
const fromKeys=calls(source,/\b(key|trackedKey)\(c, /g).filter(c=>c.args[0].startsWith("R.string"));
const toKeys=calls(all,/\b(glutealKey)\(/g).filter(c=>c.args[0].startsWith('"'));assert.equal(fromKeys.length,8);assert.equal(toKeys.length,8);
const number=s=>Number(norm(s.replaceAll("HIP_X","190").replaceAll("HIP_Y","173")));
const target=s=>{
 const m=s.match(/^CGPoint\(x:([^,]+),y:([^)]+)\)(?:\.applying\(frame\.(femur|pelvis)\))?$/);assert(m,s);
 return [number(m[1]),number(m[2]),m[3]||"fixed"];
};
const expected=fromKeys.map(c=>{
 const a=c.args,tracked=c.name==="trackedKey";
 return ['"'+a[0].replace("R.string.health_atlas_","")+'"',number(a[1]),number(a[2]),
 ...(tracked?[number(a[4]),number(a[5]),a[3]==="femurTurn"?"femur":"pelvis"]:[number(a[3]),number(a[4]),"fixed"]),
 tracked?"Self.blue":inks[a[5]],number(a[6])];
}).sort((a,b)=>a[0].localeCompare(b[0]));
const actual=toKeys.map(c=>{const a=c.args;return[a[0],number(a[1]),number(a[2]),...target(a[3]),a[4],number(a[5])];}).sort((a,b)=>a[0].localeCompare(b[0]));
assert.deepEqual(actual,expected,"fixed/tracked label anchors");
const originalLabels=calls(source,/\b(label)\(c, /g).filter(c=>c.args[0].startsWith("R.string")),nativeLabels=calls(all,/\b(label)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(originalLabels.length,5);assert.deepEqual(nativeLabels.map(c=>c.args.map(norm)),originalLabels.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v))));
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g))
 for(const lang of["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
const rotate=(p,degrees)=>{const a=degrees*Math.PI/180,c=Math.cos(a),s=Math.sin(a);return[190+(p[0]-190)*c-(p[1]-173)*s,173+(p[0]-190)*s+(p[1]-173)*c];};
for(const ease of[0,.25,.5,.75,1]){
 for(const angle of[-32+44*ease,29-44*ease]){
  assert.deepEqual(rotate([190,173],angle),[190,173]);
  for(const p of[[128,118],[117,177],[159,207],[158,233]]){const r=rotate(p,angle);assert(Math.abs(Math.hypot(r[0]-190,r[1]-173)-Math.hypot(p[0]-190,p[1]-173))<1e-10);}
 }
 for(const [start,span]of[[58,44],[-61,-44]]){const end=start+span,near=end-(span>0?4:-4);assert.equal(Math.sign(end-near),Math.sign(span));}
}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="GLUTEAL_EXTENSION");
assert.equal(story.durationMs,16000);assert.deepEqual(story.owners,["gluteus-maximus"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["attachments","femur","pelvis","compare"]);assert.equal(story.references.length,3);
assert.deepEqual(story.related,[{entryID:"muscle",storyID:"MUSCLE_MOTION"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "GLUTEAL_EXTENSION": GalaxySSIHealthAtlasGlutealView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 gluteal: 5 exact outlines/7 anchor pairs, independent hip-centered transforms, attached muscle/clipped fascicles/tendon, signed arcs and fixed-hip lumbar comparison, 13 bilingual placements checked; no native compilation/pixels verified.");
