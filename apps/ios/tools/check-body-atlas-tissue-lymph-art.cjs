// Static pinned-resource audit, not XCTest or native application execution.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const assert=require("node:assert/strict"),xml=require("xml-js"),root=path.resolve(__dirname,"../../..");
const sha="b8fbf1191367153af2824506df99bbc5c5bae56e",baseline="73c51b8a42a1882a15125110d335a62eeda438cd";
const show=(commit,file)=>cp.execFileSync("git",["show",commit+":"+file],{cwd:root,encoding:"utf8",maxBuffer:4_000_000});
for(const script of ["check-body-atlas-tissues.cjs","check-body-atlas-lymph-organs.cjs"]) {
  cp.execFileSync(process.execPath,[path.join(__dirname,script)],{cwd:root,stdio:"inherit"});
}
let paths=0,strokes=0;
for(const name of ["HealthAtlasTissues","HealthAtlasLymphOrgans"]) {
  const file="apps/ios/GalaxySSI/Assets.xcassets/"+name+".dataset/content.json";
  const pack=JSON.parse(fs.readFileSync(path.join(root,file))),old=JSON.parse(show(baseline,file));
  assert.deepEqual(pack.artworkSource,{androidPR:4363,mergeCommit:sha});
  const {artworkSource,...semantic}=pack;
  assert.deepEqual(semantic,old,"No change to graph, routes, features, stages or model data");
  for(const plate of pack.plates) {
    const before=xml.xml2js(show(pack.source.mergeCommit,plate.drawable),{compact:true}).vector;
    const after=xml.xml2js(show(sha,plate.drawable),{compact:true}).vector;
    for(const key of ["width","height","viewportWidth","viewportHeight"]) assert.equal(after._attributes["android:"+key],before._attributes["android:"+key]);
    assert.equal(after.path.length,before.path.length);
    for(const [i,p] of after.path.entries()) {
      const geometry=a=>Object.fromEntries(Object.entries(a).filter(([k])=>!["android:fillColor","android:strokeColor"].includes(k)));
      assert.deepEqual(geometry(p._attributes),geometry(before.path[i]._attributes),plate.id+":"+i);
      if(p["aapt:attr"]?._attributes.name==="android:strokeColor") strokes++;
      paths++;
    }
  }
}
assert.equal(paths,646);assert.equal(strokes,11);
cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-sensory-sections.cjs"),"--tissue-lymph"],{cwd:root,stdio:"inherit"});
console.log("Android #4363: all 646 path geometries and semantic packs unchanged; 11 shaded strokes preserve original widths/caps/joins.");
