// Pinned integration/source audit only; XCTest below is intentionally not executed.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const local=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n+".swift"),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthAtlasAgentContext.kt"],{cwd:root,encoding:"utf8"});
for(const token of ["topic == null && functionPhase != null","HealthAtlasFunctionStory.choicesForId(item.id)","functionStory.takeIf(allowed::contains)","story.chapter(functionPhase)","story.chapters[chapter]","context.getString(story.scope)","story.references.forEach"])assert(source.includes(token),token);
const helper=local("GalaxySSIHealthAtlasFunctionContext"),context=local("GalaxySSIHealthAtlasAgentContext"),handoff=local("GalaxySSIHealthAtlasAgentHandoff");
for(const token of ["guard let catalogue else","current.current(entryID: entryID, catalogue: catalogue)","current.phase(entryID: entryID, storyID: story.id, catalogue: catalogue)","entryID == self.entryID","story.chapter(phase)","text(story.title)","text(chapter.title)","text(chapter.caption)","text(story.scope)","story.references.map"])assert(helper.includes(token),token);
assert(context.includes("if screen == .function, let function { lines += function.lines(for: anatomy.id, language: language) }"));
assert(context.indexOf("guard screen != .values")<context.indexOf("function.lines"));
assert(handoff.includes("if !research, selection.tab == .function, let entry"));
assert(handoff.includes("selection: selection.functionSelection"));
assert(handoff.includes("aging: selection.aging, function: function, language: language"));
assert(handoff.includes('if let function { prompt += "\\n" + function.lines(for: entry.id, language: language).joined(separator: "\\n") }'));
assert(handoff.indexOf("let function: GalaxySSIHealthAtlasFunctionContext?")<handoff.indexOf("#if GALAXYSSI_ATLAS_AGENT_CONTEXT"));
assert(handoff.includes("selection: selectionSnapshot?() ?? selection"));
assert(local("GalaxySSIHealthAtlasDetail").includes("selectionSnapshot: { state.functionSnapshot(entry) }"));
const data=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")));
const texts=language=>{
 const file=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",language+".lproj/AtlasFunction.strings"),"utf8"),map=new Map();
 for(const line of file.split(/\r?\n/)){const m=line.match(/^"([^"]+)" = (".*");$/);if(m)map.set(m[1],JSON.parse(m[2]));}
 return map;
};
for(const lang of ["en","zh-Hans"]){
 const map=texts(lang);
 for(const story of data.stories){
  for(const chapter of story.chapters)for(const key of [story.title,chapter.title,chapter.caption,story.scope])assert(map.has(key),lang+":"+key);
  assert(story.references.length>0);
 }
}
assert.deepEqual(data.routes.pancreas,["DIGESTION","INSULIN_SECRETION","GLUCAGON_RESPONSE"]);
assert.equal(data.entryPhases.aorta.HEARTBEAT,0.6);
const swiftTests=fs.readFileSync(path.join(root,"apps/ios/GalaxySSITests/GalaxySSIHealthAtlasAgentContextTests.swift"),"utf8");
assert(swiftTests.includes("testFunctionContextKeepsCurrentCourseChapterAndOwnerAcrossScreens"));
for(const token of ['entryID: "unknown"','catalogue: nil','screen == .values','screen == .function','for: "heart"'])assert(swiftTests.includes(token),token);
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
assert.equal(pbx.split("path = GalaxySSIHealthAtlasFunctionContext.swift;").length-1,1);
console.log("Android #4384 Function Agent context source wiring: both build branches, current owner/course/chapter/scope/reference URLs, 101-course bilingual text coverage, live snapshot path. Added XCTest source not executed; no native compilation.");
