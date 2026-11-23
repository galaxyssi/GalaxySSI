// Static source and bitmap parity only; no Swift compilation or native UI execution.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const cp=require("node:child_process"),sharp=require("sharp"),root=path.resolve(__dirname,"../../..");
const sha="24748a84e848040dbe0cba323cbd5d6b970fb537",baseline="78b422ede6801548bf8aebd6aaf552005b969ded";
const show=(commit,file,encoding)=>cp.execFileSync("git",["show",commit+":"+file],{cwd:root,encoding,maxBuffer:16_000_000});
const local=file=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",file),"utf8");
(async()=>{
  cp.execFileSync(process.execPath,[path.join(__dirname,"check-body-atlas-heart-section.cjs")],{cwd:root,stdio:"inherit"});
  const file="apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasHeartSectionPack.dataset/content.json";
  const pack=JSON.parse(fs.readFileSync(path.join(root,file)));
  const {artworkSource,...semantic}=pack;
  assert.deepEqual(artworkSource,{androidPR:4364,mergeCommit:sha});
  assert.deepEqual(semantic,JSON.parse(show(baseline,file,"utf8")),"No graph/model changes");
  const kotlin=show(sha,"apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasHeartSection.kt","utf8");
  const swift=local("GalaxySSIHealthAtlasHeartSection.swift"),panel=local("GalaxySSIHealthAtlasValvePanel.swift");
  const sections=[...kotlin.matchAll(/heartSectionMarker\("([^"]+)", (\d+), (\d+)\)/g)].map(m=>[m[1],+m[2],+m[3]]);
  const actual=[...swift.matchAll(/marker\("([^"]+)", (\d+), (\d+)\)/g)].map(m=>[m[1],+m[2],+m[3]]);
  assert.equal(sections.length,6);assert.deepEqual(actual,sections);
  const valves=[...kotlin.matchAll(/\w+\("([^"]+)-valve", (\d+), (\d+), (true|false)\)/g)].map(m=>[m[1],+m[2],+m[3]]);
  const points=[...swift.matchAll(/case \.(\w+): return \((\d+), (\d+)\)/g)].map(m=>[m[1],+m[2],+m[3]]);
  assert.equal(valves.length,4);assert.deepEqual(points,valves);
  assert(swift.includes("x: x / 1254, y: y / 1254"));
  assert(swift.includes("GalaxySSIHealthAtlasHeartSection.marker(id, point.x, point.y)"));
  assert(swift.includes("aspectRatio: 1, markers: Valve.allCases.map(\\.marker)"));
  assert(panel.includes("min(geometry.size.width, geometry.size.height) / 480"));
  assert(panel.includes("geometry.size.height - 480 * scale"));
  for(const axis of ["x","y"]) assert(panel.includes("CGFloat(valve.marker."+axis+") * 480 * scale"));
  assert(!panel.includes("460")&&!panel.includes("valve.point"));
  const png=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasHeartSection.imageset/heart.png"));
  assert(png.equals(show(sha,"apps/android/app/src/main/res/drawable-nodpi/health_atlas_heart_section.png")));
  const info=await sharp(png).metadata();assert.equal(info.width,1254);assert.equal(info.height,1254);assert(info.hasAlpha);
  const rgba=await sharp(png).ensureAlpha().raw().toBuffer(),at=(x,y)=>Array.from(rgba.subarray((y*1254+x)*4,(y*1254+x)*4+4));
  for(const x of [0,1253])for(const y of [0,1253])assert(at(x,y)[3]<=4);
  for(const [id,x,y] of [...sections,...valves.map(([id,x,y])=>[id+"-valve",x,y])]){
    let matched=false;
    for(let dx=-1;dx<=1;dx++)for(let dy=-1;dy<=1;dy++){
      const [r,g,b,a]=at(x+dx,y+dy);
      const expected=["right-atrium","right-ventricle","pulmonary-trunk"].includes(id)?b>r+20:
        ["aorta","left-atrium","left-ventricle"].includes(id)?r>g+50&&r>b+60:r>229&&g>201&&g>b&&b>158;
      matched ||= a>200&&expected;
    }
    assert(matched,id);
  }
  console.log("Android #4364: original transparent 1254-square heart PNG; six anatomical and four shared leaflet anchors, exact color neighborhoods, square normalized overlay and unchanged graph/models.");
})().catch(error=>{console.error(error);process.exitCode=1;});
