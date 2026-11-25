// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasObliqueRotationStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasObliqueGeometry.swift","GalaxySSIHealthAtlasObliqueMotion.swift","GalaxySSIHealthAtlasObliqueBand.swift","GalaxySSIHealthAtlasObliqueAnatomyDrawing.swift","GalaxySSIHealthAtlasObliqueBandDrawing.swift","GalaxySSIHealthAtlasObliqueDirectionDrawing.swift","GalaxySSIHealthAtlasObliqueLabelsDrawing.swift","GalaxySSIHealthAtlasObliqueView.swift"];
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


const geometry=local("GalaxySSIHealthAtlasObliqueGeometry.swift"),motion=local("GalaxySSIHealthAtlasObliqueMotion.swift"),band=local("GalaxySSIHealthAtlasObliqueBand.swift");
const shapes=[...source.matchAll(/private val (\w+) = Path\(\).apply \{([\s\S]*?)\n    \}/g)];
assert.equal(shapes.length,4);
for(const[,name,body]of shapes){
 const native=geometry.match(new RegExp("static let "+name+" = Path \\{ p in([\\s\\S]*?)\\n  \\}"))[1];
 assert.deepEqual(toCommands(native),fromCommands(body),name);
}
assert.equal(fromCommands(shapes.find(m=>m[1]==="pelvis")[2]).filter(c=>c[0]==="close").length,2);
assert(source.includes("fillType = Path.FillType.EVEN_ODD"));
assert(all.includes("0x928572,evenOdd:true)"));assert(all.includes("style:FillStyle(eoFill:evenOdd)"));
assert(geometry.includes("for side in [-1.0,1.0]"));
const expectedTurns=source.match(/private val turns = floatArrayOf\(([^)]+)\)/)[1].split(",").map(s=>Number(norm(s)));
const actualTurns=motion.match(/static let turns: \[Double\] = \[([^\]]+)\]/)[1].split(",").map(Number);
assert.deepEqual(actualTurns,expectedTurns);assert.equal(actualTurns.length,6);
const sourceBlock=n=>source.match(new RegExp("private fun "+n+"\\([\\s\\S]*?\\) \\{([\\s\\S]*?)(?=\\n    private fun)"))[1];
assert.deepEqual(toCommands(band),fromCommands(sourceBlock("band")),"four tapered shapes and strands");
for(const [swift,kotlin]of[
 ["degrees = 27*turn","val degrees = 27f * turn"],
 ["180+x*cos(angle)-y*sin(angle)","centerX + x * cos(a) - y * sin(a)"],
 ["177+x*sin(angle)+y*cos(angle)","centerY + x * sin(a) + y * cos(a)"],
 ["max(1,hypot(dx,dy))","hypot(dx, dy).coerceAtLeast(1f)"],["10+4*effort","10f + 4f * effort"],
 ["(x+2*mx+endX)*0.25","(x + 2f * mx + endX) * .25f"],["(y+2*my+endY)*0.25","(y + 2f * my + endY) * .25f"],
 ["Double(Int(86*(1-effort)))/255","(86f * (1f - effort)).toInt()"],["Double(Int(88*effort))/255","(88f * effort).toInt()"],
 ["0.95+0.25*effort",".95f + .25f * effort"],["step != 4 || t < 0.92","step != 4 || t < .92f"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
const specs=[
 ["CGPoint(x:152,y:108)","rotate(-59,-11)","max(0,turn)","true"],
 ["CGPoint(x:95,y:207)","rotate(-45,-28)","max(0,-turn)","false"],
 ["CGPoint(x:208,y:108)","rotate(59,-11)","max(0,-turn)","true"],
 ["CGPoint(x:265,y:207)","rotate(45,-28)","max(0,turn)","false"]
];
const nativeBands=calls(motion,/\.(init)\(/g).map(c=>c.args.map(norm));assert.deepEqual(nativeBands,specs.map(c=>c.map(norm)));
for(const token of["side * 59f, -11f","side * 45f, -28f","centerX + side * 85f, 207f","centerX + side * 28f, 108f",
 "(-side * turn).coerceAtLeast(0f)","(side * turn).coerceAtLeast(0f)"])assert(source.includes(token),token);
for(const token of[
 "Superior view, anterior up: clockwise turns toward the person's right.","Self.turns[step+1]>Self.turns[step]",
 "for index in [1,0,3,2]","for strand in -1...1","let strand = Double(strand)","(x+endX)/2+(x < 180 ? -10 : 10)",
 "external ? 104 : 140","external ? 178 : 220","external ? 0xEFC9BC : 0xE1D7EB","external ? 0xCF8E94 : 0xAC9DC4",
 "copy(quiet).fill(band.shape,Self.cream)","copy(tone).fill(band.shape,color)",
 "external ? 0xF8DED3 : 0xEEE6F2","c.rotate(by:.degrees(motion.degrees))",
 "let d = motion.right ? 1.0 : -1.0","tip = -90+motion.degrees+8*d","start = tip-22*d",
 "radius:101,startAngle:.degrees(-127),endAngle:.degrees(-53),clockwise:false",
 "let low = min(start,tip)","radius:101,startAngle:.degrees(low),endAngle:.degrees(low+22),clockwise:false",
 "x+8*d*sin(a),y-8*d*cos(a),x,y,Self.blue","ty > y ? y+6 : y-17","label(key,x,y,110)",
 'accessibilityIdentifier("atlas-function-oblique-rotation-art")'
])assert(all.includes(token),token);
const fromLabels=calls(source,/\b(label)\(c, /g).filter(c=>c.args[0].startsWith("R.string"));
const labels=local("GalaxySSIHealthAtlasObliqueLabelsDrawing.swift"),actualLabels=calls(labels,/\b(label)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(fromLabels.length,3);assert.deepEqual(actualLabels.map(c=>c.args.map(norm)),fromLabels.map(c=>c.args.map((v,i)=>norm(i===0?'"'+v.replace("R.string.health_atlas_","")+'"':v))));
const fromLeaders=calls(source,/\b(leader)\(c, /g).filter(c=>c.args[0].startsWith("R.string")),toLeaders=calls(labels,/\b(obliqueLeader)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(fromLeaders.length,5);assert.equal(toLeaders.length,5);
const inks={externalInk:"0x9B5B63",internalInk:"0x665A88",boneInk:"0x928572"};
for(let i=0;i<5;i++){
 const a=fromLeaders[i].args,b=toLeaders[i].args;
 const expectedTarget=i<4?"motion.bands["+[0,2,1,3][i]+"].focus":"CGPoint(x:180,y:244)";
 assert.deepEqual(b.map(norm),['"'+a[0].replace("R.string.health_atlas_","")+'"',...a.slice(1,4),expectedTarget,inks[a[6]]].map(norm));
}
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g)){
 assert(all.includes('"'+key+'"'),key);
 for(const lang of["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
}
for(const turn of[-1,-.5,0,.12,.5,1]){
 const a=27*turn*Math.PI/180,rotate=(x,y)=>[180+x*Math.cos(a)-y*Math.sin(a),177+x*Math.sin(a)+y*Math.cos(a)];
 const efforts=[Math.max(0,turn),Math.max(0,-turn),Math.max(0,-turn),Math.max(0,turn)];
 assert.equal(efforts[0],efforts[3]);assert.equal(efforts[1],efforts[2]);
 for(const[x,y]of[[-59,-11],[-45,-28],[59,-11],[45,-28]]){const p=rotate(x,y);assert(Math.abs(Math.hypot(p[0]-180,p[1]-177)-Math.hypot(x,y))<1e-10);}
 for(const effort of efforts){assert(Math.trunc(86*(1-effort))>=0);assert(Math.trunc(88*effort)<=88);}
}
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="OBLIQUE_ROTATION");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["oblique-abdominal-muscles"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["align","right","center","left","return"]);assert.equal(story.references.length,3);
assert.deepEqual(story.related,[{entryID:"muscle",storyID:"MUSCLE_MOTION"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "OBLIQUE_ROTATION": GalaxySSIHealthAtlasObliqueView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
console.log("Android #4384 oblique: 4 exact fixed paths/even-odd pelvis, superior-view handedness/turn sequence, 4 band shapes and 12 strands, integer-alpha overlays, direction arc and 8 bilingual placements checked; no native compilation/pixels verified.");
