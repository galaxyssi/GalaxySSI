// Source contracts only; does not execute Swift/ICU, routing, models or tools.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '8f128dcd8c06298a1e1b28b85eb42dfcf422820a';
const android = '0f1c2848515869c7fdf01c3e51d04631db06edbf';
const policyFile = app + 'AgentDeterministicLocalShortcutPolicy.swift', testFile = 'apps/ios/GalaxySSITests/AgentDirectNativeToolPlannerTests.swift';
const clean = s => s.replace(/\r\n/g, '\n'), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8')), memo = new Map();
function git(args) { return clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024})); }
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, git(['show', key]));
  return memo.get(key);
}
function once(source, from, to) { assert.equal(source.split(from).length, 2, from); return source.replace(from, to); }
function validate(file, source) {
  assert([policyFile, testFile].includes(file));
  assert.equal(source, show(approved, file), 'Complete reviewed status signal source: ' + file);
}
function retained(file, source) {
  if (![policyFile, testFile].includes(file) || source === show(base, file)) return source;
  validate(file, source); return show(base, file);
}
module.exports = {retained};
if (require.main === module) {
  const policy = read(policyFile), tests = read(testFile);
  validate(policyFile, policy); validate(testFile, tests);
  const original = show(base, policyFile), lines = original.split('\n');
  const index = lines.findIndex(line => line.includes('private static let readSignal ='));
  assert(index >= 0);
  const signal = lines.slice(index, index + 2).join('\n');
  let corrected = once(signal, '|how much|if|when|unless)', '|how much)');
  corrected = once(corrected, '|\\u{5982}\\u{679c}"', '"');
  const expected = once(original, signal, corrected);
  assert.equal(policy, expected, 'Only the exact English/Chinese conditional signals are removed');
  const androidFile = 'apps/android/app/src/main/java/com/galaxyssi/chat/AgentDeviceStatusShortcutCoverage.kt';
  const before = show(android + '^1', androidFile).split('\n').find(line => line.includes('private val READ_REQUEST ='));
  const after = show(android, androidFile).split('\n').find(line => line.includes('private val READ_REQUEST ='));
  assert(before && after);
  assert(before.includes('|if|when|unless)') && before.includes('\\u5982\\u679c'));
  assert(!after.includes('|if|when|unless)') && !after.includes('\\u5982\\u679c'));
  assert(after.includes('read|check|show|get|current|available|remaining|free|status|how much'));
  const changes = git(['diff', '--unified=0', android + '^1', android, '--', androidFile]).split('\n');
  assert.deepEqual(changes.filter(line => line.startsWith('+') && !line.startsWith('+++')), ['+' + after]);
  assert.deepEqual(changes.filter(line => line.startsWith('-') && !line.startsWith('---')), ['-' + before]);
  assert.equal((tests.match(/  func test/g) || []).length - (show(base, testFile).match(/  func test/g) || []).length, 6);
  for (const file of ['AgentDirectNativeToolPlanner.swift', 'AgentTaskIntent.swift', 'AgentPhoneRuntimePolicy.swift'])
    assert.equal(read(app + file), show(base, app + file), file + ': direct effects, intent and runtime routing retained');
  const mutations = [
    [policyFile, '|how much)', '|how much|if)'],
    [policyFile, '|how much)', '|how much|when)'],
    [policyFile, '|how much)', '|how much|unless)'],
    [policyFile, '|\\u{72c0}\\u{614b}"', '|\\u{72c0}\\u{614b}|\\u{5982}\\u{679c}"'],
    [policyFile, '!AgentDirectNativeToolPlanner.isCompleteDeviceStatusRead(text)', 'AgentDirectNativeToolPlanner.isCompleteDeviceStatusRead(text)'],
    [policyFile, '!hasExplicitDesktopTarget(text)', 'hasExplicitDesktopTarget(text)'],
    [policyFile, 'if matches(readSignal, in: text)', 'if true'],
    [testFile, 'XCTAssertFalse(AgentDeviceStatusShortcutCoverage.requiresReasoning(goal), goal)', 'XCTAssertTrue(AgentDeviceStatusShortcutCoverage.requiresReasoning(goal), goal)']
  ];
  for (const [file, from, to] of mutations) {
    const source = read(file); assert(source.includes(from), from);
    assert.throws(() => validate(file, source.replace(from, to)), undefined, from);
  }
  console.log('Android #3996 exact signal change and 8 negative source mutations checked; six Swift fixtures authored, not executed.');
}
