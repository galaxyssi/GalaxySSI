// Source/packaging contracts only; not native coordinates, layout or execution.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../../..'),sha='cb3e3ca49c2d8aade7b190f1c82400d40a462806',base='916e8a5bc3c79f0d612c829b413cc913cceab352';
const git=args=>cp.execFileSync('git',args,{cwd:root,maxBuffer:16_000_000});
const read=file=>fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n');
const swift=name=>'apps/ios/GalaxySSI/GalaxySSIHealthAtlas'+name+'.swift',source=name=>read(swift(name));
const prior=name=>git(['show',base+':'+swift(name)]).toString().replace(/\r\n/g,'\n');
const check=(text,tokens)=>{for(const token of tokens)assert(text.includes(token),token);};
const android=name=>git(['show',sha+':apps/android/app/src/main/java/com/galaxyssi/chat/'+name+'.kt']).toString();
const changed=git(['diff','--name-status','--no-renames',sha+'^1',sha]).toString().trim().split(/\r?\n/).map(line=>line.split('\t'));
assert.equal(changed.length,17);
const inventory={schema:1,source:{androidPR:4446,mergeCommit:sha},files:changed.map(([status,file])=>({path:file,status,sha256:crypto.createHash('sha256').update(git(['show',sha+':'+file])).digest('hex')}))};
const frame=source('FigureFrame'),scene=source('FunctionScene'),caption=source('SceneFrame'),art=source('Artwork'),panel=source('SimulationPanel'),research=source('Research');
check(android('HealthAtlasFigureFrame'),['width >= ui.dp(580)','preferSideNote && width >= ui.dp(280)','width * .40f','width * .44f','if (overlayNote) .72f else .83f','minOf(ui.dp(46), legend.measuredHeight / 2)','annotationTarget = target','image.imageMatrix.mapPoints(subjectPosition)','parent.scrollX']);
// #4447 unifies all figures as non-overlapping side notes; keep connected native coordinates and clipping.
check(frame,['static func columns(width: CGFloat)', 'width < 320', 'compact ? 8 : 12', 'compact ? 8 : 16', 'min(width * 0.40, 328)', 'HStack(alignment: .center, spacing: columns.gutter)', 'note.frame(width: columns.noteWidth)', 'drawing.frame(width: columns.artWidth)', '.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 9)', 'overlayPreferenceValue', 'identifier + ".target"', 'identifier + ".subject"', 'identifier + ".viewport"', 'viewport.minX + $0.x', 'CGPoint(x: $0.minX, y: $0.midY)', 'subject(in rect: CGRect', 'min(art.maxX, max(art.minX, point.x))', 'min(art.maxY, max(art.minY, point.y))', '.accessibilityHidden(true).allowsHitTesting(false)']);
assert(!frame.includes('LinearGradient'));
assert(!frame.includes('overlayNote')); // No overlay or portrait fallback remains.
check(scene,['captionSize: CGFloat = 13','function: true, header: { EmptyView() }','maximumLines: 4','onExplain()','explanation = .init','title: showTitle ?','alert(item: $explanation)','atlas-function-explanation']);
assert(scene.indexOf('onExplain()')<scene.indexOf('explanation = .init'));
check(source('FunctionPlayer'),['onExplain: pause']);
assert.equal(source('FunctionPlayer').split('}.accessibilityIdentifier("atlas-function-player")')[1],prior('FunctionPlayer').split('}.accessibilityIdentifier("atlas-function-player")')[1]);
check(caption,['var maximumLines: Int? = nil','ForEach(values.indices','.hidden().accessibilityHidden(true).allowsHitTesting(false)']);
assert.equal((caption.match(/lineLimit\(maximumLines\)\.truncationMode\(\.tail\)\.fixedSize\(horizontal: false, vertical: true\)/g)||[]).length,2);
check(art,['plate?.markers.first(where: { $0.id == entry?.id })','plate?.owner == "cell-pancreatic-beta-cell"','x: 0.82, y: 0.44','subjectPoint: fullscreenSubject','subjectFocus: focus(full: full)','noteSize: CGFloat = 11','explanationSize: CGFloat = 14','entry == nil ? fullscreenCaption : caption','.atlasAnnotationSubject("atlas-concept-figure")','func scrollViewDidScroll','func scrollViewDidZoom','local.x - scroll.bounds.minX','content.convert(CGPoint','numbered: !full']);
assert(!art.includes('legendInset:'));assert(!source('LabeledArtwork').includes('legendInset'));
check(source('LabeledArtwork'),['content.convert(content.subject(parent.subjectFocus), to: scroll)','func scrollViewDidScroll','func scrollViewDidZoom','imageRect.minX + imageRect.width * focus.x']);
check(source('NotePosition'),['DispatchQueue.main.async','guard !scheduled','identity != identity','sent = nil','abs(sent.x - point.x) < 0.5','deliver(point)']);
const routing = s => s.split('      imageRect = plan.imageRect')[1].split('    private func drawGuides()')[0];
assert.equal(routing(source('LabeledArtwork')),routing(prior('LabeledArtwork')),'Number/highlight styling does not alter obstacle-aware leader routing');
check(panel,['atlas-simulation-figure','processArtwork','stageSize: CGFloat = 14','annotationScope: "atlas-simulation-figure"']);assert(!panel.includes('processArtwork.padding('));
const expectedProcess=prior('ProcessStages').replace('  let compact: Bool\n','  let compact: Bool\n  var annotationScope: String? = nil\n').replace('      .accessibilityIdentifier(compact ? "atlas-process-stage-" + String(stage) : "health-atlas-stage-" + entryID + "-" + String(stage))','      .accessibilityIdentifier(compact ? "atlas-process-stage-" + String(stage) : "health-atlas-stage-" + entryID + "-" + String(stage))\n      .atlasAnnotationTarget(annotationScope ?? "", active: annotationScope != nil && stage == current)');
assert.equal(source('ProcessStages'),expectedProcess);
check(source('RetinaPathView'),['atlas-retina-figure','GalaxySSIHealthAtlasReservedCaption(values: model.stages','atlasAnnotationTarget("atlas-retina-figure", active: index == stage)','ForEach(destinations']);
check(source('EndocrinePathView'),['atlas-endocrine-figure','frame(minHeight: 84, maxHeight: 110)','atlasAnnotationSubject','GalaxySSIHealthAtlasReservedCaption(values: atlas.model(entry).stages','atlas-endocrine-open-node']);
assert.equal(source('EndocrinePathView').split('  private func node(')[1],prior('EndocrinePathView').split('  private func node(')[1]);
assert.equal(source('RetinaPathView').split('  private func node(')[1],prior('RetinaPathView').split('  private func node(')[1].replace('      .accessibilityIdentifier("atlas-retina-node-" + String(index))','      .accessibilityIdentifier("atlas-retina-node-" + String(index))\n      .atlasAnnotationTarget("atlas-retina-figure", active: index == stage)'));
check(source('AgingPanel'),['atlas-aging-figure','GalaxySSIHealthAtlasReservedCaption(values: (0..<4).map','selection.explanation(language: language)','Text(t("diagram_scope"))','atlas-aging-study']);
check(research,['@State private var admeStage = 0','atlas-adme-figure','Double(admeStage) / 4','selected: { admeStage = $0 }','values: stages.map { t($0 + "_note") }','atlas-adme-explanation','Text(t("adme_scope"))']);
assert(!research.includes('Text(t(stage + "_note"))'));
assert.equal(research.split('      Divider()')[1],prior('Research').split('      Divider()')[1],'All drug model controls, numerical curves and aging handoff stay exact');
check(source('PhysiologyPanel'),['atlas-villus-figure','atlas-material-figure','Text(t("gut_section_area_views"))','GalaxySSIHealthAtlasMaterialResponseView.description']);
assert.equal(source('PhysiologyPanel').split('        if let forces = model.elbowForces')[1],prior('PhysiologyPanel').split('        if let forces = model.elbowForces')[1]);
const lifecycle=s=>s.split('.onReceive(timer)')[1].split('.onDisappear { pause() }')[0];
assert.equal(lifecycle(panel),lifecycle(prior('SimulationPanel')));
assert.equal(panel.split('  private var quantitative:')[1],prior('SimulationPanel').split('  private var quantitative:')[1]);
for(const name of ['ChapterClock','FunctionArtwork','FunctionCatalogue','FunctionViewport','Physiology','PhysiologyText','AgentContext','AgentHandoff','Aging','RetinaPath','EndocrinePath','MaterialResponseDrawing','MaterialResponseView','VillusAreaView','LessonNavigation','SearchNavigation','FilmPalette'])assert.equal(source(name),prior(name),name);
const tests='apps/ios/GalaxySSITests/GalaxySSIHealthAtlasLessonNavigationTests.swift';
check(read(tests),['testAtlasUniformSideColumnsAndMappedLeaderEndpoints','testFigureNoteLayoutAndLegacyBottomInsetDefaults','target: CGPoint(x: -10, y: 999)']);
const mapping={HealthAtlasAgingPanel:['AgingPanel','FigureFrame'],HealthAtlasAnatomyDialog:['Artwork','FigureFrame','LabeledArtwork','NotePosition'],HealthAtlasCaptionSizes:['SceneFrame'],HealthAtlasEndocrinePath:['EndocrinePathView','FigureFrame'],HealthAtlasFigureFrame:['FigureFrame','NotePosition'],HealthAtlasFunctionPlayer:['FunctionScene','FunctionPlayer','SceneFrame'],HealthAtlasLabeledImage:['LabeledArtwork','CalloutLayout'],HealthAtlasPhysiologyPanel:['PhysiologyPanel','FigureFrame'],HealthAtlasResearchPanel:['Research','ProcessStages','FigureFrame'],HealthAtlasRetinaPath:['RetinaPathView','FigureFrame'],HealthAtlasSimulationPanel:['SimulationPanel','ProcessStages','FigureFrame'],HealthAtlasUi:['Artwork','LabeledArtwork','FigureFrame']};
const files=inventory.files.map(file=>{
 const name=path.basename(file.path),key=name.replace(/\.kt$/,'');let kind,ios,note;
 if(mapping[key]){kind='native-production-port';ios=mapping[key].map(swift);note='Connected 12/16-point inset/gutter annotation frames, 580/280-point side thresholds, 40%/328-point side note or 72%/83% portrait note, short-window 44% side fallback and bounded 46/half-legend overlay. Native SwiftUI anchors target active process/retina nodes; UIKit conversion reports actual zoomed/scrolled image focus to the frame through the viewport anchor and post-layout deduplication. Function note is 13-point/two-line with matched hidden probes and paused full-copy alert. Structure/fullscreen/concept notes, endocrine image, aging, ADME, villus and material notes are integrated as applicable. Remove old bottom reservations from active labelled/process UI. Numerical/clock/model kernels stay exact. No native coordinates/pixels/gesture/timing acceptance.';}
 else if(file.path.includes('/androidTest/')){kind='android-device-source-reference';ios=[tests,'apps/ios/tools/check-atlas-in-image-notes-scope.cjs'];note=name+': source reference only. Review complete catalogue/alternate plate and chapter width/clearance sweeps, sampled leader pixels, note expansion/playhead retention, endocrine return helper and added screenshot routes. Swift geometry fixture sources were added but NOT executed. No iOS counterpart device sweep, pixels, screenshot or recreation evidence claimed.';}
 else{assert.equal(name,'build.gradle.kts');kind='android-version-only';ios=[];note='No iOS version bump or IPA. No localization delta in this Android PR.';}
 for(const target of ios)assert(fs.existsSync(path.join(root,target)),target);
 return{source:file.path,sourceSHA256:file.sha256,kind,ios,note};
});
assert.equal(files.filter(f=>f.kind==='native-production-port').length,12);assert.equal(files.filter(f=>f.kind==='android-device-source-reference').length,4);
for(const[suffix,value]of[['SOURCE_INVENTORY',inventory],['PORT_COVERAGE',{schema:1,source:inventory.source,verification:'source-contracts-only-not-native-execution',files}]]){
 const file='apps/ios/ANDROID_4446_'+suffix+'.json',content=JSON.stringify(value,null,2)+'\n';
 if(process.argv.includes('--write'))fs.writeFileSync(path.join(root,file),content);else assert.equal(read(file),content);
}
if(process.argv.includes('--checks'))cp.execFileSync(process.execPath,[path.join(__dirname,'check-atlas-integrated-figures-scope.cjs'),'--checks'],{cwd:root,stdio:'inherit'});
console.log('Android #4446: 17 original hashes/dispositions; connected responsive notes, native subject/active-node coordinate wiring, matched two-line probes and paused full-copy expansion source contracts. Not native Swift, XCTest, layout, coordinates or pixels.');
