// Source/resource/packaging contracts, not native layout, gestures or execution.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto'),xml=require('xml-js');
const root=path.resolve(__dirname,'../../..'),sha='9ec28d754459358556c570134171c79b55951982',base='cdf7c9587c94c4be40f416047fbe675499e479f5';
const git=args=>cp.execFileSync('git',args,{cwd:root,maxBuffer:16_000_000});
const read=file=>fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n');
const swift=name=>'apps/ios/GalaxySSI/GalaxySSIHealthAtlas'+name+'.swift',source=name=>read(swift(name));
const prior=name=>git(['show',base+':'+swift(name)]).toString().replace(/\r\n/g,'\n');
const check=(text,tokens)=>{for(const token of tokens)assert(text.includes(token),token);};
const android=name=>git(['show',sha+':apps/android/app/src/main/java/com/galaxyssi/chat/'+name+'.kt']).toString();
const changed=git(['diff','--name-status','--no-renames',sha+'^1',sha]).toString().trim().split(/\r?\n/).map(line=>line.split('\t'));
assert.equal(changed.length,27);
const inventory={schema:1,source:{androidPR:4445,mergeCommit:sha},files:changed.map(([status,file])=>{
 const revision=status==='D'?sha+'^1':sha;
 return{path:file,status,contentRevision:revision,sha256:crypto.createHash('sha256').update(git(['show',revision+':'+file])).digest('hex')};
})};
check(android('HealthAtlasFigureFrame'),['LEGEND_OVERLAP_DP = 28','atlas-figure-legend']);
const frame=source('FigureFrame'),scene=source('FunctionScene'),art=source('Artwork'),detail=source('Detail'),panel=source('SimulationPanel'),nav=source('LessonNavigation');
// #4446 replaces the former 28-point fading footer with connected responsive notes.
check(frame,['width >= 580', 'preferSide && width >= 280', 'min(46, legend / 2)', '.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 9)', 'overlayPreferenceValue', 'clipShape(RoundedRectangle(cornerRadius: 8))']);
check(scene,['GalaxySSIHealthAtlasFigureFrame(identifier: "atlas-function-frame"','legendIdentifier: "atlas-function-subtitles"','GalaxySSIHealthAtlasReservedCaption(values: labels','story.chapters.map { t($0.caption) }','GalaxySSIHealthTheme.accent','.foregroundColor(.primary)']);
assert(!scene.includes('colors.caption'));
check(source('SceneFrame'),['ForEach(values.indices','.hidden().accessibilityHidden(true).allowsHitTesting(false)','.lineLimit(maximumLines).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)']);
check(art,['plate?.markers.compactMap','if !choices.isEmpty || !(plate?.annotations.isEmpty ?? true)','atlas-source-structure','atlas-structure-figure','atlas-concept-figure','atlas-fullscreen-figure','note: "symbol_only"','explanation: entry.description','explanation: nil','minimumHeight: entry == nil ? 366 : 266','Button { fullscreenLayers.toggle() }','selectedFeature = feature','UIScrollView keeps image, markers']);
assert(!art.includes('atlas.children('));assert(!art.includes('atlas.cells('));assert(!art.includes('Slider('));
check(source('LabeledArtwork'),['minimumHeight: input.minimumHeight','backgroundColor = .clear']);
check(source('CalloutLayout'),['legendInset.isFinite','minimumHeight.isFinite','required(right)) + legendInset','height - 8 - legendInset']);
const structure=detail.split('  private var structure:')[1].split('  private var name:')[0];
assert(structure.includes('GalaxySSIHealthAtlasArtwork('));assert(!structure.includes('relationships'));assert(!detail.includes('atlas-structure-layer'));assert(!detail.includes('Text(t("art_note"))'));
check(source('SearchNavigation'),['state.beginCatalogueSearch(entry, depth: depth, scroll: memory.offset)','fullScreenCover(item: search','state.cancelCatalogueSearch()','state.openCatalogueResult(target, from: saved, atlas: atlas)','saved.structureOnly == true && surface.contains(saved.selection)']);
for(const name of ['Detail','Research','StandaloneModels'])check(source(name),['GalaxySSIHealthAtlasSearchNavigation','state.detailBinding(entry, depth: depth)']);
check(detail,['selection.wrappedValue.tab == .function || selection.wrappedValue.tab == .structure','structureOnly != true']);
check(source('Search'),['@State private var kind = "organ"','@State private var system = ""','@State private var tissues = false','@FocusState','focused = true','value.prefix(100)','matches.prefix(limit)','atlas-search-result-','system = ""; tissues = false; limit = 24']);
check(nav,['struct Search: Codable, Equatable, Identifiable','var search: Search?','playback.pause()','functionSnapshot(entry, depth: depth)','Self.safeScroll(scroll)','lessonNavigation.path.last == saved.origin','targetStory: "", structureOnly: true','next.tab = .structure','next.artworkView = saved.selection.artworkView','saved.path.last == search.origin','cleaned(search.selection','frame.structureOnly == true ? frame.targetStory.isEmpty']);
check(panel,['if !retinal && endocrine == nil','atlas-simulation-figure','annotationScope: "atlas-simulation-figure"','legend: { stageCaption }']);
assert(!panel.includes('if germline != nil { stageCaption }'));
assert.equal(panel.split('.onReceive(timer)')[1].split('.onDisappear { pause() }')[0],prior('SimulationPanel').split('.onReceive(timer)')[1].split('.onDisappear { pause() }')[0]);
assert.equal(panel.split('  private var quantitative:')[1],prior('SimulationPanel').split('  private var quantitative:')[1]);
for(const name of ['ChapterClock','FunctionArtwork','FunctionCatalogue','Physiology','AgentContext','AgentHandoff','RodResponse','RodMembraneDrawing','Circulation','GasExchange'])assert.equal(source(name),prior(name),name);
assert.equal(detail.split('struct GalaxySSIHealthAtlasValues:')[1],prior('Detail').split('struct GalaxySSIHealthAtlasValues:')[1]);
for(const [directory,expected]of[['values','#E7EFED'],['values-night','#263537']]){
 const doc=xml.xml2js(git(['show',sha+':apps/android/app/src/main/res/'+directory+'/health_atlas_scene_colors.xml']).toString(),{compact:false});
 const colors=doc.elements.find(e=>e.name==='resources').elements.filter(e=>e.name==='color');
 assert.equal(colors.length,1);assert.equal(colors[0].elements[0].text,expected);assert(source('FilmPalette').includes('0x'+expected.slice(1)));
}
const test='apps/ios/GalaxySSITests/GalaxySSIHealthAtlasLessonNavigationTests.swift';
check(read(test),['testSearchCancelAndResultBackPreserveOriginVariantScrollAndPhase','testFigureNoteLayoutAndLegacyBottomInsetDefaults']);
const mapping={HealthAtlasAnatomyDialog:['Artwork','FigureFrame','LabeledArtwork','CalloutLayout'],HealthAtlasCaptionSizes:['SceneFrame'],HealthAtlasCirculationView:['SimulationPanel'],HealthAtlasFigureFrame:['FigureFrame'],HealthAtlasFunctionPlayer:['FunctionScene','FigureFrame'],HealthAtlasLabeledImage:['LabeledArtwork','CalloutLayout','Artwork'],HealthAtlasProcessView:['SimulationPanel'],HealthAtlasSceneFrame:['SceneFrame','FigureFrame'],HealthAtlasSimulationPanel:['SimulationPanel','FigureFrame'],HealthAtlasUi:['Artwork','FigureFrame'],HealthBodyAtlasActivity:['Detail','Search','SearchNavigation','Research','StandaloneModels','LessonNavigation','State','Artwork']};
const files=inventory.files.map(file=>{
 const name=path.basename(file.path),key=name.replace(/\.kt$/,'');let kind,ios,note;
 if(mapping[key]){kind='native-production-port';ios=mapping[key].map(swift);note='Shared full-width figure/legend with 28-point bounded overlap and 18-point ground fade. Native Text reserves longest chapter/caption. Structure is figure-only; marker-only layer choices, source header icon, conceptual symbol fallback, in-figure descriptions. Fullscreen keeps zoom, labels and feature alerts. Process artwork reserves bottom 28 outside its unmodified drawing/hit regions. Search snapshots/restores origin variant, course/phase/scroll and opens results directly without an intermediate catalogue history frame. Deleted Android SceneFrame is replaced for figures; iOS SceneFrame remains as plain padded simulation container and native caption probes. No native rendering/execution acceptance.';}
 else if(file.path.includes('/androidTest/')){kind='android-device-source-reference';ios=[test,'apps/ios/tools/check-atlas-integrated-figures-scope.cjs'];note=name+': reviewed as source reference only, including flat structure navigation, figure containment, function captions, specialized simulations and search navigation. Added Swift fixture sources, not run. No iOS image sweep, device tests, keyboard, gestures or recreation claims.';}
 else if(name==='health_atlas_scene_colors.xml'){kind='exact-ground-theme-resources';ios=[swift('FigureFrame'),swift('FilmPalette')];note='Active figures use only exact day/night ground colors. Previous dark caption/chapter/text colors remain in immutable historical palette fixtures but are no longer applied by FunctionScene.';}
 else if(file.path.includes('/res/')){kind='exact-translated-resource-pair';ios=['apps/ios/GalaxySSI/en.lproj/AtlasIntegratedFigures.strings','apps/ios/GalaxySSI/zh-Hans.lproj/AtlasIntegratedFigures.strings',swift(''),swift('FunctionText'),'apps/ios/tools/import-body-atlas-regional-text.cjs','apps/ios/GalaxySSI.xcodeproj/project.pbxproj'];note='One exact English/Chinese concept-symbol disclaimer pair. No guessed translations or cross-language placeholder fallback.';}
 else{assert.equal(name,'build.gradle.kts');kind='android-version-only';ios=[];note='No iOS version bump or IPA.';}
 for(const target of ios)assert(fs.existsSync(path.join(root,target)),target);
 return{source:file.path,sourceSHA256:file.sha256,contentRevision:file.contentRevision,kind,ios,note};
});
assert.equal(files.filter(f=>f.kind==='native-production-port').length,11);
assert.equal(files.filter(f=>f.kind==='android-device-source-reference').length,11);
for(const[suffix,value]of[['SOURCE_INVENTORY',inventory],['PORT_COVERAGE',{schema:1,source:inventory.source,verification:'source-contracts-only-not-native-execution',files}]]){
 const file='apps/ios/ANDROID_4445_'+suffix+'.json',content=JSON.stringify(value,null,2)+'\n';
 if(process.argv.includes('--write'))fs.writeFileSync(path.join(root,file),content);else assert.equal(read(file),content);
}
if(process.argv.includes('--checks'))for(const command of ['import-body-atlas-regional-text.cjs --integrated-figures-4445 --check','check-atlas-related-menu-scope.cjs --checks']){
 const[file,...args]=command.split(' ');cp.execFileSync(process.execPath,[path.join(__dirname,file),...args],{cwd:root,stdio:'inherit'});
}
console.log('Android #4445: 27 path hashes/dispositions (including deleted-before provenance), integrated figures, caption reservation, flat structure, direct search return and preserved numerical/playback kernels. Not native Swift compilation or layout acceptance.');
