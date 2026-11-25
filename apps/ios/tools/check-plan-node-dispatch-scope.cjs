// Source contracts only; not a native persistence, dispatch or recovery test.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../../..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n');
function retainedServices(source) {
  const replacements = [
    ['    let dispatchCheckpoints = journaledPlan.checkpoints\n', ''],
    ['          guard let key = nodeKeys[index],\n                let checkpoint = dispatchCheckpoints.last(where: { $0.id == key.checkpointId }) else {',
      '          guard let key = nodeKeys[index] else {'],
    ['switch try nodeJournal.claim(key, action: executionActions[index], checkpoint: checkpoint) {', 'switch try nodeJournal.claim(key) {']
  ];
  if (!source.includes(replacements[0][0])) return source;
  for (const [before, after] of replacements) {
    assert.equal(source.split(before).length, 2, 'Exactly one narrowly scoped dispatch hook: ' + before);
    source = source.replace(before, after);
  }
  return source;
}
module.exports = { retainedServices };
if (require.main === module) {
  const base = '4adcd727ffd5d3a62301ce5c8132f1432755abb0';
  const old = file => cp.execFileSync('git', ['show', `${base}:${file}`], {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}).replace(/\r\n/g, '\n');
  const file = 'apps/ios/GalaxySSI/GalaxySSIServices.swift';
  const source = read(file);
  assert.equal(retainedServices(source), old(file), 'Only parallel dispatch claim receives final input/checkpoint; all service routing, permission, results and recovery unchanged');
  const journal = read('apps/ios/GalaxySSI/AgentPlanNodeJournal.swift');
  const oldJournal = old('apps/ios/GalaxySSI/AgentPlanNodeJournal.swift');
  const observeStart = '  func observe(_ key: AgentPlanNodeKey) throws -> AgentPlanNodeClaim? {';
  assert.equal(journal.slice(journal.indexOf(observeStart)), oldJournal.slice(oldJournal.indexOf(observeStart)),
    'Observe/result/update/clear/decrypt/persist semantics remain unchanged');
  const keyEnd = 'struct AgentPlanNodeObservation:';
  assert.equal(journal.slice(0, journal.indexOf(keyEnd)), oldJournal.slice(0, oldJournal.indexOf(keyEnd)),
    'Original source specification/checkpoint key and recovery identity unchanged');
  for (const token of ['var dispatch: AgentPlanNodeDispatch? = nil', 'action.id == key.actionId',
    'checkpoint.id == key.checkpointId', 'checkpoint.actionId == key.actionId, checkpoint.status == .active',
    'dispatch_intent;', 'return try claim(key, dispatch: dispatch)', 'dispatch: dispatch',
    'try persist(entries)\n    return .acquired', 'return entry.dispatch']) assert(journal.includes(token), token);
  assert(journal.indexOf('if let entry = entries[key.journalId]') < journal.indexOf('dispatch: dispatch\n'));
  assert(!journal.includes('entry.dispatch ='), 'Existing pending/observed entries cannot be retroactively replaced');
  const operation = source.slice(source.indexOf('    let dispatchCheckpoints ='), source.indexOf('    let dispatchCheckpoints =') + 4500);
  assert(operation.indexOf('nodeJournal.claim(key, action: executionActions[index], checkpoint: checkpoint)') < operation.indexOf('executor.execute(action: executionActions[index]'));
  const tests = read('apps/ios/GalaxySSITests/AgentExecutionContinuityTests.swift');
  for (const name of ['testPlanNodeDispatchAtomicallyRetainsPreparedInputCheckpointAndIntentAudits',
    'testPlanNodeDispatchRejectsMismatchedOrInactiveCheckpointBeforeClaim',
    'testLegacyPlanNodeClaimCannotBeEnrichedIntoAnInventedDispatch',
    'testUnreadableDispatchJournalCannotGrantExecution']) assert(tests.includes('func ' + name + '('));
  console.log('Plan-node final dispatch/checkpoint/intent source contracts passed; no native build, crash, storage-fault or runtime acceptance.');
}
