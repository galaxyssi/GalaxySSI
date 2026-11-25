// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasDeltoidStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasDeltoidGeometry.swift","GalaxySSIHealthAtlasDeltoidMotion.swift","GalaxySSIHealthAtlasDeltoidPose.swift","GalaxySSIHealthAtlasDeltoidAnatomyDrawing.swift","GalaxySSIHealthAtlasDeltoidBandDrawing.swift","GalaxySSIHealthAtlasDeltoidSweepDrawing.swift","GalaxySSIHealthAtlasDeltoidLabelsDrawing.swift","GalaxySSIHealthAtlasDeltoidView.swift"];
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


const geometry=local("GalaxySSIHealthAtlasDeltoidGeometry.swift"),motion=local("GalaxySSIHealthAtlasDeltoidMotion.swift"),pose=local("GalaxySSIHealthAtlasDeltoidPose.swift");
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([^}]+)\}/g)];
assert.equal(shapes.length,7);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
for(const name of ["roots","neutralControls","restingEnds"]){
 const expected=source.match(new RegExp("private val "+name+" = floatArrayOf\\(([^)]+)\\)"))[1].split(",").map(s=>Number(norm(s)));
 const actual=[...motion.match(new RegExp("static let "+name+": \\[CGPoint\\] = \\[([^\\n]+)"))[1].matchAll(/[xy]: ([^,)]+)/g)].map(m=>Number(m[1]));
 assert.equal(expected.length,8);assert.deepEqual(actual,expected,name);
}
const sourceBlock=n=>source.match(new RegExp("private fun "+n+"\\([^\\n]*\\) \\{([\\s\\S]*?)(?=\\n    private fun)"))[1];
const anatomy=local("GalaxySSIHealthAtlasDeltoidAnatomyDrawing.swift"),sweep=local("GalaxySSIHealthAtlasDeltoidSweepDrawing.swift");
assert.deepEqual(toCommands(anatomy),fromCommands(sourceBlock("drawClavicle")),"deforming clavicle");
assert.deepEqual(toCommands(sweep),fromCommands(sourceBlock("drawSweep")),"moving lift/lower sweep");
for(const [swift,kotlin] of [
 ["0.36*ease",".36f * ease"],["0.36+0.64*ease",".36f + .64f * ease"],["1-ease","1f - ease"],
 ["-33*pose*(0.45+0.55*pose)","-33f * pose * (.45f + .55f * pose)"],
 ["Self.rotation(bladeTurn, 157, 141, 5*pose, -4*pose)","scapulaPose.postTranslate(5f * pose, -4f * pose)"],
 ["Self.rotation(-119*pose, 204, 142, head.x-204, head.y-142)","armPose.postTranslate(head[0] - 204f, head[1] - 142f)"],
 ["pose*(17-2*Double(i))","pose * (17f - 2f * i)"],["pose*(18+5*Double(i))","pose * (18f + 5f * i)"],
 ["M.blend(-14+5.3*Double(i), -16, pose)","blend(-14f + 5.3f * i, -16f, pose)"],["M.blend(-13, 4, pose)","blend(-13f, 4f, pose)"],
 ["max(0, 1-abs(3*t-Double(band)-0.5))","(1f - kotlin.math.abs(3f * t - band - .5f)).coerceAtLeast(0f)"],
 ["Double(Int(180*focus))/255","(180f * focus).toInt()"],["x-2*pose","x - 2f * pose"],["y-4*(1-pose)","y - 4f * (1f - pose)"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
const band=local("GalaxySSIHealthAtlasDeltoidBandDrawing.swift"),labels=local("GalaxySSIHealthAtlasDeltoidLabelsDrawing.swift");
for(const token of [
 "case 3: return 1-ease","default: return 0","Overlapping teaching poses, not measured joint angles or recruitment phases.",
 "origins = M.roots.map { $0.applying(blade) }","let ends = M.restingEnds.map { $0.applying(arm) }",
 "CGPoint(x: 204, y: 142).applying(blade)","CGPoint(x: 138, y: 170).applying(blade)","CGPoint(x: 226, y: 117).applying(blade)",
 "tx: px-px*c+py*s+dx, ty: py-px*s-py*c+dy","blade.concatenate(frame.scapula)","arm.concatenate(frame.arm)",
 "let l = band, r = band+1","for band in 0...2","for row in 1...4","Double(row)/5",
 "p.move(to: o[l]); p.addCurve(to: e[l], control1: c[l], control2: v[l])",
 "p.addLine(to: e[r]); p.addCurve(to: o[r], control1: v[r], control2: c[r])",
 "0.85+0.85*reveal+(step == 1 && band == 1 ? 0.65*pose : 0)",
 "row % 2 == 0 ? 0xAAFFF4F7 : m.fiberInks[band]","lowering: step == 3","if step >= 2",
 "frame.ends[2].x, frame.ends[2].y","m.blend(frame.origins[band].x,frame.origins[band+1].x,0.53)",
 "m.blend(frame.origins[band].y,frame.origins[band+1].y,0.53)+3",
 "ty > y ? y+7 : y-17","disc(tx,ty,3,color,border: Self.cream)","label(key,x,y,124)",
 "let start = angle+(lowering ? -0.2 : 0.2), tip = angle+(lowering ? 0.16 : -0.16)",
 "let nearTip = tip+(lowering ? -0.08 : 0.08)",'accessibilityIdentifier("atlas-function-deltoid-lift-art")'
])assert(all.includes(token),token);
const gradients=[...source.match(/private val cap = arrayOf\(([\s\S]*?)\n    \)/)[1].matchAll(/shade\(([^)]+)\)/g)].map(m=>m[1].split(",").map(s=>norm(s).replace("0xff","0x").toUpperCase()));
const actual=[...band.matchAll(/\(([\d]+),([\d]+),(0x[\dA-F]+),(0x[\dA-F]+)\)/g)].map(m=>m.slice(1).map(s=>s.toUpperCase()));
assert.equal(gradients.length,3);assert.deepEqual(actual,gradients,"three world-space cap gradients");
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g)){
 assert(all.includes('"'+key+'"'),key);
 for(const lang of ["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
}
const originalParts=calls(source,/\b(partCallout)\(c, /g),actualParts=calls(labels,/\b(deltoidPart)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(originalParts.length,3);
assert.deepEqual(actualParts.map(c=>c.args.slice(0,-1).map(norm)),originalParts.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v))));
const rotate=(p,angle,center,shift)=>{const a=angle*Math.PI/180,c=Math.cos(a),s=Math.sin(a);return [center[0]+(p[0]-center[0])*c-(p[1]-center[1])*s+shift[0],center[1]+(p[0]-center[0])*s+(p[1]-center[1])*c+shift[1]];};
const matrix=(p,angle,center,shift)=>{const a=angle*Math.PI/180,c=Math.cos(a),s=Math.sin(a),[px,py]=center,[dx,dy]=shift;return [c*p[0]-s*p[1]+px-px*c+py*s+dx,s*p[0]+c*p[1]+py-px*s-py*c+dy];};
const roots=[148,129,186,112,216,109,231,124],ends=[211,224,214,225,217,225,220,223];
for(const pose of [0,.18,.36,.6,1]){
 const turn=-33*pose*(.45+.55*pose),head=rotate([204,142],turn,[157,141],[5*pose,-4*pose]);
 const mappedHead=rotate([204,142],-119*pose,[204,142],[head[0]-204,head[1]-142]);
 assert(Math.hypot(mappedHead[0]-head[0],mappedHead[1]-head[1])<1e-10);
 for(let i=0;i<4;i++){
  const p=roots.slice(i*2,i*2+2),a=rotate(p,turn,[157,141],[5*pose,-4*pose]),b=matrix(p,turn,[157,141],[5*pose,-4*pose]);
  assert(Math.hypot(a[0]-b[0],a[1]-b[1])<1e-10);
  const ep=ends.slice(i*2,i*2+2),mapped=matrix(ep,-119*pose,[204,142],[head[0]-204,head[1]-142]);
  assert(Math.abs(Math.hypot(mapped[0]-head[0],mapped[1]-head[1])-Math.hypot(ep[0]-204,ep[1]-142))<1e-10);
 }
}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="DELTOID_LIFT");
assert.equal(story.durationMs,16000);assert.deepEqual(story.owners,["deltoid"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["parts","lift","coordinate","return"]);assert.equal(story.references.length,4);
assert.deepEqual(story.related,[{entryID:"trapezius",storyID:"SCAPULAR_ROTATION"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "DELTOID_LIFT": GalaxySSIHealthAtlasDeltoidView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 deltoid: 4 source chapters, 7 fixed paths, exact clavicle/sweep, 12 anchor/control points, separate rigid transforms, attached cap bands/fibers and bilingual focus checked; no native compilation/pixels verified.");
