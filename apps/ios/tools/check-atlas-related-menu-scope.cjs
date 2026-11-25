// Source and packaging contracts only, never native navigation or recreation acceptance.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../../..'),sha='556cd2c8e452fea8a299e80fc44e03471a7d14ca',base='f0c936664048ac9d1908a481ac0b7a61da282ba9';
const git=args=>cp.execFileSync('git',args,{cwd:root,maxBuffer:16_000_000});
const read=file=>fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n');
const swift=name=>'apps/ios/GalaxySSI/GalaxySSIHealthAtlas'+name+'.swift',source=name=>read(swift(name));
const prior=name=>git(['show',base+':'+swift(name)]).toString().replace(/\r\n/g,'\n');
const check=(text,tokens)=>{for(const token of tokens)assert(text.includes(token),token);};
const changed=git(['diff','--name-status','--no-renames',sha+'^1',sha]).toString().trim().split(/\r?\n/).map(line=>line.split('\t'));
assert.equal(changed.length,9);
const inventory={schema:1,source:{androidPR:4444,mergeCommit:sha},files:changed.map(([status,file])=>({path:file,status,sha256:crypto.createHash('sha256').update(git(['show',sha+':'+file])).digest('hex')}))};
const menu=source('FunctionPlaybackMenu'),detail=source('Detail'),navigation=source('LessonNavigation'),state=source('State');
check(menu,['case chapters, evidence, related','if !related.isEmpty','panel = .related','List(related)','pendingRelated = action.open; panel = nil','let action = pendingRelated; pendingRelated = nil; action?()']);
check(source('FunctionPanel'),['related: relatedActions(story)','story.id + "|" + navigationID']);
check(detail,['state.detailBinding(entry, depth: depth)','navigationID: location.key, relatedActions: relatedActions','state.openRelatedLesson(origin: entry','scroll: scrollMemory.offset','NavigationLink(isActive: relatedDestination)','state.recordDetail(entry, depth: depth)','lessonReturnScroll.removeValue(forKey: location.key)','state.functionSnapshot(entry, depth: depth)']);
assert(!detail.includes('GalaxySSIHealthAtlasFunctionRelatedRow('));
check(navigation,['struct Location: Codable, Equatable','struct Return: Codable, Equatable','(1..<32).contains(depth)','self.lessonNavigation.path.contains(location)','self.lessonNavigation.returns[location.key]?.selection','function.selected = saved.selection.functionSelection?.selected','function.phases[originStory]','text.utf8.count <= 128_000','saved.path.count <= 32','saved.returns.count < 32','saved.schema == 1','atlas.entry($0.entryID) != nil','catalogue.routes[frame.targetID]?.contains(frame.targetStory) == true','cleaner.restore(encodedText, atlas: atlas)','Self.safeScroll(frame.scroll)','zip(saved.path, saved.path.dropFirst())']);
const push=navigation.split('  func openRelatedLesson(')[1].split('  func closeRelatedLesson')[0];
assert(push.indexOf('playback.pause()')<push.indexOf('functionSnapshot(origin, depth: depth)'));
assert(push.indexOf('lessonNavigation.returns[location.key] =')<push.indexOf('binding(target).wrappedValue = next'));
check(state,['depth: Int? = nil','functionPhaseKey(entryID, depth: depth)','if let depth, lessonNavigation.returns[functionPhaseKey(entry.id, depth: depth)] != nil { return value }','lesson-navigation.v1','state.lessonNavigationSerialized','state.restoreLessonNavigation(savedNavigation, atlas: content)','quickTarget = state.lessonNavigation.path.first?.entryID']);
check(navigation,['saved.activeSelection = saved.path.last.flatMap { entries[$0.entryID] }','cleaned(active, entryID: last.entryID)']);
const select=navigation.split('  func selectDetailTab(')[1].split('  @discardableResult')[0];
assert(select.indexOf('guard selection.wrappedValue.tab != tab')<select.indexOf('playback.pause()'));
check(source('CompactTabs'),['if selection != option || allowsReselect']);
assert(source('StandaloneModels').includes('allowsReselect: true'));
for(const name of ['Detail','Research','StandaloneModels'])assert(source(name).includes('GalaxySSIHealthAtlasRestoredDetailLink'),name);
check(source('RestoredDetailLink'),['enabled && state.restoredDetailChildren[location.key] != nil','state.closeRestoredDetail(location)','depth: next.depth']);
const core=s=>s.split('}.accessibilityIdentifier("atlas-function-player")')[1];
assert.equal(core(source('FunctionPlayer')),core(prior('FunctionPlayer')));
assert.equal(menu.split('  private var chapters:')[1],prior('FunctionPlaybackMenu').split('  private var chapters:')[1]);
assert.equal(state.split('  func restore(_ text:')[1].split('  var serialized:')[0],prior('State').split('  func restore(_ text:')[1].split('  var serialized:')[0]);
assert.equal(detail.split('struct GalaxySSIHealthAtlasValues:')[1],prior('Detail').split('struct GalaxySSIHealthAtlasValues:')[1]);
for(const name of ['ChapterClock','SimulationPanel','Physiology','AgentContext','AgentHandoff','FunctionCatalogue','FunctionArtwork','FunctionScene','FilmPalette','RodResponse','RodMembraneDrawing'])assert.equal(source(name),prior(name),name);
for(const locale of ['en','zh-Hans']){const table=read('apps/ios/GalaxySSI/'+locale+'.lproj/AtlasRelatedAnimations.strings');assert.equal([...table.matchAll(/^"health_atlas_/gm)].length,2);assert(table.includes('"health_atlas_related_lesson_label" = "%1$@ · %2$@";'));}
const tests='apps/ios/GalaxySSITests/GalaxySSIHealthAtlasLessonNavigationTests.swift';
check(read(tests),['testSameOrganReturnRestoresOriginButRetainsDestinationProgressAndIgnoresLateWrites','testRestoredOrdinaryAncestorAndCrossEntryRelatedReturnKeepDistinctContexts','testRetappingSelectedDetailTabDoesNotPauseOrMutateState','testNavigationArchiveRejectsUnboundedUnknownAndNoncontiguousPaths','restored.restoreLessonNavigation','child.wrappedValue = destination']);
const mapping={HealthAtlasFunctionPlayer:['FunctionPlayer','FunctionPanel','FunctionPlaybackMenu','FunctionRelatedRow','LessonNavigation'],HealthBodyAtlasActivity:['Detail','State','LessonNavigation','RestoredDetailLink','CompactTabs','StandaloneModels','Research']};
const files=inventory.files.map(file=>{
 const name=path.basename(file.path),key=name.replace(/\.kt$/,'');let kind,ios,note;
 if(mapping[key]){kind='native-production-port';ios=mapping[key].map(swift);note='Menu-only related actions after sheet dismissal; contextual origin course/phase/scroll snapshots, inactive-parent and late-child write isolation, independent destination course progress and entry-scoped numerical settings. Bounded public navigation archive validates entries/courses/path/schema/size and reuses existing sanitizers. Reconstruct detail links in ordinary, research and standalone containers. Retapping current tabs is a no-op; highlighted Function still exits standalone. Native gestures, timing and recreation remain unexecuted.';}
 else if(file.path.includes('/androidTest/')){kind='android-device-source-reference';ios=[tests,'apps/ios/tools/check-atlas-related-menu-scope.cjs'];note=name+': original real-popup interaction, same-organ recreation/return, cross-entry flows, chapter-relative animation sampling and clock diagnostics reviewed as source references only. Added native state/archive fixtures, not executed. No moving pixels, native timing, screenshots or recreation acceptance claimed.';}
 else if(file.path.includes('/res/')){kind='exact-resource-delta-with-neutral-format';ios=['apps/ios/GalaxySSI/en.lproj/AtlasRelatedAnimations.strings','apps/ios/GalaxySSI/zh-Hans.lproj/AtlasRelatedAnimations.strings',swift('FunctionText'),swift(''),'apps/ios/tools/import-body-atlas-regional-text.cjs','apps/ios/GalaxySSI.xcodeproj/project.pbxproj'];note='One exact translated heading pair plus an explicitly pinned placeholder/punctuation-only neutral format shared in both tables. The format is not marked translatable=false in Android; do not call it a translated pair or source-declared non-translatable name. Two entries per locale.';}
 else{assert.equal(name,'build.gradle.kts');kind='android-version-only';ios=[];note='No iOS version bump or IPA.';}
 for(const target of ios)assert(fs.existsSync(path.join(root,target)),target);return{source:file.path,sourceSHA256:file.sha256,kind,ios,note};
});
assert.equal(files.filter(f=>f.kind==='android-device-source-reference').length,4);
for(const[suffix,value]of[['SOURCE_INVENTORY',inventory],['PORT_COVERAGE',{schema:1,source:inventory.source,verification:'source-contracts-only-not-native-execution',files}]]){const file='apps/ios/ANDROID_4444_'+suffix+'.json',content=JSON.stringify(value,null,2)+'\n';if(process.argv.includes('--write'))fs.writeFileSync(path.join(root,file),content);else assert.equal(read(file),content);}
if(process.argv.includes('--checks'))for(const command of ['import-body-atlas-regional-text.cjs --related-menu-4444 --check','check-atlas-function-navigation.cjs','check-atlas-film-captions-scope.cjs --checks']){const[file,...args]=command.split(' ');cp.execFileSync(process.execPath,[path.join(__dirname,file),...args],{cwd:root,stdio:'inherit'});}
console.log('Android #4444: nine source hashes/dispositions; menu-only related links, contextual return/archive and reselect source contracts. Not native navigation, recreation, timing or XCTest acceptance.');
