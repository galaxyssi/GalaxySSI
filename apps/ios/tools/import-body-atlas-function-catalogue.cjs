// Evaluate the pinned Android catalogue with Kotlin, without compiling Android renderers.
// Generated stubs supply resource identities/constants; no scene is executed.
const fs=require("node:fs"),path=require("node:path"),os=require("node:os"),cp=require("node:child_process"),crypto=require("node:crypto");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const prefix="apps/android/app/src/main/java/com/galaxyssi/chat/";
const show=file=>cp.execFileSync("git",["show",sha+":"+file],{cwd:root,encoding:"utf8",maxBuffer:16_000_000});
const source=name=>show(prefix+name+".kt");
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),"galaxyssi-function-catalogue-")),files=[];
function generated(name,text){const file=path.join(temporary,name+".kt");fs.writeFileSync(file,text);files.push(file);}
const original=source("HealthAtlasFunctionStory");
const start=original.indexOf("    fun createArt(context: Context)"),end=original.indexOf("    companion object {",start);
if(start<0||end<=start)throw Error("Catalogue renderer boundary changed");
generated("HealthAtlasFunctionStory",original.slice(0,start)+original.slice(end));
for(const name of ["BeatStage","BreathingStage","DigestionStage","NephronStage","SoundStage","VisionStage","GanglionRelayAssignment"]){
  generated("HealthAtlas"+name,source("HealthAtlas"+name));
}
// These pure declarations end before their Android View class.
for(const [name,marker] of [["Podocyte","internal enum class HealthAtlasPodocyteStage"],
  ["Intercalated","internal enum class HealthAtlasIntercalatedStage"],
  ["PlacentalExchange","internal object HealthAtlasPlacentalExchangeLesson"]]){
  const text=source("HealthAtlas"+name+"StoryView"),from=text.indexOf(marker),to=text.indexOf("\ninternal ",from+marker.length);
  if(from<0||to<0)throw Error("Unsupported stage boundary "+name);
  generated(name,"package com.galaxyssi.chat\n"+text.slice(from,to));
}
const constants=[];
for(const name of ["HealthAtlasHeartSection","HealthAtlasGasExchange","HealthAtlasLymphOrgans","HealthAtlasAutonomicNervesPlate","HealthAtlasLigamentsPlate","HealthAtlasPodocyteStoryView"]){
  const declarations=[...source(name).matchAll(/^\s*(?:private )?const val (\w+)\s*=\s*([^\r\n]+)/gm)].map(m=>"const val "+m[1]+" = "+m[2]);
  if(!declarations.length)throw Error("Missing source constants "+name);
  constants.push("internal object "+name+" {\n"+declarations.join("\n")+"\n}");
}
generated("Constants","package com.galaxyssi.chat\n"+constants.join("\n")+'\ninternal enum class HealthAtlasValve { TRICUSPID, MITRAL, PULMONARY, AORTIC; fun openAt(stage: Int) = stage == if (this == TRICUSPID || this == MITRAL) 0 else 2 }');
generated("Context","package android.content\nclass Context");
const keys=[...new Set(files.flatMap(file=>[...fs.readFileSync(file,"utf8").matchAll(/(?:R\.)?string\.(\w+)/g)].map(m=>m[1])))].sort();
const resources=JSON.stringify(keys).replace(/^\[/,"arrayOf(").replace(/\]$/,")");
generated("R","package com.galaxyssi.chat\ninternal object ResourceNames { val keys="+resources+" }\ninternal object R { object string {\n"+keys.map((k,i)=>"const val "+k+" = "+(i+1)).join("\n")+"\n}}");
generated("Export",fs.readFileSync(path.join(__dirname,"AtlasFunctionCatalogueExport.kt"),"utf8"));
const data=require("./atlas-kotlin-extract.cjs")({files,temporary,mainClass:"com.galaxyssi.chat.ExportKt",cwd:root});
const graph=JSON.parse(show("apps/android/app/src/main/assets/health/body-atlas.json")),ids=new Set(graph.entries.map(e=>e.id));
if(data.stories.length<50||data.stories.some(s=>s.chapters.length<3||s.chapters.length>8||s.owners.some(id=>!ids.has(id))))throw Error("Invalid exported story catalogue");
const pack={schema:1,source:{androidPR:4384,mergeCommit:sha},...data};
fs.writeFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json"),JSON.stringify(pack,null,2)+"\n");
const changed=cp.execFileSync("git",["diff","--name-status","--no-renames",sha+"^1",sha],{cwd:root,encoding:"utf8"}).trim().split(/\r?\n/).map(line=>line.split("\t"));
const inventory={schema:1,source:pack.source,files:changed.map(([status,file])=>({path:file,status,
  sha256:crypto.createHash("sha256").update(cp.execFileSync("git",["show",(status==="D"?sha+"^1":sha)+":"+file],{cwd:root,maxBuffer:32_000_000})).digest("hex")}))};
fs.writeFileSync(path.join(root,"apps/ios/ANDROID_4384_SOURCE_INVENTORY.json"),JSON.stringify(inventory,null,2)+"\n");
console.log("Exported "+data.stories.length+" Kotlin-evaluated stories, "+Object.keys(data.routes).length+" owner routes and "+changed.length+" pinned source files. No Android or iOS renderer/test executed.");
