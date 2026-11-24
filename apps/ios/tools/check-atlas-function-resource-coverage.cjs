// #4384 changed-drawable coverage backed by source/PDF checks, not native rendering.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const read=n=>JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",n+".dataset/content.json")));
const structures=read("HealthAtlasFunctionStructures"),digestive=read("HealthAtlasDigestiveCells"),gut=read("HealthAtlasGutSections");
const coverage=new Map([...structures.plates,...digestive.plates,...gut.plates].map(p=>[p.drawable,p.asset]));
for(const [slug,asset]of [["locator","HealthAtlasFunctionGutLymphoidLocator"],["comparison","HealthAtlasFunctionGutLymphoidComparison"]]){
 coverage.set("apps/android/app/src/main/res/drawable/health_atlas_gut_lymphoid_"+slug+".xml",asset);
}
const inventory=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/ANDROID_4384_SOURCE_INVENTORY.json")));
const changed=inventory.files.filter(f=>/\/drawable\/.*\.xml$/.test(f.path));
assert.equal(changed.length,61);assert.equal(changed.filter(f=>f.status!=="D").length,59);
for(const item of changed){
 if(item.status==="D"){
  assert(!coverage.has(item.path),"Deleted SVG still used by an active plate");
  const png=path.basename(item.path,".xml")+".png",replacement=gut.plates.find(p=>path.basename(p.drawable)===png);
  assert(replacement&&replacement.aspectRatio===1,"Deleted vector must resolve to its square PNG");
 } else {
  const asset=coverage.get(item.path);assert(asset,"Missing changed drawable "+item.path);
  const directory=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets",asset+".imageset");
  const metadata=JSON.parse(fs.readFileSync(path.join(directory,"Contents.json")));
  assert(metadata.images.length>0);for(const image of metadata.images)assert(fs.existsSync(path.join(directory,image.filename)));
 }
}
for(const flag of ["structures","erector","ligaments","placenta","pineal","digestive-structures","gut-structures","gut-lymphoid"]){
 cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-"+flag],{cwd:root,stdio:"pipe"});
}
cp.execFileSync(process.execPath,[path.join(__dirname,"import-body-atlas-function-gut-plates.cjs"),"--check"],{cwd:root,stdio:"inherit"});
assert.deepEqual(digestive.artworkSource,{androidPR:4384,mergeCommit:sha});
assert.deepEqual(gut.functionArtworkSource,{androidPR:4384,mergeCommit:sha});
console.log("Android #4384 drawable scope: all 59 added/modified SVGs covered; two deleted SVG identities use original square PNGs. Eight PDF cohorts verify 82 plates/999 paths/276 gradients including retained source plates. No native compilation or pixels verified.");
