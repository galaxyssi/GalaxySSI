// Source/resource contracts only, not UIKit recognizer or native chart execution.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../../..'),sha='6071f168d789cc0657306042b9735a512bd04e64',androidBase='d858b91af063b6a77960480d4acf1c1398f8a620',base='a95357af78c71b82a60f2460e4601e3b95956313';
const git=args=>cp.execFileSync('git',args,{cwd:root,maxBuffer:16_000_000});
const read=file=>fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n'),source=name=>read('apps/ios/GalaxySSI/'+name+'.swift');
const prior=name=>git(['show',base+':apps/ios/GalaxySSI/'+name+'.swift']).toString().replace(/\r\n/g,'\n');
const check=(text,tokens)=>{for(const token of tokens)assert(text.includes(token),token);};
assert.equal(git(['rev-parse',sha+'^1']).toString().trim(),androidBase);
const changed=git(['diff','--name-status','--no-renames',androidBase,sha]).toString().trim().split(/\r?\n/).map(line=>line.split('\t'));
assert.equal(changed.length,8);
const inventory={schema:1,source:{androidPR:4497,headCommit:sha,incrementalAndroidBase:androidBase,stateAtReview:'OPEN',note:'Pinned open follow-up head based on Android #4493; not a merged Android commit.'},files:changed.map(([status,file])=>({path:file,status,sha256:crypto.createHash('sha256').update(git(['show',sha+':'+file])).digest('hex')}))};
const model=source('GalaxySSIHealthActivityComparison'),view=source('GalaxySSIHealthActivityComparisonView'),chart=source('GalaxySSIHealthActivityChart');
check(model,['func nearestDayIndex(fraction: Double)','fraction.isFinite','Int((min(1, max(0, fraction)) * Double(pairs.count - 1)).rounded())']);
assert.equal(model.split('  func dateTickIndices(')[1],prior('GalaxySSIHealthActivityComparison').split('  func dateTickIndices(')[1],'Date ranges, totals, live overlay and migration unchanged');
for(const name of ['GalaxySSIHealthActivityHistoryStore','GalaxySSIHealthMotionState','GalaxySSIHealthMotionController','GalaxySSIHealthRecords']){
 let current=source(name);
 if(name==='GalaxySSIHealthRecords'&&fs.existsSync(path.join(root,'apps/ios/ANDROID_4276_PORT_COVERAGE.json'))){
   const binding=current.split('  func bindLocalCareAgentDiscussion(')[1]?.split('  func overviewDiscussionConcern(')[0];assert(binding);
   current=current.replace('  func bindLocalCareAgentDiscussion('+binding,'');
 }
 assert.equal(current,prior(name),name+' unchanged except the explicitly isolated #4276 conversation-binding method, covered by its own checker');
}
check(view,['@State private var trackingTouch = false','onTracking: { active in','trackingTouch = active','if !active { renderLive() }','guard canRead, let loaded, !trackingTouch else { return }','failure = nil; trackingTouch = false']);
assert.equal(view.split('  private func reload()')[1].split('  private func motionChanged(')[0],prior('GalaxySSIHealthActivityComparisonView').split('  private func reload()')[1].split('  private func motionChanged(')[0],'Selected-only read, consent and request correlation unchanged');
check(chart,['import UIKit.UIGestureRecognizerSubclass','private var days: [Int]','days.first { key($0) == selectedDay }','?? area.midY','"health_activity_day_unrecorded"','"No record"','if result.pairs[index].current != nil','timeline.scrubbing || onTimeline(p)','result.nearestDayIndex(fraction:','p.x >= area.minX - 10','p.y >= area.minY - 10','p.y <= bounds.height','scroll.panGestureRecognizer.require(toFail: timeline)','dx > dy, onTimeline(origin)','state = .failed; finish()','scrubbing = true; state = .began','else if scrubbing { state = .changed }','touchesCancelled','touches.count == 1','private func abort()','DispatchQueue.main.async { callback(false) }','override func reset() { finish(); scrubbing = false','tap.cancelsTouchesInView = false','outsideTap.view?.removeGestureRecognizer','gestureRecognizer === outsideTap || other === outsideTap']);
assert(!chart.includes('distance($0) <= 22'));assert(!chart.includes('private var recorded'));
assert.equal(chart.split('    let attributes: [NSAttributedString.Key: Any] = [.font: axisFont')[1].split('    if let index = selectedIndex {')[0],prior('GalaxySSIHealthActivityChart').split('    let attributes: [NSAttributedString.Key: Any] = [.font: axisFont')[1].split('    if let index = selectedIndex {')[0],'Axes, selected-range scale and date ticks unchanged');
assert.equal(chart.split('  private func drawTooltip(')[1].split('  private func select(')[0],prior('GalaxySSIHealthActivityChart').split('  private func drawTooltip(')[1].split('  private func select(')[0],'Tooltip layout unchanged');
const tests='apps/ios/GalaxySSITests/GalaxySSIHealthActivityComparisonTests.swift';check(read(tests),['testHorizontalFractionsSelectCalendarDatesIncludingGaps','testChartAccessibilityVisitsMissingDatesWithoutInventingZero','fraction: 0.34','fraction: 0.47','fraction: .nan']);
const coverage={schema:1,source:inventory.source,verification:'source-and-resource-contracts-not-native-execution',files:inventory.files.map(file=>{
 const name=path.basename(file.path);let kind,ios,note;
 if(name==='HealthActivityComparison.kt'){kind='native-production-port';ios=['GalaxySSIHealthActivityComparison.swift'];note='Nearest calendar index clamps finite horizontal fraction and rounds; one-day safe. Missing dates participate without becoming zeros.';}
 else if(name==='HealthActivityComparisonActivity.kt'){kind='native-production-port';ios=['GalaxySSIHealthActivityComparisonView.swift','GalaxySSIHealthActivityChart.swift'];note='Freeze displayed live overlay while touch tracking is active and apply latest state asynchronously after completion/cancellation. Keep selected-range query and existing owner/consent/protected-data/cancellation checks.';}
 else if(name==='HealthActivityComparisonChart.kt'){kind='native-production-port';ios=['GalaxySSIHealthActivityChart.swift'];note='Timeline tap anywhere above/below a point selects by X; horizontal directional recognizer scrubs continuously and clamps endpoints. Fail vertical drags for parent scrolling, ignore multitouch, finalize cancellation. Missing-day guide/readout at mid-height without fake dot; date-by-date VoiceOver/keyboard traversal including missing values; blank/outside clear. Native UIKit gestures have not been executed.';}
 else if(file.path.includes('/res/')){kind='exact-resource-port';ios=['en.lproj/HealthActivityScrubbing.strings','zh-Hans.lproj/HealthActivityScrubbing.strings'];note='One exact changed no-record pair per locale. Existing #4493 point-value table unchanged.';}
 else if(file.path.includes('/test/')||file.path.includes('/androidTest/')){kind='native-fixture-source-reference';ios=[];note='Reviewed Android clamping/nearest-date, above-point taps, both drag directions, missing/zero, vertical-scroll rejection and clearing sources. iOS model/accessibility fixture sources updated but NOT executed; no native layout/gesture/VoiceOver/pixel/device acceptance claimed.';}
 else{assert.equal(name,'build.gradle.kts');kind='android-version-only';ios=[];note='No iOS version bump or IPA.';}
 const targets=ios.map(name=>'apps/ios/GalaxySSI/'+name);if(kind==='native-fixture-source-reference')targets.push(tests);for(const target of targets)assert(fs.existsSync(path.join(root,target)),target);
 return{source:file.path,sourceSHA256:file.sha256,kind,ios:targets,note};
})};
for(const[suffix,value]of[['SOURCE_INVENTORY',inventory],['PORT_COVERAGE',coverage]]){
 const file='apps/ios/ANDROID_4497_'+suffix+'.json',content=JSON.stringify(value,null,2)+'\n';
 if(process.argv.includes('--write'))fs.writeFileSync(path.join(root,file),content);else assert.equal(read(file),content);
}
if(process.argv.includes('--checks'))for(const name of ['import-activity-selected-value-text.cjs','import-activity-scrubbing-text.cjs'])cp.execFileSync(process.execPath,[path.join(__dirname,name),'--check'],{cwd:root,stdio:'inherit'});
console.log('Android #4497: eight pinned incremental source-file dispositions; calendar-day scrubbing, missing-vs-zero and live-update/scroll contracts. Source/resource evidence, not native gesture execution.');
