// Source/catalogue wiring only; not native navigation or pixel validation.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const root=path.resolve(__dirname,"../../.."),sha="ab78711d467c013444883dbaeca23c39a601c875";
const read=n=>fs.readFileSync(path.join(root,"apps/ios/GalaxySSI",n+".swift"),"utf8");
const source=cp.execFileSync("git",["show",sha+":apps/android/app/src/main/java/com/galaxyssi/chat/HealthBodyAtlasActivity.kt"],{cwd:root,encoding:"utf8"});
const detail=read("GalaxySSIHealthAtlasDetail"),row=read("GalaxySSIHealthAtlasFunctionRelatedRow");
for(const token of ["story.relatedLessons.forEach","functionState.choose(id, next)","select(target, HealthAtlasTab.FUNCTION)","choices.any { it.showStructurePreview }","item.kind == HealthAtlasKind.SYSTEM"])assert(source.includes(token),token);
assert(detail.includes("functionSelection.wrappedValue.current(entryID: entry.id, catalogue: catalogue)"));
assert(detail.includes("ForEach(Array(story.related.enumerated())"));
assert(detail.includes("atlas.entry(related.entryID)"));assert(detail.includes("catalogue.story(related.storyID)"));
for(const token of ["depth < 32","catalogue.routes[target.id]?.contains(story.id) == true","var next = state.binding(target).wrappedValue","function.choose(story.id, entryID: target.id, catalogue: catalogue)","next.functionSelection = function","next.tab = .function","state.binding(target).wrappedValue = next","active = true",'NavigationLink(isActive: $active)',"depth: depth + 1"])assert(row.includes(token),token);
assert(row.indexOf("state.binding(target).wrappedValue = next")<row.indexOf("active = true"));
assert(!row.includes("function.save(")&&!row.includes("phases =")&&!row.includes("onAppear"));
assert(row.includes("get(story.title, language)"));assert(row.includes("get(target.name, language)"));
assert(detail.includes("entry.kind == .system && atlas.views(for: entry.id).count > 1"));
assert(detail.includes("!$0.markers.isEmpty || !$0.annotations.isEmpty"));
assert(detail.includes("catalogue.choices(for: entry.id).contains { $0.showStructurePreview }"));
assert(detail.includes("if showFunctionStructurePreview {"));
const catalogue=JSON.parse(fs.readFileSync(path.join(root,"apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasFunctionStories.dataset/content.json")));
let links=0;
for(const story of catalogue.stories)for(const related of story.related){
 const target=catalogue.stories.find(s=>s.id===related.storyID);assert(target);
 assert(catalogue.routes[related.entryID]?.includes(target.id));links++;
}
assert(links>0);
const pbx=fs.readFileSync(path.join(root,"apps/ios/GalaxySSI.xcodeproj/project.pbxproj"),"utf8");
assert.equal(pbx.split("path = GalaxySSIHealthAtlasFunctionRelatedRow.swift;").length-1,1);
console.log("Android #4384 Function navigation: "+links+" valid related destinations, explicit target course/tab selection before activation, existing phases retained, bounded navigation and source-gated structure previews. No native navigation executed.");
