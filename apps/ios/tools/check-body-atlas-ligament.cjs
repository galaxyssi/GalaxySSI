// Pinned source/curve/formula checks only; not Swift type checking or native pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasLigamentGuidanceStoryView.kt"],{cwd:root,encoding:"utf8"});
const names=["GalaxySSIHealthAtlasLigamentPlate.swift","GalaxySSIHealthAtlasLigamentDrawing.swift","GalaxySSIHealthAtlasLigamentView.swift"];
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


const plate=local("GalaxySSIHealthAtlasLigamentPlate.swift"),drawing=local("GalaxySSIHealthAtlasLigamentDrawing.swift");
const originalPlate=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasLigamentsPlate.kt"],{cwd:root,encoding:"utf8"});
const anchors=Object.fromEntries([...originalPlate.matchAll(/val (\w+) = anchor\("[^"]+", (\d+), (\d+)\)/g)].map(m=>[m[1],[+m[2],+m[3]]]));
assert.equal(Object.keys(anchors).length,5);
for(const[name,xy]of Object.entries(anchors)){
 const match=plate.match(new RegExp("static let "+name+" = CGPoint\\(x:([^,]+),y:([^)]+)\\)"));
 assert(match,name);assert.deepEqual(match.slice(1).map(Number),xy,name);
}
for(const[key,name]of[["PLATE_WIDTH","width"],["PLATE_HEIGHT","height"],["PLATE_TOP","top"]]){
 const from=Number(source.match(new RegExp("const val "+key+" = (\\d+)"))[1]);
 const to=Number(plate.match(new RegExp("\\b"+name+" = ([\\d.]+)"))[1]);assert.equal(to,from,name);
}
assert(plate.includes("CGPoint(x:point.x,y:point.y+top)"));
const originalCalls=calls(source,/\b(callout)\(c, /g).filter(c=>c.args[0].startsWith("R.string"));
const nativeCalls=calls(drawing,/\b(ligamentCallout)\(/g).filter(c=>c.args[0].startsWith('"'));
assert.equal(originalCalls.length,4);assert.equal(nativeCalls.length,4);
const colors={boneInk:"0x886E59",aclInk:"0x30756C",pclInk:"0x77587A"};
const coord=(s,axis)=>{const m=s.match(/^[xy]\(plate\.(\w+)\)$/);return m?anchors[m[1]][axis]+(axis===1?8:0):Number(norm(s));};
const target=s=>{
 let m=s.match(/^plate.display\(plate\.(\w+)\)$/);if(m)return [anchors[m[1]][0],anchors[m[1]][1]+8];
 m=s.match(/^CGPoint\(x:([^,]+),y:([^)]+)\)$/);assert(m,s);return m.slice(1).map(Number);
};
for(let i=0;i<4;i++){
 const a=originalCalls[i].args,b=nativeCalls[i].args;
 assert.deepEqual([b[0],...b.slice(1,5).map(norm),...target(b[5]),b[6]],
 ['"'+a[0].replace("R.string.health_atlas_","")+'"',...a.slice(1,5).map(norm),coord(a[5],0),coord(a[6],1),colors[a[7]]]);
}
for(const[swift,kotlin]of[
 ["phase*phase*(3-2*phase)","phase * phase * (3f - 2f * phase)"],
 ["Double(Int(196-76*focus))/255","(196f - 76f * focus).toInt()"],
 ["4.5+4.5*focus","4.5f + 4.5f * focus"],["1.55+1.45*focus","1.55f + 1.45f * focus"]
]){assert(norm(all).includes(norm(swift)),swift);assert(norm(source).includes(norm(kotlin)),kotlin);}
for(const token of [
 '(1...2).contains(step) || step == 4 ? emphasis : nil',
 'step == 1 || (3...4).contains(step) ? emphasis : nil',
 'let acl: Double?', 'let pcl: Double?', 'guard let focus else { return }',
 'ligamentFootprint(plate.aclFemur,0x30756C,acl)','ligamentFootprint(plate.aclTibia,0x30756C,acl)',
 'ligamentFootprint(plate.pclFemur,0x77587A,pcl)','ligamentFootprint(plate.pclTibia,0x77587A,pcl)',
 'if step >= 2','if step >= 3','if step == 2 || step == 4',
 'ligamentRestraint(159,83,0x77587A,emphasis,"ligament_guidance_story_backward_slide")',
 'ligamentRestraint(201,277,0x30756C,emphasis,"ligament_guidance_story_forward_slide")',
 'tip = stop-direction*8','arrow(from,319,tip,319,color)',
 'line(stop,313,stop,325,color,1.55+1.45*focus)',
 'label(key,(from+stop)/2,341,136)','label(key,x,y,77)',
 'line(31,283,329,283,0xADC1BA,1)','label("ligament_guidance_story_direction_key",180,302,306)',
 'disc(p.x,p.y,2.55,color,border:Self.cream)',
 'Fixed arrows show the checked direction, not force or tibial displacement.',
 'Image("HealthAtlasFunctionLigaments")','CGRect(x:0,y:plate.top,width:plate.width,height:plate.height)',
 'accessibilityIdentifier("atlas-function-ligament-guidance-art")'
])assert(all.includes(token),token);
for(const[,key]of source.matchAll(/R.string.health_atlas_(\w+)/g)){
 assert(all.includes('"'+key+'"'),key);
 for(const lang of["en","zh-Hans"])assert(local(lang+".lproj/AtlasFunction.strings").includes('"health_atlas_'+key+'"'),key);
}
const acl=[false,true,true,false,true],pcl=[false,true,false,true,true];
for(let step=0;step<5;step++){
 assert.equal((step>=1&&step<=2)||step===4,acl[step]);assert.equal(step===1||(step>=3&&step<=4),pcl[step]);
 for(const phase of[0,.25,.5,.75,1]){
  const focus=phase*phase*(3-2*phase),alpha=Math.trunc(196-76*focus),radius=4.5+4.5*focus;
  assert(alpha>=120&&alpha<=196&&radius>=4.5&&radius<=9);
 }
}
assert.equal(83-(-1)*8,91);assert.equal(277-1*8,269);
const data=JSON.parse(local("Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")),story=data.stories.find(s=>s.id==="LIGAMENT_GUIDANCE");
assert.equal(story.durationMs,20000);assert.deepEqual(story.owners,["ligaments"]);
assert.deepEqual(story.chapters.map(c=>c.title.split("_").pop()),["connect","cross","anterior","posterior","coordinate"]);
assert.equal(story.references.length,4);for(const ref of story.references)assert(originalPlate.includes(ref.url),ref.url);
assert.deepEqual(story.related,[{entryID:"joints",storyID:"KNEE_ARTICULATION"}]);
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "LIGAMENT_GUIDANCE": GalaxySSIHealthAtlasLigamentView'));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of names){assert.equal(pbx.split("path = "+name+";").length-1,1,name);assert.equal(pbx.split(name+" in Sources").length-1,2,name);assert(Buffer.byteLength(local(name))<16000,name);}
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-ligaments"],{cwd:root,stdio:"inherit"});
console.log("Android #4384 ligaments: 5 source chapters, exact plate-space anchors/4 callouts, optional ACL/PCL emphasis and fixed restraint cues, original vector plate and bilingual labels checked; no native compilation/pixels verified.");
