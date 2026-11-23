// Checks the exported source catalogue/inventory, not native Swift or renderer output.
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
const cp=require("node:child_process"),crypto=require("node:crypto"),root=path.resolve(__dirname,"../../..");
const read=file=>JSON.parse(fs.readFileSync(path.join(root,file)));
const pack=read("apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json");
const inventory=read("apps/ios/ANDROID_4384_SOURCE_INVENTORY.json"),sha="ab78711d467c013444883dbaeca23c39a601c875";
assert.deepEqual(pack.source,{androidPR:4384,mergeCommit:sha});assert.deepEqual(inventory.source,pack.source);
assert.equal(inventory.files.length,387);assert.equal(new Set(inventory.files.map(f=>f.path)).size,387);
for(const file of inventory.files){
  assert(["A","M","D"].includes(file.status),file.status);
  const bytes=cp.execFileSync("git",["show",(file.status==="D"?sha+"^1":sha)+":"+file.path],{cwd:root,maxBuffer:32_000_000});
  assert.equal(crypto.createHash("sha256").update(bytes).digest("hex"),file.sha256,file.path);
}
assert.equal(pack.schema,1);assert.equal(pack.stories.length,101);
assert.equal(new Set(pack.stories.map(s=>s.id)).size,101);assert.equal(Object.keys(pack.routes).length,268);
assert.equal(pack.stories.reduce((n,s)=>n+s.chapters.length,0),491);
assert.equal(pack.stories.reduce((n,s)=>n+s.references.length,0),226);
const ids=new Set(pack.stories.map(s=>s.id)),owners=new Set(pack.stories.flatMap(s=>s.owners));
assert.deepEqual(new Set(Object.keys(pack.routes)),owners);assert.deepEqual(new Set(Object.keys(pack.entryPhases)),owners);
for(const story of pack.stories){
  assert(story.chapters.length>=3&&story.chapters.length<=5);assert(story.durationMs>0&&story.durationMs<=20000);
  for(const key of [story.title,story.choiceTitle,story.scope,...story.chapters.flatMap(c=>[c.title,c.caption])])assert(/^health_atlas_\w+$/.test(key),key);
  for(const reference of story.references){const url=new URL(reference.url);assert.equal(url.protocol,"https:");assert(!url.username&&!url.password&&!url.port);}
  for(const related of story.related)assert(pack.routes[related.entryID].includes(related.storyID));
}
for(const [id,choices] of Object.entries(pack.routes)){
  assert(choices.length>0&&choices.length<=6);assert.equal(new Set(choices).size,choices.length);
  assert.equal(choices[0],pack.stories.find(s=>s.owners.includes(id)).id);
  assert(choices.every(id=>ids.has(id)));
  assert.deepEqual(Object.keys(pack.entryPhases[id]),choices);
  for(const phase of Object.values(pack.entryPhases[id]))assert(Number.isFinite(phase)&&phase>=0&&phase<=1);
}
assert.deepEqual(pack.routes.pancreas,["DIGESTION","INSULIN_SECRETION","GLUCAGON_RESPONSE"]);
assert.equal(pack.entryPhases.aorta.HEARTBEAT,0.6);
assert.equal(pack.entryPhases["renal-medulla"].NEPHRON,0.4);
const swift=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/GalaxySSIHealthAtlasFunctionCatalogue.swift"),"utf8");
for(const token of ["stories.count == 101","routes.count == 268","== 491","data.count <= 1_000_000",
  "allowed.contains","Story.safePhase","catalogue.initialPhase"])assert(swift.includes(token),token);
console.log("Android #4384 foundation: 387 pinned source files; 101 Kotlin-evaluated courses, 491 chapters, 226 references, 268 routes and isolated selection/state definitions. Renderer/UI/model parity is unfinished.");
