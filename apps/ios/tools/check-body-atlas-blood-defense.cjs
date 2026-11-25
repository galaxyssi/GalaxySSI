// Static core-family resource/source audit, not native drawing or Swift type checking.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const cp=require("node:child_process"),xml=require("xml-js"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="26b7b4395a27a74a3f9e3e45db9c46f217c505f9";
const baseline="90ff0f55891c67c22650abe0de52f3ade4a4ffc5",file="apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmuneCells.dataset/content.json";
const show=(ref,file)=>cp.execFileSync("git",["show",ref+":"+file],{cwd:root,maxBuffer:16_000_000});
const local=file=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",file),"utf8");
(async()=>{
  cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-immune.cjs")],{cwd:root,stdio:"inherit"});
  const pack=JSON.parse(fs.readFileSync(path.join(root,file))),old=JSON.parse(show(baseline,file));
  assert.deepEqual(pack.bloodDefenseArtworkSource,{androidPR:4368,mergeCommit:sha});
  const semantic=structuredClone(pack);delete semantic.bloodDefenseArtworkSource;
  const revised=["cell-t-cell","cell-b-cell","cell-natural-killer-cell","cell-megakaryocyte","fragment-platelet"];
  for(const id of revised){
    const p=semantic.plates.find(p=>p.owner===id),before=old.plates.find(p=>p.owner===id);
    p.aspectRatio=before.aspectRatio;p.drawable=before.drawable;
    for(const feature of p.features)feature.marker=before.features.find(f=>f.marker.id===feature.marker.id).marker;
  }
  assert.deepEqual(semantic,old,"No unrelated metadata, feature title or identity changes");
  const kotlin=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasImmunePlates.kt").toString();
  let count=0;
  for(const plate of pack.plates){
    assert.equal(plate.aspectRatio,1);assert(plate.drawable.endsWith(".png"));
    const start=kotlin.indexOf('plate("'+plate.owner+'"'),next=kotlin.indexOf("\n        plate(",start+1);
    const block=kotlin.slice(start,next<0?kotlin.indexOf("\n    )",start):next);assert(start>=0);
    const features=[...block.matchAll(/paintedFeature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)]
      .map(m=>({marker:{id:m[1],x:Number(m[2])/1254,y:Number(m[3])/1254},title:m[4],explanation:m[5]}));
    assert.deepEqual(plate.features,features,plate.owner);count+=features.length;
    const dir=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",plate.asset+".imageset"),png=fs.readFileSync(path.join(dir,"cell.png"));
    assert(png.equals(show(sha,plate.drawable)),plate.owner);
    const info=await sharp(png).metadata();assert.equal(info.width,1254);assert.equal(info.height,1254);assert(info.hasAlpha);
    const rgba=await sharp(png).ensureAlpha().raw().toBuffer(),alpha=(x,y)=>rgba[(y*1254+x)*4+3];
    for(const x of [0,1253])for(const y of [0,1253])assert(alpha(x,y)<=4);
    for(const feature of features)assert(alpha(Math.floor(feature.marker.x*1254),Math.floor(feature.marker.y*1254))>200,feature.marker.id);
  }
  assert.equal(count,25);
  const base=JSON.parse(local("body-atlas/body-atlas.json")),extended=JSON.parse(local("Assets.xcassets/HealthAtlasExtendedCells.dataset/content.json"));
  for(const data of [base,extended])assert.equal(data.entries.find(e=>e.id==="fragment-platelet").kind,"fragment");
  const platelet=pack.plates.find(p=>p.owner==="fragment-platelet");
  assert(platelet.features.some(f=>f.marker.id==="anucleate"));assert(!platelet.features.some(f=>f.marker.id.includes("nucleus")));
  const keys=["health_atlas_t_lesson_scope","health_atlas_b_lesson_scope","health_atlas_nk_lesson_scope","health_atlas_mega_lesson_scope","health_atlas_platelet_lesson_scope"];
  for(const [language,directory] of [["en","values"],["zh-Hans","values-zh"]]){
    const strings=xml.xml2js(show(sha,"apps/android/app/src/main/res/"+directory+"/health_atlas_immune_features.xml").toString(),{compact:true}).resources.string;
    const map=new Map();
    for(const line of local(language+".lproj/BodyAtlas.strings").split(/\r?\n/)){
      const m=line.match(/^"([^"]+)" = (".*");$/);if(!m)continue;assert(!map.has(m[1]),m[1]);map.set(m[1],JSON.parse(m[2]));
    }
    for(const key of keys)assert.equal(map.get(key),strings.find(s=>s._attributes.name===key)._text);
  }
  const model=local("GalaxySSIHealthAtlasBloodDefense.swift"),view=local("GalaxySSIHealthAtlasBloodDefenseView.swift")+local("GalaxySSIHealthAtlasBloodDefenseDrawing.swift");
  const android=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasBloodDefenseView.kt").toString();
  const pairs=[["83 + 26 * ease","83f + 26f * t"],["48 - ease * 16","48f - t * 16f"],
    ["112 + 34 * ease","112f + 34f * t"],["146 + 74 * ease","146f + 74f * t"],["137 + 20 * ease","137f + 20f * t"],
    ["65 + 29 * ease","65f + 29f * t"],["85 + 25 * ease","85f + 25f * t"],["75 + ease * 48","75f + t * 48f"],
    ["100 - 65 * ease","100f - 65f * t"],["35 - 12 * ease","35f - 12f * t"],
    ["254 - 29 * t","254f - 29f * t"],["224 - t * 73","224f - t * 73f"],
    ["195 + 30 * t","195f + 30f * t"],["radius * 3.75","radius * 3.75f"]];
  for(const [native,source] of pairs){assert((model+view).includes(native),native);assert(android.includes(source),source);}
  for(const token of ["GalaxySSIHealthAtlasCellScene.Frame(phase)",'"fragment-platelet"','return "platelet_lesson_scope"'])assert(model.includes(token),token);
  for(const token of ['identifier: "atlas-blood-defense-diagram"',"case .tCell, .bCell: adaptive","case .naturalKiller: naturalKiller",
    "case .megakaryocyte: megakaryocyte","case .platelet: platelet","GalaxySSIHealthAtlasCellSceneRelatedRow","cos(angle)","sin(angle)"])assert(view.includes(token),token);
  assert(!view.includes("Timer")&&!view.includes("@State"));
  const panel=local("GalaxySSIHealthAtlasSimulationPanel.swift"),detail=local("GalaxySSIHealthAtlasDetail.swift");
  assert(panel.includes("GalaxySSIHealthAtlasBloodDefenseView(atlas: atlas, lesson: lesson, phase: simulation.phase"));
  assert(panel.includes("GalaxySSIHealthAtlasBloodDefense(rawValue: entry.id) == nil"));
  assert(detail.includes("GalaxySSIHealthAtlasBloodDefense(rawValue: entry.id) == nil"));
  const context=local("GalaxySSIHealthAtlasAgentContext.swift"),handoff=local("GalaxySSIHealthAtlasAgentHandoff.swift");
  const offset=context.indexOf("GalaxySSIHealthAtlasBloodDefense(rawValue: anatomy.id)");
  assert(offset>context.indexOf("if screen.includesPhysiology"));assert(offset>context.indexOf("simulation.entryID == anatomy.id"));
  assert(handoff.includes("if let lesson = GalaxySSIHealthAtlasBloodDefense(rawValue: entry.id),"));
  console.log("Android #4368: all 12 original painted core-family PNGs/25 calibrated features, ten localized values, five scene integrations, source motion formulas, fragment identity and scoped context. No native renderer execution.");
})().catch(error=>{console.error(error);process.exitCode=1;});
