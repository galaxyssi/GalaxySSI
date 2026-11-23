// Pinned resource/source checks, not native drawing, XCTest or Swift type checking.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const cp=require("node:child_process"),xml=require("xml-js"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="20de8dd75a18c257e7a8fdba844511d3bd98c37d";
const baseline="82ee72583d452f44b8563bd5d74f344a2ee75fbb",file="apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmuneCells.dataset/content.json";
const show=(ref,file)=>cp.execFileSync("git",["show",ref+":"+file],{cwd:root,maxBuffer:16_000_000});
const local=file=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",file),"utf8");
(async()=>{
  cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-immune.cjs")],{cwd:root,stdio:"inherit"});
  const pack=JSON.parse(fs.readFileSync(path.join(root,file))),old=JSON.parse(show(baseline,file));
  assert.deepEqual(pack.immuneLinkArtworkSource,{androidPR:4367,mergeCommit:sha});
  const kotlin=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasImmunePlates.kt").toString();
  const expected=[...kotlin.matchAll(/paintedFeature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)]
    .map(m=>({marker:{id:m[1],x:Number(m[2])/1254,y:Number(m[3])/1254},title:m[4],explanation:m[5]}));
  assert.equal(expected.length,15);
  const semantic=structuredClone(pack);delete semantic.immuneLinkArtworkSource;delete semantic.bloodDefenseArtworkSource;
  for(const id of ["cell-t-cell","cell-b-cell","cell-natural-killer-cell","cell-megakaryocyte","fragment-platelet"]){
    const restored=semantic.plates.find(p=>p.owner===id),previous=old.plates.find(p=>p.owner===id);
    restored.aspectRatio=previous.aspectRatio;restored.drawable=previous.drawable;
    for(const feature of restored.features)feature.marker=previous.features.find(f=>f.marker.id===feature.marker.id).marker;
  }
  let features=0;
  for(const id of ["cell-monocyte","cell-dendritic-cell","cell-plasma-cell"]){
    const plate=pack.plates.find(p=>p.owner===id),previous=old.plates.find(p=>p.owner===id);
    assert.equal(plate.aspectRatio,1);
    assert.deepEqual(plate.features,expected.filter(f=>plate.features.some(p=>p.marker.id===f.marker.id)));
    const dir=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",plate.asset+".imageset"),png=fs.readFileSync(path.join(dir,"cell.png"));
    assert(png.equals(show(sha,plate.drawable)));
    const info=await sharp(png).metadata();assert.equal(info.width,1254);assert.equal(info.height,1254);assert(info.hasAlpha);
    const rgba=await sharp(png).ensureAlpha().raw().toBuffer(),alpha=(x,y)=>rgba[(y*1254+x)*4+3];
    for(const x of [0,1253])for(const y of [0,1253])assert(alpha(x,y)<=4);
    for(const feature of plate.features){assert(alpha(Math.floor(feature.marker.x*1254),Math.floor(feature.marker.y*1254))>200,feature.marker.id);features++;}
    const restored=semantic.plates.find(p=>p.owner===id);
    restored.aspectRatio=previous.aspectRatio;restored.drawable=previous.drawable;
    for(const feature of restored.features)feature.marker=previous.features.find(f=>f.marker.id===feature.marker.id).marker;
  }
  assert.equal(features,7);assert.deepEqual(semantic,old,"No other metadata/feature identity changes");
  const keys=["health_atlas_monocyte_lesson_scope","health_atlas_dendritic_lesson_scope","health_atlas_plasma_lesson_scope"];
  for(const [language,directory] of [["en","values"],["zh-Hans","values-zh"]]){
    const strings=xml.xml2js(show(sha,"apps/android/app/src/main/res/"+directory+"/health_atlas_immune_features.xml").toString(),{compact:true}).resources.string;
    const map=new Map();
    for(const line of local(language+".lproj/BodyAtlas.strings").split(/\r?\n/)){
      const m=line.match(/^"([^"]+)" = (".*");$/);if(!m)continue;assert(!map.has(m[1]),m[1]);map.set(m[1],JSON.parse(m[2]));
    }
    for(const key of keys)assert.equal(map.get(key),strings.find(s=>s._attributes.name===key)._text);
  }
  const swift=local("GalaxySSIHealthAtlasImmuneLink.swift"),scene=local("GalaxySSIHealthAtlasCellScene.swift");
  const android=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasImmuneLinkView.kt").toString();
  const pairs=[["64 + 85 * ease","64f + 85f * t"],["149 + 94 * ease","149f + 94f * t"],["55 + 89 * ease","55f + 89f * t"],
    ["1 - 1.1 * ease * (1 - ease)","1f - 1.1f * t * (1f - t)"],["254 - 20 * ease","254f - 20f * t"],
    ["296 - 73 * t","296f - 73f * t"],["3 + 4 * t","3f + 4f * t"],["190 + t * (79 + i * 4)","190f + t * (79f + index * 4f)"],
    ["237 + 12 * t","237f + 12f * t"],["0.25 + 0.75 * ease",".25f + .75f * progress"]];
  for(const [native,source] of pairs){assert(swift.includes(native),native);assert(android.includes(source),source);}
  for(const [id,target,asset] of [["cell-monocyte","cell-macrophage","HealthAtlasImmuneMacrophage"],
    ["cell-dendritic-cell","cell-t-cell","HealthAtlasImmuneTCell"],["cell-plasma-cell","cell-b-cell","HealthAtlasImmuneBCell"]]){
    assert(swift.includes('"'+id+'"'));assert(swift.includes('return "'+target+'"'));assert(swift.includes('return "'+asset+'"'));
    assert(pack.plates.some(p=>p.owner===target&&p.asset===asset));
  }
  for(const token of ["Gallery", "Timer", "@State"])assert(!swift.includes(token));
  for(const token of ["GalaxySSIHealthAtlasCellScene.Frame(phase)",'identifier: "atlas-immune-link-diagram"',
    'GalaxySSIHealthAtlasCellSceneRelatedRow(atlas: atlas, entryID: lesson.relatedID'])assert(swift.includes(token),token);
  for(const token of ['atlas.entry(entryID)','Button { open(related.id) }','"atlas-immune-related-" + related.id'])assert(scene.includes(token),token);
  const base=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasCellSceneView.kt").toString();
  assert(base.includes("200f / maxOf(width, height)"));assert(base.includes("progress * progress * (3f - 2f * progress)"));
  for(const token of ["GalaxySSIHealthAtlasSectionLesson.Phase(phase)","progress * progress * (3 - 2 * progress)",
    "size.height / 200","floor(100 * min(1, aspectRatio))","floor(100 * min(1, 1 / aspectRatio))",
    "UIImage(named: asset)","health_atlas_granulocyte_stage"])assert(scene.includes(token),token);
  const panel=local("GalaxySSIHealthAtlasSimulationPanel.swift"),detail=local("GalaxySSIHealthAtlasDetail.swift");
  assert(panel.includes("GalaxySSIHealthAtlasImmuneLinkView(atlas: atlas, lesson: lesson, phase: simulation.phase"));
  assert(panel.includes("open: { playing = false; structure = $0 }"));
  assert(panel.includes("GalaxySSIHealthAtlasImmuneLink(rawValue: entry.id) == nil"));
  assert(detail.includes("GalaxySSIHealthAtlasImmuneLink(rawValue: entry.id) == nil"));
  const context=local("GalaxySSIHealthAtlasAgentContext.swift"),handoff=local("GalaxySSIHealthAtlasAgentHandoff.swift");
  const offset=context.indexOf("GalaxySSIHealthAtlasImmuneLink(rawValue: anatomy.id)");
  assert(offset>context.indexOf("if screen.includesPhysiology"));assert(offset>context.indexOf("simulation.entryID == anatomy.id"));
  assert(handoff.includes("if let lesson = GalaxySSIHealthAtlasImmuneLink(rawValue: entry.id),"));
  console.log("Android #4367: three exact painted cells, seven feature anchors, six localized values, three canonical destinations, shared scene fitting/playhead and source motion/scope integration. No native rendering executed.");
})().catch(error=>{console.error(error);process.exitCode=1;});
