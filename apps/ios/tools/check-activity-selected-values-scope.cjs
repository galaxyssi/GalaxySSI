// Source/resource contracts only. These are not native chart, gesture or XCTest execution.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../../..'),sha='d858b91af063b6a77960480d4acf1c1398f8a620',base='28718cbf10eaf67b5b836944cc0d039ca5682bd6';
const git=args=>cp.execFileSync('git',args,{cwd:root,maxBuffer:16_000_000});
const read=file=>fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n'),source=name=>read('apps/ios/GalaxySSI/'+name+'.swift');
const prior=name=>git(['show',base+':apps/ios/GalaxySSI/'+name+'.swift']).toString().replace(/\r\n/g,'\n');
const check=(text,tokens)=>{for(const token of tokens)assert(text.includes(token),token);};
const changed=git(['diff','--name-status','--no-renames',sha+'^1',sha]).toString().trim().split(/\r?\n/).map(line=>line.split('\t'));
assert.equal(changed.length,8);
const inventory={schema:1,source:{androidPR:4493,headCommit:sha,stateAtReview:'OPEN',note:'Pinned open PR head, not a merged Android commit.'},files:changed.map(([status,file])=>({path:file,status,sha256:crypto.createHash('sha256').update(git(['show',sha+':'+file])).digest('hex')}))};
if(fs.existsSync(path.join(root,'apps/ios/ANDROID_4497_PORT_COVERAGE.json'))){
 assert.deepEqual(JSON.parse(read('apps/ios/ANDROID_4493_SOURCE_INVENTORY.json')),inventory);
 cp.execFileSync(process.execPath,[path.join(__dirname,'check-activity-day-scrubbing-scope.cjs'),...(process.argv.includes('--checks')?['--checks']:[])],{cwd:root,stdio:'inherit'});
 console.log('Android #4493 point-only interaction contracts are superseded explicitly by #4497 calendar-day scrubbing; historical source inventory retained.');
 process.exit(0);
}
const model=source('GalaxySSIHealthActivityComparison'),view=source('GalaxySSIHealthActivityComparisonView'),chart=source('GalaxySSIHealthActivityChart');
check(model,['func dateTickIndices(limit: Int)','min(max(2, min(7, limit)), pairs.count)','$0 * (pairs.count - 1) / (count - 1)','Pair(id: index, day: day, current: totals','max(pair.current ?? 0, row.total)']);
for(const forbidden of ['previousDay','currentPaired','previousPaired','changePercent'])assert(!model.includes(forbidden));
assert.equal(model.split('  // Display-only projection:')[1],prior('GalaxySSIHealthActivityComparison').split('  // Display-only projection:')[1],'Motion projection/checkpoint migration unchanged');
for(const name of ['GalaxySSIHealthActivityHistoryStore','GalaxySSIHealthMotionState','GalaxySSIHealthMotionController','GalaxySSIHealthRecords'])assert.equal(source(name),prior(name),name+' storage/tracking/privacy unchanged');
check(view,['window.pairs.first?.day','history.read(kind: selected, first: firstKey, last: lastKey)','fresh.derivesOverview == true, fresh.privacyEvents?.last?.id == consent','request == id, canRead','UIApplication.shared.isProtectedDataAvailable','store.profile.identityFingerprint == records.owner','@SceneStorage private var selectedDay','records.owner + "."','selectedDay = ""; reload()','GalaxySSIHealthActivityChart(result: comparison','scaledValue(for: 220)']);
assert(!view.includes('chartData'));assert(!view.includes('showsData'));assert(!view.includes('previousDay'));
assert.equal(view.split('  private func motionChanged(')[1].split('  private func clear(')[0],prior('GalaxySSIHealthActivityComparisonView').split('  private func motionChanged(')[1].split('  private func clear(')[0],'Live update/rollover correlation unchanged');
check(chart,['ceil(Double(result.pairs.compactMap(\\.current).max() ?? 0) / divisor / 3)','maximum = interval * 3 * divisor','pairs.count == 1 ? area.midX','dateTickIndices(limit:','guard pair.current != nil else { previous = nil; continue }','context.addLine(to: CGPoint(x: point(index).x, y: bottom))','drawTooltip(label(index)','distance($0) <= 22','dragged = true','touchesCancelled','accessibilityActivate','accessibilityIncrement','accessibilityDecrement','.keyboardRightArrow','.keyboardLeftArrow','tap.cancelsTouchesInView = false','outsideTap.view?.removeGestureRecognizer','!bounds.contains(touch.location(in: self))','shouldRecognizeSimultaneouslyWith','table: "HealthActivitySelection"']);
assert(!chart.includes('systemBlue'));assert(!chart.includes('DragGesture'));assert(!chart.includes('touchesMoved')||!chart.split('override func touchesMoved')[1].split('override func touchesEnded')[0].includes('select('),'Scrubbing belongs to the separate Android #4497 port');
const tests='apps/ios/GalaxySSITests/GalaxySSIHealthActivityComparisonTests.swift';
check(read(tests),['testSelectedPeriodPreservesUnknownAndZeroWithoutPreviousValues','testDateTicksIncludeBothEndsWithoutDuplicates','testChartAccessibilitySelectsRecordedDaysIncludingZeroAndSkipsMissing','testDayAlignmentUsesCalendarNotFixed86400SecondWindows']);
const coverage={schema:1,source:inventory.source,verification:'source-and-resource-contracts-not-native-execution',files:inventory.files.map(file=>{
 const name=path.basename(file.path);let kind,ios,note;
 if(name==='HealthActivityComparison.kt'){kind='native-production-port';ios=['GalaxySSIHealthActivityComparison.swift'];note='Selected-range-only dated values, nil versus zero, calendar tick endpoints and monotonic live overlay; no previous-period data.';}
 else if(name==='HealthActivityComparisonActivity.kt'){kind='native-production-port';ios=['GalaxySSIHealthActivityComparisonView.swift','GalaxySSIHealthActivityChart.swift'];note='Narrow history reads to the selected range; remove all-values sheet; owner-scoped SceneStorage for kind/range/date selection, clear on kind/range/timezone/identity changes; keep protected-data/consent/request checks and live rollover behavior.';}
 else if(name==='HealthActivityComparisonChart.kt'){kind='native-production-port';ios=['GalaxySSIHealthActivityChart.swift'];note='Current-only green curve, current-only rounded Y scale, date ticks, nil gaps/visible zero, one-day centering, point hit testing, guide/ring/wrapping inline tooltip, blank/outside tap clearing, drag cancellation, VoiceOver and keyboard recorded-point selection. No native gesture/pixel/layout claim.';}
 else if(file.path.includes('/res/')){kind='exact-resource-port';ios=['en.lproj/HealthActivitySelection.strings','zh-Hans.lproj/HealthActivitySelection.strings'];note='One exact changed source pair per locale, positional object format adaptation only.';}
 else if(file.path.includes('/test/')||file.path.includes('/androidTest/')){kind='native-fixture-source-reference';ios=[];note='Android date ticks/current-only range, missing-vs-zero, live overlay, cycling and steps point switch/dismissal/accessibility/guide sources reviewed. iOS model/accessibility fixture sources updated but NOT run. No device screenshot or native pixel/layout/gesture acceptance claimed.';}
 else{assert.equal(name,'build.gradle.kts');kind='android-version-only';ios=[];note='No iOS version bump or IPA.';}
 const targets=ios.map(name=>'apps/ios/GalaxySSI/'+name);if(kind==='native-fixture-source-reference')targets.push(tests);for(const target of targets)assert(fs.existsSync(path.join(root,target)),target);
 return{source:file.path,sourceSHA256:file.sha256,kind,ios:targets,note};
})};
for(const[suffix,value]of[['SOURCE_INVENTORY',inventory],['PORT_COVERAGE',coverage]]){
 const file='apps/ios/ANDROID_4493_'+suffix+'.json',content=JSON.stringify(value,null,2)+'\n';
 if(process.argv.includes('--write'))fs.writeFileSync(path.join(root,file),content);else assert.equal(read(file),content);
}
if(process.argv.includes('--checks'))cp.execFileSync(process.execPath,[path.join(__dirname,'import-activity-selected-value-text.cjs'),'--check'],{cwd:root,stdio:'inherit'});
console.log('Android #4493: eight pinned source-file dispositions, selected-period-only model/query, chart interaction and resource source contracts; not native execution.');
