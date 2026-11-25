// Exact asset/metadata/source checks; not native rendering or XCTest.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict"),sharp=require("sharp");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875",baseline="50d46aa1b";
const relative="apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasGutSections.dataset/content.json";
const show=(ref,p)=>cp.execFileSync("git",["show",ref+":"+p],{cwd:root,maxBuffer:32_000_000});
(async()=>{
 cp.execFileSync(process.execPath,[path.join(__dirname,"import-body-atlas-function-gut-plates.cjs"),"--check"],{cwd:root,stdio:"inherit"});
 const pack=JSON.parse(fs.readFileSync(path.join(root,relative))),previous=JSON.parse(show(baseline,relative));
 assert.deepEqual(pack.functionArtworkSource,{androidPR:4384,mergeCommit:sha});
 const normalized=structuredClone(pack);delete normalized.functionArtworkSource;
 for(const owner of ["teeth","jejunum"]){
  const plate=pack.plates.find(p=>p.owner===owner),old=previous.plates.find(p=>p.owner===owner);
  assert.equal(plate.aspectRatio,1);assert.equal(plate.features.length,4);
  assert.deepEqual(plate.entryIDs,old.entryIDs);assert.deepEqual(pack.stageFeatures[owner],previous.stageFeatures[owner]);
  assert(!pack.routes[owner]);
  const directory=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",plate.asset+".imageset");
  const contents=JSON.parse(fs.readFileSync(path.join(directory,"Contents.json")));
  assert.equal(contents.images[0].filename,"art.png");
  const png=fs.readFileSync(path.join(directory,"art.png"));assert(png.equals(show(sha,plate.drawable)));
  const info=await sharp(png).metadata();assert.equal(info.width,1254);assert.equal(info.height,1254);assert(info.hasAlpha);
  normalized.plates[normalized.plates.findIndex(p=>p.owner===owner)]=old;
 }
 assert.deepEqual(normalized,previous,"No graph, lesson, unrelated plate or localization changes");
 const native=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/GalaxySSIHealthAtlasGutSections.swift"),"utf8");
 assert(native.includes('static let paintedAssets = ["teeth": "HealthAtlasFunctionGutTooth", "jejunum": "HealthAtlasFunctionGutJejunum"]'));
 assert(native.includes("Self.paintedAssets[owner] == nil ? 360.0 / 280 : 1"));
 const lesson=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/GalaxySSIHealthAtlasSectionLesson.swift"),"utf8");
 assert(lesson.includes("artHeight: GalaxySSIHealthAtlas.GutPack.paintedAssets[id] == nil ? 280 : 360"));
 console.log("Android #4384 alimentary structures: two byte-identical square RGBA PNGs, eight source-calibrated features/two links, correct 360-unit lesson height and unchanged remaining catalogue. No native drawing executed.");
})().catch(e=>{console.error(e);process.exitCode=1;});
