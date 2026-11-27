// Source-only contracts. The conversation entry, results UI and linked reminders are not covered here.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n');
const core = read('apps/ios/GalaxySSI/GalaxySSIHealthAgentLab.swift');
for (const token of ['reading.metric.laboratory, !reading.deleted, reading.isValid, reading.measuredAt <= through',
  'eligible.contains { $0.reportSource != nil }', 'source.filter { $0.measuredAt >= day }',
  'case results, abnormal, note, remind', 'range.position == .notComparable',
  'self.owner == owner, self.policy == policy, self.through == through',
  'uptime >= deadline - 60, uptime <= deadline', 'used = true',
  'try persistLocalLabAudit(archive)', 'guard permitted else { throw Failure.permission }',
  'GalaxySSIHealthAgentLab.Policy(archive) == policy', 'archive.current.first(where: { $0.id == expected.id }) == expected',
  'try write(updated)', 'UIApplication.shared.isProtectedDataAvailable']) assert(core.includes(token), token);
const audit = core.slice(core.indexOf('  struct Audit:'), core.indexOf('  struct Snapshot'));
assert(!/reading|notes|sourceID|recordID|value:/.test(audit), 'Audit must not duplicate measurement content');
assert(!/CloudModelClient|MessageCoordinator|conversationStreamingRequest|queuePrivateHealth/.test(core),
  'The local read foundation must not submit health content to a model');
for (const name of ['GalaxySSIHealthAgentLab', 'GalaxySSIHealthAgentLabTests']) {
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' registered');
  const source = read(`apps/ios/${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`);
  assert(!/\p{Script=Han}/u.test(source), 'Localized strings belong in resources');
}
assert.equal((read('apps/ios/GalaxySSITests/GalaxySSIHealthAgentLabTests.swift').match(/func test/g) || []).length, 8);
console.log('Local lab foundation source contracts passed; UI integration pending, no Swift compilation or XCTest execution.');
