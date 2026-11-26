// Source contracts, not Swift/OSLog/model/provider execution or latency evidence.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'e5c54f06c49f81cd4dd31d5387533cffc44311a5';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', base + ':' + app + file + '.swift'],
  {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
const hooks = [
  ['  private let timingClock: () -> Int64\n', ''],
  ['  private let timingSink: CloudModelRoundTiming.Sink\n', ''],
  ['    elapsedMillis: @escaping () -> Int64 = CloudConversationStreamEngine.defaultElapsedMillis,\n    timingClock: @escaping () -> Int64 = CloudModelRoundTiming.monotonicMillis,\n    timingSink: @escaping CloudModelRoundTiming.Sink = CloudModelRoundTiming.log',
    '    elapsedMillis: @escaping () -> Int64 = CloudConversationStreamEngine.defaultElapsedMillis'],
  ['    self.timingClock = timingClock\n    self.timingSink = timingSink\n', ''],
  ['        let roundTiming = CloudModelRoundTiming(requestId: requestId, round: currentRound,\n          route: useCompleteJSON ? .compatibility : .streaming, finalRound: finalRound,\n          clock: timingClock, sink: timingSink)\n', ''],
  ['        roundTiming.request(inputCharacters: roundRequest.bodyJson.utf16.count)\n', ''],
  ['          var providerCancelled = false\n          defer { roundTiming.finish(completed: roundCompleted, failed: roundFailure != nil,\n            cancelled: providerCancelled || Task.isCancelled) }\n', ''],
  ['                roundTiming.activity(.text)\n', ''],
  ['                roundTiming.activity(.tool)\n', ''],
  ['            providerCancelled = true\n', ''],
  ['            let citationStarted = timingClock()\n', ''],
  ['            roundTiming.citationValidation(startedAtMillis: citationStarted, requiresRepair: repairPrompt != nil)\n', '']
];
let engine = require('./check-web-fallback-scope.cjs').retainedFallbackFile(app + 'CloudConversationStreamEngine.swift', read(app + 'CloudConversationStreamEngine.swift'));
for (const [before, after] of hooks) {
  assert.equal(engine.split(before).length, 2, 'One declared timing hook: ' + before);
  engine = engine.replace(before, after);
}
assert.equal(engine, old('CloudConversationStreamEngine'),
  'Outside passive timing hooks retain admission, permission, cancellation, deadline, preview, citation, tool callback, recovery and result policies');
const timing = read(app + 'CloudModelRoundTiming.swift');
for (const token of ['DispatchTime.now().uptimeNanoseconds / 1_000_000', 'subtractingReportingOverflow',
  'end <= start ? 0', 'delta.overflow ? Int64.max', 'guard !requested, !finished',
  'guard requested, !firstActivity, !finished', 'guard !finished',
  'SHA256.hash(data: Data(requestId.utf8))', 'privacy: .private(mask: .hash)', 'category: "web-latency"']) assert(timing.includes(token), token);
assert(!timing.includes('Date(') && !timing.includes('URLSession') && !timing.includes('UserDefaults'));
const sample = timing.slice(timing.indexOf('  struct Sample:'), timing.indexOf('  typealias Sink'));
for (const token of ['requestId', 'body', 'prompt', 'endpoint', 'key', 'header']) assert(!sample.includes(token), token);
const tests = read('apps/ios/GalaxySSITests/CloudModelRoundTimingTests.swift');
assert.equal((tests.match(/func test/g) || []).length, 4);
const integration = read('apps/ios/GalaxySSITests/CloudConversationStreamEngineTests.swift');
for (const name of ['FollowsActualProviderEventsWithoutChangingTheAnswer', 'SeparatesUnsupportedStreamAndCompatibilityRounds',
  'RecordsFailedAndInterruptedProviderRounds', 'RecordsToolActivityThenCitationValidationOnRealEnginePath'])
  assert(integration.includes('func testModelTiming' + name + '('), name);
const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['CloudModelRoundTiming', 'CloudModelRoundTimingTests'])
  assert.equal(project.split(name + '.swift in Sources */').length, 3, name);
console.log('iOS model-round preparation/activity/outcome/citation timing source contracts passed; not native or latency acceptance');
