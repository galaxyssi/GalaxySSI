// Static source/resource audit only; not native drawing, XCTest or Swift type checking.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const cp=require("node:child_process"),xml=require("xml-js"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="3aa202bc663c6d15bc8085a6af965b461f620899";
const baseline="bf82ac10a81a6d211d6d6098f3489d32538bb36a";
const file="apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmuneCells.dataset/content.json";
const show=(ref,file)=>cp.execFileSync("git",["show",ref+":"+file],{cwd:root,maxBuffer:16_000_000});
const local=file=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",file),"utf8");
(async()=>{
  cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-immune.cjs")],{cwd:root,stdio:"inherit"});
  const pack=JSON.parse(fs.readFileSync(path.join(root,file))),old=JSON.parse(show(baseline,file));
  assert.deepEqual(pack.granulocyteArtworkSource,{androidPR:4366,mergeCommit:sha});
  const kotlin=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasImmunePlates.kt").toString();
  const features=[...kotlin.matchAll(/paintedFeature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)]
    .map(m=>({marker:{id:m[1],x:Number(m[2])/1254,y:Number(m[3])/1254},title:m[4],explanation:m[5]}));
  assert.equal(features.length,8);
  const semantic=structuredClone(pack);delete semantic.granulocyteArtworkSource;
  for(const id of ["cell-eosinophil","cell-basophil"]){
    const plate=pack.plates.find(p=>p.owner===id),previous=old.plates.find(p=>p.owner===id);
    assert.equal(plate.aspectRatio,1);
    assert.deepEqual(plate.features,features.filter(f=>plate.features.some(p=>p.marker.id===f.marker.id)));
    const dir=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",plate.asset+".imageset");
    const png=fs.readFileSync(path.join(dir,"cell.png"));assert(png.equals(show(sha,plate.drawable)));
    const info=await sharp(png).metadata();assert.equal(info.width,1254);assert.equal(info.height,1254);assert(info.hasAlpha);
    const rgba=await sharp(png).ensureAlpha().raw().toBuffer(),alpha=(x,y)=>rgba[(y*1254+x)*4+3];
    for(const x of [0,1253])for(const y of [0,1253])assert(alpha(x,y)<=4);
    for(const feature of plate.features)assert(alpha(Math.floor(feature.marker.x*1254),Math.floor(feature.marker.y*1254))>200,feature.marker.id);
    const restored=semantic.plates.find(p=>p.owner===id);
    restored.aspectRatio=previous.aspectRatio;restored.drawable=previous.drawable;
    for(const feature of restored.features)feature.marker=previous.features.find(f=>f.marker.id===feature.marker.id).marker;
  }
  assert.deepEqual(semantic,old,"Other metadata and feature identities/text remain unchanged");
  const keys=["health_atlas_granulocyte_stage","health_atlas_neutrophil_scope","health_atlas_eosinophil_scope","health_atlas_basophil_scope"];
  for(const [language,directory] of [["en","values"],["zh-Hans","values-zh"]]){
    const strings=xml.xml2js(show(sha,"apps/android/app/src/main/res/"+directory+"/health_atlas_immune_features.xml").toString(),{compact:true}).resources.string;
    const map=new Map();
    for(const line of local(language+".lproj/BodyAtlas.strings").split(/\r?\n/)){
      const m=line.match(/^"([^"]+)" = (".*");$/);if(!m)continue;
      assert(!map.has(m[1]),"Duplicate localized key "+m[1]);map.set(m[1],JSON.parse(m[2]));
    }
    for(const key of keys)assert.equal(map.get(key),strings.find(s=>s._attributes.name===key)._text.replace(/%([0-9]+)\$s/g,"%$1$@"));
  }
  const swift=local("GalaxySSIHealthAtlasGranulocyte.swift");
  const android=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGranulocyteView.kt").toString();
  const pairs=[
    ["76 + 109 * ease","76f + 109f * t"],["57 + 79 * ease","57f + 79f * t"],
    ["1 - 1.1 * ease * (1 - ease)","1f - 1.1f * t * (1f - t)"],["271 - 56 * ease","271f - 56f * t"],
    ["11 + 5 * ease","11f + 5f * t"],["94 + 54 * ease","94f + 54f * t"],
    ["148 + 23 * ease","148f + 23f * t"],["9 * ease","9f * t"],
    ["215 + 24 * t","215f + 24f * t"],["3 + 7 * t","3f + 7f * t"],
    ["166 + t * 88","166f + t * 88f"],["4 + 9 * t","4f + 9f * t"],["215 - t * 8","215f - t * 8f"]
  ];
  for(const [native,source] of pairs){assert(swift.includes(native),native);assert(android.includes(source),source);}
  for(const token of ["GalaxySSIHealthAtlasSectionLesson.Phase(phase)","progress * progress * (3 - 2 * progress)",
    "context.draw(Image(lesson.asset), in: frame.cellBounds)","case .neutrophil: neutrophil","case .eosinophil: eosinophil",
    "case .basophil: basophil","atlas-granulocyte-diagram","health_atlas_granulocyte_stage","size.height / 200"])assert(swift.includes(token),token);
  assert(!swift.includes("Timer")&&!swift.includes("@State")&&!swift.includes("GalaxySSIHealthRecords"));
  const panel=local("GalaxySSIHealthAtlasSimulationPanel.swift"),detail=local("GalaxySSIHealthAtlasDetail.swift");
  assert(panel.includes("GalaxySSIHealthAtlasGranulocyteView(lesson: lesson, phase: simulation.phase, stages: model.stages, language: language)"));
  assert(panel.includes("GalaxySSIHealthAtlasGranulocyte(rawValue: entry.id) == nil"));
  assert(detail.includes("GalaxySSIHealthAtlasGranulocyte(rawValue: entry.id) == nil"));
  const context=local("GalaxySSIHealthAtlasAgentContext.swift"),handoff=local("GalaxySSIHealthAtlasAgentHandoff.swift");
  const scope=context.indexOf("GalaxySSIHealthAtlasGranulocyte(rawValue: anatomy.id)");
  assert(scope>context.indexOf("if screen.includesPhysiology"));assert(scope>context.indexOf("simulation.entryID == anatomy.id"));
  assert(handoff.includes("if let lesson = GalaxySSIHealthAtlasGranulocyte(rawValue: entry.id),"));
  console.log("Android #4366: two original painted cells/four calibrated features, eight exact localized values, three native lesson integrations, source motion formulas and owner/screen-scoped Agent contexts. No native renderer execution.");
})().catch(error=>{console.error(error);process.exitCode=1;});
