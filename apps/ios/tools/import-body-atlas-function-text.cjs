// Mechanical Android #4384 string-table conversion. No app or renderer execution.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),xml=require("xml-js");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const show=file=>cp.execFileSync("git",["show",sha+":"+file],{cwd:root,encoding:"utf8",maxBuffer:16_000_000});
const inventory=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/ANDROID_4384_SOURCE_INVENTORY.json")));
const catalogue=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")));
const checking=process.argv.includes("--check");
const keys=new Set(["health_atlas_stage","health_atlas_phase","health_atlas_sense_choose","health_atlas_reset"]);
for(const story of catalogue.stories){
  for(const key of [story.title,story.choiceTitle,story.scope,...story.chapters.flatMap(c=>[c.title,c.caption]),...story.references.map(r=>r.title)])keys.add(key);
}
for(const file of inventory.files.filter(f=>f.status!=="D"&&f.path.includes("/src/main/java/")&&f.path.endsWith(".kt"))){
  for(const match of show(file.path).matchAll(/(?:R\.)?string\.(health_atlas_\w+)/g))keys.add(match[1]);
}
const files=cp.execFileSync("git",["ls-tree","-r","--name-only",sha,"apps/android/app/src/main/res/values","apps/android/app/src/main/res/values-zh"],
  {cwd:root,encoding:"utf8"}).trim().split(/\r?\n/);
function text(element){
  return (element.elements||[]).map(e=>e.type==="text"||e.type==="cdata"?e.text??e.cdata:e.type==="element"?text(e):"").join("");
}
const languages=new Map();
for(const [directory,language] of [["values","en"],["values-zh","zh-Hans"]]){
  const strings=new Map();
  for(const file of files.filter(f=>f.includes("/"+directory+"/")&&f.endsWith(".xml"))){
    const resource=xml.xml2js(show(file),{compact:false}).elements.find(e=>e.name==="resources");
    for(const element of resource?.elements||[]){
      const name=element.attributes?.name;
      if(element.name!=="string"||!keys.has(name))continue;
      if(strings.has(name))throw Error("Duplicate Android resource "+directory+":"+name);
      strings.set(name,text(element));
    }
  }
  languages.set(language,strings);
}
function resolve(key,map,seen=new Set()){
  if(seen.has(key))throw Error("Resource alias cycle "+key);seen.add(key);
  const raw=map.get(key)??languages.get("en").get(key);
  if(raw===undefined)throw Error("Missing source resource "+key);
  if(/^@string\/\w+$/.test(raw))return resolve(raw.slice(8),map,seen);
  return raw.replace(/\\'/g,"'").replace(/\\"/g,'"').replace(/\\n/g,"\n").replace(/%([0-9]+)\$s/g,"%$1$@").replace(/%([0-9]+)\$d/g,"%$1$lld");
}
for(const [language,map] of languages){
  const entries=[...keys].sort().map(key=>JSON.stringify(key)+" = "+JSON.stringify(resolve(key,map))+";");
  const destination=path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),content=entries.join("\n")+"\n";
  if(checking){
    if(fs.readFileSync(destination,"utf8").replace(/\r\n/g,"\n")!==content)throw Error("Function resource drift "+language);
  }else fs.writeFileSync(destination,content);
  const fallback=[...keys].filter(k=>!map.has(k));
  console.log(language+": "+entries.length+" Function strings; "+fallback.length+" inherited English fallbacks.");
}
