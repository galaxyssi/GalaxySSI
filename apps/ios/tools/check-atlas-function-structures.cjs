// Pinned declaration/resource/canonical-wiring checks only; not Swift or native UI execution.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n+".swift"),"utf8");
cp.execFileSync(process.execPath,[path.join(__dirname,"import-body-atlas-function-structures.cjs"),"--check"],{cwd:root,stdio:"inherit"});
const pack=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStructures.dataset/content.json")));
const graph=JSON.parse(cp.execFileSync("git",["show",sha+":apps/android/app/src/main/assets/health/body-atlas.json"],{cwd:root,encoding:"utf8"})),ids=new Set(graph.entries.map(e=>e.id));
assert.equal(pack.plates.length,54);assert.equal(new Set(pack.plates.map(p=>p.owner)).size,54);
assert.equal(pack.plates.flatMap(p=>p.features).length,177);assert.equal(pack.plates.flatMap(p=>p.markers).length,27);
const current=local("GalaxySSIHealthAtlasFunctionStructures");
for(const language of ["en","zh-Hans"]){
 const keys=new Set();
 for(const file of ["BodyAtlas","AtlasFunction"]){
  const text=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/"+file+".strings"),"utf8");
  for(const m of text.matchAll(/^"([^"]+)" = /gm))keys.add(m[1]);
 }
 for(const plate of pack.plates){
  assert(ids.has(plate.owner));assert.equal(plate.id,plate.owner);
  assert.equal(plate.aspectRatio,360/280);
  assert.deepEqual(plate.entryIDs,[plate.owner,...plate.markers.map(m=>m.id)]);
  assert.equal(new Set([...plate.markers.map(m=>m.id),...plate.features.map(f=>f.marker.id)]).size,plate.markers.length+plate.features.length);
  for(const point of [...plate.markers,...plate.features.map(f=>f.marker)])assert([point.x,point.y].every(n=>Number.isFinite(n)&&n>=0&&n<=1));
  for(const feature of plate.features)assert(!ids.has(feature.marker.id));
  for(const marker of plate.markers)assert(ids.has(marker.id));
  for(const key of [plate.viewLabel,...(plate.selectorLabel?[plate.selectorLabel]:[]),...plate.features.flatMap(f=>[f.title,f.explanation])])assert(keys.has(key),language+":"+key);
  assert(current.includes('"'+plate.owner+'"'));assert(current.includes('"'+plate.source+'"'));
 }
}
for(const flag of ["structures","erector","ligaments","placenta","pineal"]){
 cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--function-"+flag],{cwd:root,stdio:"inherit"});
}
const atlas=local("GalaxySSIHealthAtlas"),art=local("GalaxySSIHealthAtlasArtwork");
assert(atlas.includes("if let pack = try FunctionStructurePack.read(bundle: bundle) { try pack.validating(in: result, bundle: bundle) }"));
assert(atlas.includes("RegionalStructurePack.plate(for: id) ?? FunctionStructurePack.plate(for: id)"));
assert(atlas.includes("return detail.map { [$0] + views } ?? views"));
assert(atlas.indexOf("if let plate = FunctionStructurePack.plate(for: id) { return plate }")<atlas.indexOf("if let pack = try? GutPack.bundled.get()"));
const regional=local("GalaxySSIHealthAtlasRegionalStructures");
assert(regional.includes("static let sources = FunctionStructurePack.sources.union"));
assert(atlas.includes("RegionalStructurePack.sources.contains(source)"));
assert(atlas.includes('if key == "health_atlas_belongs"'));
assert(art.includes("ForEach(Array(views.enumerated()), id: \\.element.id)"));
assert(art.includes('t(index == 0 ? "view_front" : "view_back")'));
const transforms=require("./body-atlas-vector-transform.cjs"),ordered=require("./body-atlas-ordered-vector.cjs");
const apply=(m,x,y)=>[m[0]*x+m[2]*y+m[4],m[1]*x+m[3]*y+m[5]];
const near=(a,b)=>a.forEach((n,i)=>assert(Math.abs(n-b[i])<1e-9));
const fixture=transforms.group({"android:pivotX":"10","android:pivotY":"20","android:scaleX":"2","android:scaleY":"3","android:rotation":"90","android:translateX":"3","android:translateY":"4"});
near(apply(fixture,10,21),[10,24]);
const parent=transforms.group({"android:translateX":"10","android:translateY":"-7"}),child=transforms.group({"android:rotation":"90"});
near(apply(transforms.multiply(parent,child),2,3),[7,-5]);
for(const matrix of [fixture,transforms.multiply(parent,child),[-1,0,0,1,360,0]]){
 const native=apply(matrix,13,71),pdf=apply(transforms.pdf(matrix,280),13,280-71);
 near(pdf,[native[0],280-native[1]]);
}
const xml='<vector><path android:pathData="M0,0L1,1"/><group android:translateX="10" android:translateY="-7"><group android:rotation="90"><path android:pathData="M2,3L4,5"/></group></group><path android:pathData="M7,8L9,10"/></vector>';
const result=ordered(xml,{affine:true});assert.equal(result.length,3);
assert(!result[0]._atlasTransform&&!result[2]._atlasTransform);near(apply(result[1]._atlasTransform,2,3),[7,-5]);
assert.throws(()=>ordered('<vector><group android:scaleX=".5"><path android:pathData="M0,0L1,1"/></group></vector>'));
assert.throws(()=>transforms.group({"android:invalid":"1"}));assert.throws(()=>transforms.group({"android:scaleX":"0"}));
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
assert.equal(pbx.split("path = GalaxySSIHealthAtlasFunctionStructures.swift;").length-1,1);
const defs=[...pbx.matchAll(/^\s*(C4384[0-9A-F]{19}) \/\*[^\n]+\*\/ = \{/gm)].map(m=>m[1]);assert.equal(defs.length,new Set(defs).size);
console.log("Android #4384 frozen structures: 54 evaluated declarations/177 features/27 links, 782 encoded paths/119 gradients including reused plates, affine/RGB/alpha state and retained regional fallback. This is not SVG quadratic equivalence or latest-view acceptance; no native execution.");
