// Source contracts only; no Swift, storage, model, network or concurrency execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '70ebfc8b70c9fdd797f0dd40ae8b39026ab9ec91';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length); assert(b > a, last); return s.slice(a, b);
}
function retainedEngine(s) {
  if (!s.includes('  private let toolJournal: AgentModelLoopJournal')) return s;
  assert.equal(s, show(approved, app + 'CloudConversationStreamEngine.swift'), 'Exact cloud invocation envelope only');
  return show(base, app + 'CloudConversationStreamEngine.swift');
}
function retainedRounds(s) {
  if (!s.includes('  static func restoreResult(_ output: String, context: CloudConversationToolExecutionContext)')) return s;
  assert.equal(s, show(approved, app + 'CloudConversationStreamToolRounds.swift'), 'Exact saved annotation restoration only');
  return show(base, app + 'CloudConversationStreamToolRounds.swift');
}
module.exports = {retainedEngine, retainedRounds};
if (require.main === module) {
  const engineFile = app + 'CloudConversationStreamEngine.swift', roundsFile = app + 'CloudConversationStreamToolRounds.swift';
  const helperFile = app + 'CloudToolInvocationJournal.swift', testFile = 'apps/ios/GalaxySSITests/CloudToolInvocationJournalTests.swift';
  const engine = read(engineFile), rounds = read(roundsFile), helper = read(helperFile), tests = read(testFile);
  assert.equal(retainedEngine(engine), show(base, engineFile)); assert.equal(retainedRounds(rounds), show(base, roundsFile));
  assert.equal(helper, show(approved, helperFile)); assert.equal(tests, show(approved, testFile));
  const native = section(engine, '                let output: String\n', '                return output\n')
    .split('\n').map(line => line.startsWith('  ') ? line.slice(2) : line).join('\n');
  assert.equal(native, section(show(base, engineFile), '              let output: String\n', '              return ToolExecutionOutcome('),
    'Existing native/recall/publication/milestone dispatch unchanged inside the claim');
  for (const name of ['AgentModelLoopJournal', 'CloudWebGrounding', 'CloudResearchRuntimeBudget', 'AgentDataDisclosureLedger', 'CloudModelStreamProviderAdapters'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' retained');
  for (const token of ['binding.owner', 'binding.contactID', 'binding.turnID', 'binding.requestID',
    'requestSHA256', 'collaborationOwner', 'binding.scope', 'decode(Input.self, from: saved) == input',
    'result.inputSHA256 == hash', 'try restoreResult(result.output)', 'Outcome(output: result.output, replayed: true)',
    'Outcome(output: output, replayed: false)', 'cloud_tool_outcome_unknown']) assert(helper.includes(token), token);
  assert(helper.indexOf('try records.write("cloud-tool-input"') < helper.indexOf('output = try await operation()'));
  assert(helper.indexOf('output = try await operation()') < helper.indexOf('try records.write("cloud-tool-result"'));
  assert(helper.lastIndexOf('try await validateOwner()') > helper.indexOf('try records.write("cloud-tool-result"'));
  assert(!/\.remove\(|\.delete\(|clearCancellation|grantedPermissions|grantedConsents|UUID\(/.test(helper));
  for (const token of ['!$0.privateMode && !$0.trackingPaused', 'retainToolInvocations ? toolJournal : transientToolJournal',
    'store.profile.identityFingerprint == disclosureOwner', 'store.canReadAgentTranscript',
    'UIApplication.shared.isProtectedDataAvailable', '!PhoneExecutionAuthority.isCancelled(taskId: turnId)',
    'current?.collaborationRoster == toolSession?.collaborationRoster', 'current?.privateMode == toolSession?.privateMode',
    'current?.trackingPaused == toolSession?.trackingPaused', 'invocationBinding.slot = start + offset',
    '!outcome.replayed { await onObservation?', 'failureCode: "CLOUD_TOOL_RECOVERY_REQUIRED"',
    'object["new_execution"] = .bool(false)', '"fresh_observation": .bool(false)']) assert(engine.includes(token), token);
  assert(engine.indexOf('let toolSession =') < engine.indexOf('      while true {'), 'Privacy store selection stays fixed for the stream');
  const restore = section(rounds, '  static func restoreResult(', '  private static func recordRendered(');
  for (const token of ['position < context.images.count', 'digest.utf8.count == 64', 'digest.utf8.allSatisfy',
    'size.int64Value <= 12 * 1_024 * 1_024', 'data.count <= 12 * 1_024 * 1_024', 'joined() == digest',
    'recordRendered(data: data, digest: digest']) assert(restore.includes(token), token);
  assert(!/render\(|write\(|URLSession/.test(restore), 'Restoration cannot reexecute annotation or download a replacement');
  assert.equal(rounds.slice(rounds.indexOf('  static func artifactSuffix(')),
    show(base, roundsFile).slice(show(base, roundsFile).indexOf('  static func artifactSuffix(')), 'Existing selection/discard/directory and tool contracts retained');
  let negatives = 0;
  function rejected(source, token, checker) {
    assert(source.includes(token), token); assert.throws(() => checker(source.replace(token, '')), assert.AssertionError); negatives++;
  }
  for (const token of ['decode(Input.self, from: saved) == input', 'guard let data = try records.read("cloud-tool-result")',
    'result.inputSHA256 == hash', 'try records.write("cloud-tool-input", data: JSONEncoder().encode(input))',
    'try records.write("cloud-tool-result", data: JSONEncoder().encode(Result(inputSHA256: hash, output: output)))',
    'try await validateOwner()', 'try Task.checkCancellation()', 'try restoreResult(result.output)'])
    rejected(helper, token, s => assert.equal(s, show(approved, helperFile)));
  for (const token of ['!$0.privateMode && !$0.trackingPaused', 'retainToolInvocations ? toolJournal : transientToolJournal',
    'store.profile.identityFingerprint == disclosureOwner', 'current?.trackingPaused == toolSession?.trackingPaused',
    'CloudToolInvocationJournal(journal: journal).execute(', '!outcome.replayed { await onObservation?',
    'failureCode: "CLOUD_TOOL_RECOVERY_REQUIRED"', 'object["new_execution"] = .bool(false)']) rejected(engine, token, retainedEngine);
  for (const token of ['position < context.images.count', 'digest.utf8.allSatisfy', 'size.int64Value <= 12 * 1_024 * 1_024',
    'joined() == digest']) rejected(rounds, token, retainedRounds);
  assert.equal((tests.match(/  func test/g) || []).length, 15);
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => /CloudToolInvocationJournal(?:Tests)?\.swift/.test(line));
  assert.equal(registrations(read(projectFile)).length, 8);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  assert(!/\p{Script=Han}/u.test(helper + tests));
  console.log(`Cloud pre-execution claims, replay provenance, retained dispatch/artifact policies and ${negatives} negative source mutations checked; fifteen Swift fixtures authored, not executed.`);
}
