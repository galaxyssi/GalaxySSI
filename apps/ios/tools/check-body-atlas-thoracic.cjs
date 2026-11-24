// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasThoracicFrameStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasThoracicMotion.swift","GalaxySSIHealthAtlasThoracicGeometry.swift","GalaxySSIHealthAtlasThoracicFrontDrawing.swift","GalaxySSIHealthAtlasThoracicProfileDrawing.swift","GalaxySSIHealthAtlasThoracicDrawing.swift","GalaxySSIHealthAtlasThoracicSternum.swift","GalaxySSIHealthAtlasThoracicLungGeometry.swift","GalaxySSIHealthAtlasThoracicLungDrawing.swift","GalaxySSIHealthAtlasThoracicSceneDrawing.swift","GalaxySSIHealthAtlasThoracicView.swift"];
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

const sourceBlock=n=>source.match(new RegExp("private fun "+n+"\\([^\\n]*\\) \\{([\\s\\S]*?)(?=\\n    private fun)"))[1];
function nativeBody(file, name, isLet=false) {
 const regex=new RegExp(isLet ? "static let "+name+" = Path \\{" : "static func "+name+"\\([^\\n]+\\{");
 const match=regex.exec(file);assert(match,name);
 const start=match.index+match[0].length;let end=start,depth=1;
 for(;end<file.length&&depth;end++){if(file[end]==="{")depth++;if(file[end]==="}")depth--;}
 assert.equal(depth,0,name);return file.slice(start,end-1);
}
const geometry=local("GalaxySSIHealthAtlasThoracicGeometry.swift"),sternum=local("GalaxySSIHealthAtlasThoracicSternum.swift"),lung=local("GalaxySSIHealthAtlasThoracicLungGeometry.swift");
const frontBone=sourceBlock("frontSternum"), sideBone=sourceBlock("sideSternumPath");
const frontLung=sourceBlock("frontLung"), profileLung=sourceBlock("profileLung");
const parts=(b,tag,start=0)=>{const i=b.indexOf(tag,start),tail=b.slice(i+tag.length);return tail.slice(0,tail.indexOf("washed("));};
const cases=[
 ["sternum",nativeBody(sternum,"front",true),frontBone.slice(0,frontBone.indexOf("washed("))],
 ["sternum relief",nativeBody(sternum,"relief",true),frontBone.slice(frontBone.indexOf("detail.rewind()"))],
 ["side sternum",nativeBody(sternum,"side"),sideBone],
 ["front lung",nativeBody(lung,"front"),parts(frontLung,"curve.rewind()")],
 ["front fissures",nativeBody(lung,"frontDetail"),frontLung.slice(frontLung.indexOf("detail.rewind()"),frontLung.indexOf("stroke(c, detail"))],
 ["front diaphragm",nativeBody(lung,"frontDiaphragm"),parts(frontLung,"curve.rewind()",frontLung.indexOf("stroke(c, detail"))],
 ["side lung",nativeBody(lung,"profile"),parts(profileLung,"curve.rewind()")],
 ["side fissures",nativeBody(lung,"profileDetail"),profileLung.slice(profileLung.indexOf("detail.rewind()"),profileLung.indexOf("stroke(c, detail"))],
 ["side diaphragm",nativeBody(lung,"profileDiaphragm"),parts(profileLung,"curve.rewind()",profileLung.indexOf("stroke(c, detail"))],
 ["front rib",nativeBody(geometry,"frontRib"),sourceBlock("frontRib")],
 ["rear rib",nativeBody(geometry,"rearRib"),sourceBlock("front").slice(0,sourceBlock("front").indexOf("if (cutaway)"))],
 ["cartilage",nativeBody(geometry,"cartilage"),sourceBlock("frontCartilages").split("// The lower")[0]],
 ["costal margin",nativeBody(geometry,"costalMargin"),sourceBlock("frontCartilages").split("// The lower")[1]],
 ["side rib",nativeBody(geometry,"sideRib"),sourceBlock("sideRib")],
 ["side cartilage",nativeBody(geometry,"sideCartilage"),sourceBlock("profile")]
];
for(const[name,to,from]of cases)assert.deepEqual(toCommands(to),fromCommands(from),name);
for(const name of ["lateral","join"]){
 const sourceArray=source.match(new RegExp("private val "+name+" = floatArrayOf\\(([^)]+)\\)"))[1].split(",").map(s=>Number(norm(s)));
 const nativeArray=local("GalaxySSIHealthAtlasThoracicMotion.swift").match(new RegExp("static let "+name+" = \\[([^\\]]+)\\]"))[1].split(",").map(Number);
 assert.equal(sourceArray.length,12);assert.deepEqual(nativeArray,sourceArray,name);
}
for(const[swift,kotlin]of[
 ["x+max(0, x-13)*0.14*b","x + (x - 13f).coerceAtLeast(0f) * .14f * b"],
 ["y-(6+max(0, x-13)*0.045)*b","y - (6f + (x - 13f).coerceAtLeast(0f) * .045f) * b"],
 ["84+15*Double(i)","84f + 15f * i"],["99+16.2*Double(i)","99f + 16.2f * i"],["254+7*Double(i-10)","254f + 7f * (i - 10)"],
 ["85+17*Double(i)","85f + 17f * i"],["107+0.8*Double(i)","107f + .8f * i"],["73+16*Double(i)","73f + 16f * i"],
 ["251+(y-90)*0.085+14*b","251f + (y - 90f) * .085f + 14f * b"],
 ["x-(x-tip)*0.52","x - (x - tip) * .52f"],["105+12*b","105f + 12f * b"],["239+5*b","239f + 5f * b"],
 ["248+12*b","248f + 12f * b"],["210+17*b","210f + 17f * b"],
 ["px+(endX-px)*cosine-(endY-py)*sine","px + (endX - px) * cosine - (endY - py) * sine"],
 ["py+(endX-px)*sine+(endY-py)*cosine","py + (endX - px) * sine + (endY - py) * cosine"],
 ["(width-3)*0.35","(width - 3f) * .35f"],["8.5+Double(i)*0.29","8.5f + i * .29f"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of [
 "0.38*wave*wave","step == 4 ? 1-eased : eased","t*t*(3-2*t)","sin(.pi*t)",
 "for side in [-1.0, 1.0]","c.scaleBy(x: side, y: 1)","heartSide: side > 0",
 "for i in 0...5","for i in 7...9","for i in stride(from: 6, through: 0, by: -1)",
 "c.rotate(by: .degrees(-8*b))","c.translateBy(x: -px, y: -py)","let angle = -8*b * .pi/180",
 "c.translateBy(x: 180, y: -6*b)","c.translateBy(x: 0, y: -9*b)",
 "strong ? 8.1 : (i == 0 || i >= 10) ? 5.4 : 7.1","strong ? 8.8 : 6.9",
 "dash: [4,4], dashPhase: 0","0x88FFFFFF","for i in 0...11",
 "heartSide ? 11.0 : 0.0","if !heartSide","returning ? 178 : 228+5*b",
 "returning ? 210+17*b : 222+14*b","0xEAF5F7, 0xF9F7F2",
 'accessibilityIdentifier("atlas-function-thoracic-frame-art")'
])assert(all.includes(token),token);
const scene=local("GalaxySSIHealthAtlasThoracicSceneDrawing.swift");
const aliases=s=>s.replaceAll("liftInk","0x8B536B").replaceAll("widthInk","0x2C766E").replaceAll("heightInk","0x466A9C").replaceAll("if (returning) 178f else 228f + 5f * b","returning ? 178 : 228+5*b").replaceAll("if (returning) 210f + 17f * b else 222f + 14f * b","returning ? 210+17*b : 222+14*b");
const original=calls(source,/\b(callout|axis)\(c, /g).filter(c=>c.args.some(a=>a.includes("R.string")));
const nativeCalls=calls(scene,/\b(thoracicCallout|thoracicAxis)\(/g);
assert.equal(original.length,nativeCalls.length);
for(const call of original){
 const args=call.args.map(aliases);
 if(call.name==="callout")args[0]=args[0].replace("R.string.health_atlas_",'"')+'"';
 else args[args.length-1]=args.at(-1).replace("R.string.health_atlas_",'"')+'"';
 const expected=args.map(s=>norm(s.replace("below =","below:"))).join(",");
 assert(nativeCalls.some(c=>c.args.map(norm).join(",")===expected),call.name+":"+expected);
}
for(const key of new Set([...source.matchAll(/R.string.health_atlas_(\w+)/g)].map(m=>m[1]))){
 assert(all.includes('"'+key+'"'),key);
 for(const lang of ["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),lang+":"+key);
}
const ease=t=>t*t*(3-2*t),fx=(x,b)=>x+Math.max(0,x-13)*.14*b,fy=(x,y,b)=>y-(6+Math.max(0,x-13)*.045)*b;
for(const t of [0,.1,.25,.5,.9,1]){assert(Math.abs(ease(t)+ease(1-t)-1)<1e-12);}
assert.equal(fx(13,1),13);assert.equal(fx(118,1),132.7);assert.equal(fy(118,200,1),189.275);
for(const b of [0,.2,.5,1])for(let i=0;i<7;i++){
 const px=107+.8*i,py=73+16*i,dx=207+4.5*i-px,dy=101+17*i-py,angle=-8*b*Math.PI/180;
 const x=dx*Math.cos(angle)-dy*Math.sin(angle),y=dx*Math.sin(angle)+dy*Math.cos(angle);
 assert(Math.abs(Math.hypot(x,y)-Math.hypot(dx,dy))<1e-10);
}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="THORACIC_FRAME");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["ribs","sternum"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["frame","pump","bucket","expand","recoil"]);
assert.equal(story.references.length,4);assert.deepEqual(story.related,[{entryID:"lungs",storyID:"BREATHING"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "THORACIC_FRAME": GalaxySSIHealthAtlasThoracicView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 thoracic frame: 15 exact geometry templates, 12 paired ribs/shared margin, stationary pivots/bridging cartilage, cutaway contours, motion rules/axes/bilingual anchors checked; no native compilation/pixels verified.");
