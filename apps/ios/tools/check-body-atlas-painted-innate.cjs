// Static bitmap/source parity, not Swift type checking or native renderer execution.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const cp=require("node:child_process"),sharp=require("sharp"),root=path.resolve(__dirname,"../../..");
const sha="8ac01038b80a341c2c2f4912a455e834cd434daf",baseline="c68e8e71c1b819e0b316fec79d884e046e768485";
const show=(ref,file)=>cp.execFileSync("git",["show",ref+":"+file],{cwd:root,maxBuffer:16_000_000});
const file="apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasImmuneCells.dataset/content.json";
const read=file=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",file),"utf8");
(async()=>{
  cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-immune.cjs")],{cwd:root,stdio:"inherit"});
  const pack=JSON.parse(fs.readFileSync(path.join(root,file))),old=JSON.parse(show(baseline,file));
  assert.deepEqual(pack.artworkSource,{androidPR:4365,mergeCommit:sha});
  const kotlin=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasImmunePlates.kt").toString();
  const expected=[...kotlin.matchAll(/paintedFeature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)]
    .map(m=>({marker:{id:m[1],x:Number(m[2])/1254,y:Number(m[3])/1254},title:m[4],explanation:m[5]}));
  assert.equal(expected.length,4);
  const semantic=structuredClone(pack);delete semantic.artworkSource;delete semantic.granulocyteArtworkSource;
  // Later #4366 artwork has its own pinned audit; retain the original #4365 scope here.
  for(const id of ["cell-eosinophil","cell-basophil"]){
    const restored=semantic.plates.find(p=>p.owner===id),previous=old.plates.find(p=>p.owner===id);
    restored.aspectRatio=previous.aspectRatio;restored.drawable=previous.drawable;
    for(const feature of restored.features) feature.marker=previous.features.find(f=>f.marker.id===feature.marker.id).marker;
  }
  let anchors=0;
  for(const id of ["cell-neutrophil","cell-macrophage"]){
    const plate=pack.plates.find(p=>p.owner===id),previous=old.plates.find(p=>p.owner===id);
    assert.equal(plate.aspectRatio,1);
    assert.deepEqual(plate.features,expected.filter(f=>plate.features.some(p=>p.marker.id===f.marker.id)));
    const dir=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",plate.asset+".imageset"),png=fs.readFileSync(path.join(dir,"cell.png"));
    assert(png.equals(show(sha,plate.drawable)));
    const info=await sharp(png).metadata();assert.equal(info.width,1254);assert.equal(info.height,1254);assert(info.hasAlpha);
    const rgba=await sharp(png).ensureAlpha().raw().toBuffer(),alpha=(x,y)=>rgba[(y*1254+x)*4+3];
    for(const x of [0,1253])for(const y of [0,1253])assert(alpha(x,y)<=4);
    for(const feature of plate.features){assert(alpha(Math.floor(feature.marker.x*1254),Math.floor(feature.marker.y*1254))>200,feature.marker.id);anchors++;}
    const restored=semantic.plates.find(p=>p.owner===id);
    restored.aspectRatio=previous.aspectRatio;restored.drawable=previous.drawable;restored.features=previous.features;
  }
  assert.equal(anchors,4);assert.deepEqual(semantic,old,"All other metadata/feature definitions remain unchanged");
  const swift=read("GalaxySSIHealthAtlasPhagocytosis.swift"),panel=read("GalaxySSIHealthAtlasSimulationPanel.swift");
  assert(panel.includes("GalaxySSIHealthAtlasPhagocytosis(phase: simulation.phase, stages: model.stages, language: language)"));
  assert(!swift.includes("Timer")&&!swift.includes("@State")&&!swift.includes("Self.outline"));
  for(const source of ['GalaxySSIHealthAtlasSectionLesson.Phase(phase)','stage = value.stage; progress = value.fraction',
    'progress * progress * (3 - 2 * progress)','298 - ease * 80 : 218 - ease * 62','15 + ease * 8',
    'Double(Int(70 + ease * 185)) / 255','[4.5 - ease * 2, 4 - ease * 2, 3.5 - ease * 2]','ease * 18',
    'drawing.draw(Image("HealthAtlasImmuneMacrophage"), in: CGRect(x: 17, y: -22, width: 244, height: 244))',
    'size.height / 200','switch frame.stage','Self.label(stage: frame.stage','atlas-phagocytosis-diagram']) assert(swift.includes(source),source);
  const android=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasPhagocytosisView.kt").toString();
  for(const source of ["setBounds(17, -22, 261, 222)","phase * 4f - stage","progress * progress * (3f - 2f * progress)",
    "298f - ease * 80f","218f - ease * 62f","15f + ease * 8f","70f + ease * 185f","ease * 18f"]) assert(android.includes(source),source);
  console.log("Android #4365: exact two painted cells/four feature anchors, unchanged remaining metadata, shared phase and source-equivalent motion formulas. Native rendering not executed.");
})().catch(error=>{console.error(error);process.exitCode=1;});
