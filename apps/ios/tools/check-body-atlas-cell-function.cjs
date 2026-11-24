// Pinned source/resource and reuse checks only; no native compilation or pixels.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const read=p=>fs.readFileSync(path.join(root,p),"utf8"),local=n=>read("apps/ios/GalaxySSI/"+n+".swift");
const show=(ref,p)=>cp.execFileSync("git",["show",ref+":"+p],{cwd:root,maxBuffer:32_000_000});
const android=n=>show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/"+n+".kt").toString();
const before=n=>show("9011726df","apps/ios/GalaxySSI/"+n+".swift").toString();
const norm=s=>s.replace(/\s+/g,"");
function balanced(source,start,open="{",close="}"){
  const at=source.indexOf(open,start);assert(at>=0);
  let depth=0;
  for(let i=at;i<source.length;i++){if(source[i]===open)depth++;if(source[i]===close&&!--depth)return source.slice(at+1,i);}
  assert.fail("Unbalanced source block");
}
function method(source,name){const at=source.indexOf(name);assert(at>=0,name);return balanced(source,at);}
for(const [name,ref]of [
  ["HealthAtlasGranulocyteView","3aa202bc663c6d15bc8085a6af965b461f620899"],
  ["HealthAtlasImmuneLinkView","20de8dd75a18c257e7a8fdba844511d3bd98c37d"],
  ["HealthAtlasBloodDefenseView","26b7b4395a27a74a3f9e3e45db9c46f217c505f9"],
  ["HealthAtlasPhagocytosisView","26b7b4395a27a74a3f9e3e45db9c46f217c505f9"]]){
  const previous=show(ref,"apps/android/app/src/main/java/com/galaxyssi/chat/"+name+".kt").toString();
  const names=name.includes("Granulocyte")?["neutrophil","eosinophil","basophil"]:
    name.includes("ImmuneLink")?["monocyte","dendritic","plasma","antibody","arrow"]:
    name.includes("BloodDefense")?["adaptive","naturalKiller","megakaryocyte","platelet","activePlatelet","ring"]:["target"];
  for(const helper of names){
    const clean=s=>norm(s).replace(/brush/g,"paint");
    assert.equal(clean(method(android(name),"private fun "+helper+"(")),clean(method(previous,"private fun "+helper+"(")),name+"."+helper);
  }
  if(name.includes("Phagocytosis")){
    const clean=s=>norm(s).replace(/brush/g,"paint").replace(/ease/g,"t");
    assert.equal(clean(method(android(name),"when (stage)")),clean(method(previous,"when (stage)")));
  }
}
for(const [view,drawing,first]of [
 ["GalaxySSIHealthAtlasImmuneLink","GalaxySSIHealthAtlasImmuneLinkDrawing","portraits"],
 ["GalaxySSIHealthAtlasBloodDefenseView","GalaxySSIHealthAtlasBloodDefenseDrawing","portrait"]]){
  const original=before(view),current=local(drawing),start="  private func "+first+"(";
  assert.equal(norm(current.slice(current.indexOf(start))),norm(original.slice(original.indexOf(start))),
    "Extracted drawing helpers must remain byte-semantic identical");
  const switchToken="switch lesson";
  const originalSwitch=original.indexOf(switchToken,original.indexOf("var body: some View"));
  assert.equal(norm(method(current,"func drawScene")),norm(switchToken+" {"+balanced(original,originalSwitch)+"}"));
  assert(local(view).includes(drawing+"(lesson: lesson).drawScene(in: drawing, frame: frame)"));
  assert(!current.includes("GalaxySSIHealthAtlasCellSceneRelatedRow"));
}
for(const [name,begin]of [["GalaxySSIHealthAtlasPhagocytosis",'drawing.draw(Image("HealthAtlasImmuneMacrophage")'],["GalaxySSIHealthAtlasGranulocyte","switch lesson"]]){
  const original=before(name),start=original.indexOf(begin,original.indexOf("var body: some View"));
  const end=original.indexOf(name.endsWith("Phagocytosis")?"      }.aspectRatio":"\n      }\n    }\n  }",start);
  assert(start>=0&&end>start);
  assert.equal(norm(method(local(name),"func drawScene")),norm(original.slice(start,end)));
}
const ids=["NEUTROPHIL_DEFENSE","EOSINOPHIL_RESPONSE","BASOPHIL_SIGNALING","MONOCYTE_RECRUITMENT","DENDRITIC_PRESENTATION","T_CELL_RESPONSE","NK_SURVEILLANCE","PLATELET_FORMATION","MACROPHAGE_CLEARANCE"];
const data=JSON.parse(read("apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"));
const registry=local("GalaxySSIHealthAtlasFunctionArtwork"),native=local("GalaxySSIHealthAtlasCellFunctionView");
const enabled=[...registry.match(/implemented: Set<String> = \[([^\]]+)\]/)[1].matchAll(/"([^"]+)"/g)].map(m=>m[1]);
assert.equal(enabled.length,101);assert.deepEqual(new Set(enabled),new Set(data.stories.map(s=>s.id)));
const source=android("HealthAtlasCellFunctionArt"),scene=android("HealthAtlasCellSceneView");
for(const token of ["0xffeaf4f1","8f * resources.displayMetrics.density","scene.drawFrame(canvas, width, height, phase)","HealthAtlasPhagocytosisView.OWNER","HealthAtlasGranulocyte.forId(owner)","HealthAtlasImmuneLink.forId(owner)","HealthAtlasBloodDefense.forId(owner)"])assert(source.includes(token),token);
for(const token of ["width * .56f","maxHeightDp * resources.displayMetrics.density","frameWidth / 360f, frameHeight / 200f","phase * 4f - stage","progress * progress * (3f - 2f * progress)"])assert(scene.includes(token),token);
for(const token of ["width * 0.56 * displayScale","macrophage ? 235 : 240","size.width / 360, size.height / 200","cornerRadius: 8","234.0 / 255, green: 244.0 / 255, blue: 241.0 / 255","Story.safePhase(phase)","story.chapters.count == 4","story.chapters.map(\\.title)"])assert(native.includes(token),token);
assert(!native.includes("Timer")&&!native.includes("onPhase")&&!native.includes("CellSceneRelatedRow"));
const table=new Map(ids.map(id=>[id,data.stories.find(s=>s.id===id)]));
for(const [id,story]of table){
 assert(story,id);assert.equal(story.chapters.length,4);assert.equal(story.durationMs,16000);assert.equal(story.owners.length,1);
 assert(story.showStructurePreview);
 assert(registry.includes('"'+id+'"'));
 const owner=story.owners[0];
 assert(source.includes("renderer(context, story, owner)"));
 assert(owner==="cell-macrophage"||android("HealthAtlasGranulocyteView").includes('"'+owner+'"')||android("HealthAtlasImmuneLinkView").includes('"'+owner+'"')||android("HealthAtlasBloodDefenseView").includes('"'+owner+'"'));
 for(const phase of [0,0.249999,0.25,0.499999,0.5,0.749999,0.75,1]){
  const stage=Math.min(3,Math.trunc(phase*4)),fraction=phase*4-stage,ease=fraction*fraction*(3-2*fraction);
  assert(stage>=0&&stage<4);assert(ease>=0&&ease<=1);
  if(phase===1){assert.equal(stage,3);assert.equal(ease,1);}
 }
}
const pack=JSON.parse(read("apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmuneCells.dataset/content.json"));
for(const plate of pack.plates){
 const original=show(sha,plate.drawable),image=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",plate.asset+".imageset/cell.png"));
 assert(image.equals(original),"Painted source plate "+plate.owner);
}
const pbx=read("apps/ios/GalaxySSI.xcodeproj/project.pbxproj");
for(const name of ["GalaxySSIHealthAtlasImmuneLinkDrawing","GalaxySSIHealthAtlasBloodDefenseDrawing","GalaxySSIHealthAtlasCellFunctionView"]){
 assert.equal(pbx.split("path = "+name+".swift;").length-1,1);
 assert.equal([...pbx.matchAll(new RegExp(name+"\\.swift in Sources \\*/ =","g"))].length,1);
 assert(Buffer.byteLength(local(name))<16*1024);
}
const definitions=[...pbx.matchAll(/^\s*(C4384[0-9A-F]{19}) \/\*[^\n]+\*\/ = \{/gm)].map(m=>m[1]);
assert.equal(new Set(definitions).size,definitions.length);
console.log("Android #4384 CellFunctionArt: nine courses/36 chapters, original 12 PNGs, unchanged dedicated source scenes/shared helpers, four-stage reuse and panel/project wiring. All 101 courses registered; native compilation/pixels unverified.");
