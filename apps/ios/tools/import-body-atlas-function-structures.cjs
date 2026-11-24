// Evaluate original #4384 pure structure declarations with resource identities and Plate DTO stubs.
// No Android scene, Swift code, XCTest or native app is compiled/executed.
const fs=require("node:fs"),path=require("node:path"),os=require("node:os"),cp=require("node:child_process"),assert=require("node:assert/strict"),xml=require("xml-js");
const complete=process.argv.includes("--complete-4388"),regional=complete||process.argv.includes("--regional");
const root=path.resolve(__dirname,"../../.."),sha=complete?"6581110ec5c048edebf63821dee839b4818fe663":regional?"a81aa85a1c81e41ff19a032eabea1eddcd2371dc":"ab78711d467c013444883dbaeca23c39a601c875",check=process.argv.includes("--check");
const directory="apps/android/app/src/main/java/com/galaxyssi/chat/";
const show=p=>cp.execFileSync("git",["show",sha+":"+p],{cwd:root,maxBuffer:32_000_000});
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),"galaxyssi-function-structures-")),files=[];
function generated(name,text){const file=path.join(temporary,name+".kt");fs.writeFileSync(file,text);files.push(file);}
for(const name of ["TissueContextPlates","AutonomicNervesPlate","LigamentsPlate","PlacentaPlate","CartilageOverviewPlate","SynovialJointPlate"]){
 generated("HealthAtlas"+name,show(directory+"HealthAtlas"+name+".kt").toString());
}
if(regional){
 for(const name of ["AccessoryGlandRoutingAssignment","AxialProtectionAssignment","ClitoralVestibularAssignments",
  "PenileUrinaryAssignment","ScrotalHeatAssignment","ShoulderActionAssignments","ShoulderActionPlates",
  "TenocyteTendonMatrixAssignment","TenocyteTendonMatrixPlate","UterocervicalAssignment","UterocervicalPlates",
  "VulvarProtectionAssignment","VulvarProtectionPlates"]){
  const source=show(directory+"HealthAtlas"+name+".kt").toString();
  generated("HealthAtlas"+name,source.replace(/^    fun createArt\(context: Context, story: HealthAtlasFunctionStory\) = HealthAtlas(?:ClitoralSensory|VestibularGland)StoryView\(context, story\)\r?\n/gm,""));
 }
 generated("Context","package android.content\nclass Context");
 generated("FunctionStory","package com.galaxyssi.chat\ninternal enum class HealthAtlasFunctionStory { SPERM_TRANSPORT }");
}
if(complete)generated("HealthAtlasLoadTransferPlates",show(directory+"HealthAtlasLoadTransferPlates.kt").toString());
generated("Plate",`package com.galaxyssi.chat
internal data class HealthAtlasMarker(val id: String, val x: Float, val y: Float)
internal data class HealthAtlasFeature(val marker: HealthAtlasMarker, val title: Int, val explanation: Int)
internal data class HealthAtlasPlate(val drawable: Int, val owner: String?, val viewLabel: Int,
 val markers: List<HealthAtlasMarker>, val source: String? = null, val viewKey: String? = null,
 val selectorLabel: Int? = null, val features: List<HealthAtlasFeature> = emptyList(), val splitCallouts: Boolean = false)
`);
const names=namespace=>[...new Set(files.flatMap(file=>[...fs.readFileSync(file,"utf8").matchAll(new RegExp("(?:R\\.)?"+namespace+"\\.(\\w+)","g"))].map(m=>m[1])))].sort();
const strings=names("string"),drawables=names("drawable");
const array=values=>"arrayOf("+values.map(x=>JSON.stringify(x)).join(",")+")";
generated("R","package com.galaxyssi.chat\ninternal object ResourceNames { val keys="+array(strings)+" }\n"+
 "internal object DrawableNames { val keys="+array(drawables)+" }\ninternal object R { object string {\n"+
 strings.map((name,i)=>"const val "+name+" = "+(i+1)).join("\n")+"\n}\nobject drawable {\n"+
 drawables.map((name,i)=>"const val "+name+" = "+(i+1)).join("\n")+"\n}}\n");
let exporter=fs.readFileSync(path.join(__dirname,"AtlasFunctionStructuresExport.kt"),"utf8");
if(regional)exporter=exporter.replace("HealthAtlasTissueContextPlates.all.map", "(HealthAtlasTissueContextPlates.all + HealthAtlasTenocyteTendonMatrixPlate.plate).map");
generated("StructureExport",exporter);
const exported=require("./atlas-kotlin-extract.cjs")({files,temporary,mainClass:"com.galaxyssi.chat.StructureExportKt",cwd:root});
assert(exported.length>40&&exported.length<80);
const resourcePaths=cp.execFileSync("git",["ls-tree","-r","--name-only",sha,"apps/android/app/src/main/res"],{cwd:root,encoding:"utf8"}).trim().split(/\r?\n/);
const graph=JSON.parse(show("apps/android/app/src/main/assets/health/body-atlas.json")),ids=new Set(graph.entries.map(e=>e.id));
const aliases={health_atlas_erector_spinae_plate:"HealthAtlasFunctionErector",health_atlas_placenta_plate:"HealthAtlasFunctionPlacenta",
 health_atlas_ligaments_plate:"HealthAtlasFunctionLigaments",health_atlas_pineal_plate:"HealthAtlasFunctionPineal"};
const plates=exported.map(value=>{
 const {drawableName,...plate}=value;
 const matching=resourcePaths.filter(p=>/\/drawable(?:-[^/]+)?\//.test(p)&&path.basename(p,path.extname(p))===drawableName&&/\.(xml|png)$/.test(p));
 assert.equal(matching.length,1,drawableName);const drawable=matching[0],bytes=show(drawable);
 assert(drawable.endsWith(".xml"),"Explicit PNG handling required: "+drawable);
 const attrs=xml.xml2js(bytes.toString(),{compact:true}).vector._attributes;
 const width=Number(attrs["android:viewportWidth"]),height=Number(attrs["android:viewportHeight"]);
 assert(width>0&&height>0);
 assert(ids.has(plate.owner),plate.owner);
 for(const marker of plate.markers)assert(ids.has(marker.id),marker.id);
 const suffix=drawableName.replace(/^health_atlas_/,"").split("_").map(s=>s[0].toUpperCase()+s.slice(1)).join("");
 const loadTransfer=complete&&["health_atlas_pelvic_ring","health_atlas_subcutaneous_section"].includes(drawableName);
 const asset=loadTransfer?"HealthAtlasComplete"+suffix:regional?"HealthAtlasRegional"+suffix:aliases[drawableName]??"HealthAtlasStructure"+suffix;
 return {...plate,...(regional?{id:plate.viewKey??plate.owner}:{}),asset,entryIDs:[plate.owner,...plate.markers.map(m=>m.id)],aspectRatio:width/height,drawable};
});
if(!regional)assert.equal(new Set(plates.map(p=>p.owner)).size,plates.length);
assert.equal(new Set(plates.map(p=>p.id)).size,plates.length);
const pack={schema:1,source:{androidPR:complete?4388:regional?4385:4384,mergeCommit:sha},plates};
const assets=path.join(root,"apps/ios/GalaxySSI/Assets.xcassets"),destination=path.join(assets,(complete?"HealthAtlasCompleteStructures":regional?"HealthAtlasRegionalStructures":"HealthAtlasFunctionStructures")+".dataset");
function write(p,text){if(check)assert.equal(fs.readFileSync(p,"utf8"),text,p);else{fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,text);}}
write(path.join(destination,"content.json"),JSON.stringify(pack,null,2)+"\n");
write(path.join(destination,"Contents.json"),JSON.stringify({data:[{filename:"content.json",idiom:"universal"}],info:{author:"xcode",version:1}},null,2)+"\n");
for(const plate of plates){
 if(!regional&&aliases[path.basename(plate.drawable,".xml")])continue;
 write(path.join(assets,plate.asset+".imageset/Contents.json"),JSON.stringify({images:[{filename:"art.pdf",idiom:"universal"}],info:{author:"xcode",version:1},properties:{"preserves-vector-representation":true}},null,2)+"\n");
}
console.log((check?"Verified":"Exported")+" "+plates.length+" Kotlin-evaluated structure plates / "+plates.reduce((n,p)=>n+p.features.length,0)+" features / "+plates.reduce((n,p)=>n+p.markers.length,0)+" links. Native resources still require import/validation.");
