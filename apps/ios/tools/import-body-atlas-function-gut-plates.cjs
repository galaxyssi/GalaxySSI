// Import #4384's square alimentary PNGs and source-calibrated anchors, not rendered approximations.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875",check=process.argv.includes("--check");
const show=p=>cp.execFileSync("git",["show",sha+":"+p],{cwd:root,maxBuffer:32_000_000});
const kotlin=show("apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasGutSections.kt").toString();
const file=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasGutSections.dataset/content.json");
const pack=JSON.parse(fs.readFileSync(file));
const assets=path.dirname(path.dirname(file));
function write(file,bytes){
 if(check){assert(fs.existsSync(file),file);assert(fs.readFileSync(file).equals(Buffer.from(bytes)),file);}
 else {fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);}
}
for(const [owner,slug,asset]of [["teeth","tooth","HealthAtlasFunctionGutTooth"],["jejunum","jejunum","HealthAtlasFunctionGutJejunum"]]){
 const from=kotlin.indexOf('section("'+owner+'",'),to=kotlin.indexOf('\n        section(',from+1);
 assert(from>=0&&to>from);const block=kotlin.slice(from,to);
 assert(block.includes("squareArt = true"));
 const features=[...block.matchAll(/paintedFeature\("([^"]+)", (\d+), (\d+), R.string.(\w+), R.string.(\w+)\)/g)]
  .map(m=>({marker:{id:m[1],x:Number(m[2])/1254,y:Number(m[3])/1254},title:m[4],explanation:m[5]}));
 const markers=[...block.matchAll(/paintedMarker\("([^"]+)", (\d+), (\d+)\)/g)]
  .map(m=>({id:m[1],x:Number(m[2])/1254,y:Number(m[3])/1254}));
 assert.equal(features.length,4);assert.equal(markers.length,owner==="jejunum"?2:0);
 const plate=pack.plates.find(p=>p.owner===owner);assert(plate);
 assert.deepEqual(plate.features.map(f=>[f.marker.id,f.title,f.explanation]),features.map(f=>[f.marker.id,f.title,f.explanation]));
 assert.deepEqual(plate.markers.map(m=>m.id),markers.map(m=>m.id));
 const drawable="apps/android/app/src/main/res/drawable-nodpi/health_atlas_gut_"+slug+".png",png=show(drawable);
 assert.equal(png.readUInt32BE(16),1254);assert.equal(png.readUInt32BE(20),1254);
 assert.equal(png.subarray(1,4).toString(),"PNG");
 Object.assign(plate,{asset,aspectRatio:1,features,markers,drawable});
 const directory=path.join(assets,asset+".imageset");
 write(path.join(directory,"art.png"),png);
 write(path.join(directory,"Contents.json"),JSON.stringify({images:[{filename:"art.png",idiom:"universal"}],info:{author:"xcode",version:1}},null,2)+"\n");
}
pack.functionArtworkSource={androidPR:4384,mergeCommit:sha};
write(file,JSON.stringify(pack,null,2)+"\n");
console.log((check?"Verified":"Imported")+" #4384 teeth/jejunum: two original 1254-square PNGs, eight features and two links; shared Function/Structure jejunum asset.");
