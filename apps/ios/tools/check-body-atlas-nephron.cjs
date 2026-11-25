// Source/resource audit only; no Swift/native execution.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=name=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",name),"utf8");
const show=name=>cp.execFileSync("git",["show",sha+":apps/android/app/src/main/"+name],{cwd:root,maxBuffer:20_000_000});
const source=show("java/com/galaxyssi/chat/HealthAtlasNephronStoryView.kt").toString();
const stage=show("java/com/galaxyssi/chat/HealthAtlasNephronStage.kt").toString();
const motion=local("GalaxySSIHealthAtlasNephronMotion.swift"),view=local("GalaxySSIHealthAtlasNephronView.swift");
const routes=["throughGlomerulus","filter","proximal","returnToBlood","periProximal","loop","waterFromLoop","saltFromLoop",
  "distal","intoDistal","periDistal","drain","waterFromDuct"];
for(const name of routes){
  const block=source.match(new RegExp("private val "+name+" = path \\{([\\s\\S]*?)\\n    \\}"));assert(block,name);
  const expected=[...block[1].matchAll(/(?:moveTo|lineTo|quadTo|cubicTo)\(([^)]+)\)/g)].map(m=>m[1].split(",").map(v=>Number(v.trim().replace(/f$/,""))));
  const target=motion.match(new RegExp("static let "+name+" = route\\(([^\\n]+)\\)"));assert(target,name);
  const parsed=JSON.parse("["+target[1]+"]");assert.deepEqual([[parsed[0],parsed[1]],...parsed.slice(2)],expected,name);
}
const expectedStages=[["filter",["BLOOD","FILTER"]],["proximal",["FILTRATE","REABSORB"]],
  ["loop",["FILTRATE","LOOP_WATER","LOOP_SALT"]],["distal",["FILTRATE","SECRETE"]],["collect",["DUCT_WATER","URINE"]]];
const stageBlocks=[...stage.matchAll(/listOf\(([^)]+)\)/g)].map(m=>[...m[1].matchAll(/HealthAtlasNephronRoute\.(\w+)/g)].map(v=>v[1]));
assert.deepEqual(stageBlocks,expectedStages.map(v=>v[1]));
const streamCases=[["filter",["throughGlomerulus",".blood",5,"filter",".crosses",2]],
  ["proximal",["proximal",".fluid",5,"returnToBlood",".crosses",2]],
  ["loop",["loop",".fluid",8,"waterFromLoop",".crosses",2,"saltFromLoop",".salt",2]],
  ["distal",["distal",".fluid",7,"intoDistal",".secreted",3]],
  ["collect",["waterFromDuct",".crosses",2,"drain",".salt",7]]];
for(const [name,expected] of streamCases){
  const block=motion.match(new RegExp("case \\."+name+": return \\[([^\\n]+)\\]"));assert(block,name);
  const actual=[...block[1].matchAll(/route: Self\.(\w+), ink: (\.\w+), count: (\d+)/g)].flatMap(m=>[m[1],m[2],Number(m[3])]);
  assert.deepEqual(actual,expected,name);
}
for(const color of ["A84554","19796F","355F9E","98601C","76508E"]){
  assert(motion.includes("0x"+color));assert(source.toLowerCase().includes("0xff"+color.toLowerCase()));
}
assert(motion.includes("fraction * 1.3 + Double($0) / Double(count)"));assert(source.includes("time * 1.3f + index / count.toFloat()"));
for(const token of ["art.translateBy(x: 55, y: 17)","art.scaleBy(x: 0.20, y: 0.20)","width: 1173, height: 1341",
  "lineWidth: 37","motion.positions(count: 2)","lineWidth: 13","lineWidth: 7.5","atlas-function-nephron-art"])assert(view.includes(token),token);
for(const key of ["glomerulus","blood","filtrate","capillary","reabsorb","water","salt","secretion","urine"]){
  for(const language of ["en","zh-Hans"])assert(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8").includes('"health_atlas_nephron_story_'+key+'"'),key);
}
const folder=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasNephron.imageset");
const filename=JSON.parse(fs.readFileSync(path.join(folder,"Contents.json"))).images[0].filename;
assert(show("res/drawable-nodpi/health_atlas_nephron.png").equals(fs.readFileSync(path.join(folder,filename))));
assert(local("GalaxySSIHealthAtlasFunctionArtwork.swift").includes('case "NEPHRON": GalaxySSIHealthAtlasNephronView'));
const project=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
for(const name of ["NephronMotion","NephronView"])assert.equal(project.split("GalaxySSIHealthAtlas"+name+".swift in Sources").length-1,2,name);
console.log("Android #4384 nephron source audit: five stage transport sets, thirteen exact routes, original 1173x1341 illustration, stage-specific counts/inks, capillary flow and bilingual labels. No native build or pixels verified.");
