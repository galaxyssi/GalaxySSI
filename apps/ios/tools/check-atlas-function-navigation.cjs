// Source/catalogue contracts only, not native navigation execution.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../../..');
const read=n=>fs.readFileSync(path.join(root,'apps/ios/GalaxySSI/GalaxySSIHealthAtlas'+n+'.swift'),'utf8');
const detail=read('Detail'),navigation=read('LessonNavigation'),menu=read('FunctionPlaybackMenu');
assert(!detail.includes('GalaxySSIHealthAtlasFunctionRelatedRow('));
for(const token of ['relatedActions: relatedActions','atlas.entry(related.entryID)','catalogue.story(related.storyID)','NavigationLink(isActive: relatedDestination)','state.detailBinding(entry, depth: depth)'])assert(detail.includes(token),token);
for(const token of ['(1..<32).contains(depth)','function.choose(related.storyID','next.tab = .function','self.lessonNavigation.path.contains(location)','lessonReturnScroll[location.key] = saved.scroll'])assert(navigation.includes(token),token);
for(const token of ['if !related.isEmpty','panel = .related','onDismiss:','pendingRelated = action.open','action?()'])assert(menu.includes(token),token);
const catalogue=JSON.parse(fs.readFileSync(path.join(root,'apps/ios/GalaxySSI/Assets.xcassets/HealthAtlasCompleteStories.dataset/content.json')));
let links=0;for(const story of catalogue.stories)for(const related of story.related){assert(catalogue.routes[related.entryID]?.includes(related.storyID));links++;}assert(links>0);
console.log('Related navigation: '+links+' current valid edges, menu-only destinations and contextual return source wiring. No native navigation execution.');
