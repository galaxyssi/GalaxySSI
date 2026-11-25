// Restore the #4384 canonical digestive/alimentary artwork without changing graph or lesson definitions.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875",check=process.argv.includes("--check");
for(const [dataset,key,flag]of [["HealthAtlasDigestiveCells","artworkSource","--function-digestive-structures"],["HealthAtlasGutSections","functionArtworkSource","--function-gut-structures"]]){
 const relative="apps/ios/GalaxySSI/Assets.xcassets/"+dataset+".dataset/content.json",file=path.join(root,relative);
 const pack=JSON.parse(fs.readFileSync(file)),previous=JSON.parse(cp.execFileSync("git",["show","bd15bbcf4:"+relative],{cwd:root,encoding:"utf8"}));
 const original=structuredClone(previous),current=structuredClone(pack);delete original[key];delete current[key];
 assert.deepEqual(current,original,"Unrelated declaration changes: "+dataset);
 const revision={androidPR:4384,mergeCommit:sha};
 if(check)assert.deepEqual(pack[key],revision);else{pack[key]=revision;fs.writeFileSync(file,JSON.stringify(pack,null,2)+"\n");}
 cp.execFileSync(process.execPath,[path.join(__dirname,check?"check-body-atlas-sensory-sections.cjs":"import-body-atlas-sensory-gradients.cjs"),flag],{cwd:root,stdio:"inherit"});
}
console.log((check?"Verified":"Imported")+" 26 #4384 canonical vector plates / 191 original paths / 149 gradients. No native app build or pixels verified.");
