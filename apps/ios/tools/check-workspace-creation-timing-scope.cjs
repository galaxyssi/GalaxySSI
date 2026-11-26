// Source contracts only, not native workspace/filesystem/OSLog execution or latency evidence.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const baseline = 'ebc9b2f25ae8c4631917a8f9aa75848420ff73e6';
const app = 'apps/ios/GalaxySSI/';
const clean = value => value.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
const git = (...args) => clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 8_000_000}));

function retainedWorkspaceCreationTiming(source) {
  const hooks = [
    ['  private let timingClock: () -> Int64\n  private let timingSink: AgentWorkspaceCreationTiming.Sink\n', ''],
    ['    },\n    timingClock: @escaping () -> Int64 = AgentWorkspaceCreationTiming.monotonicMillis,\n    timingSink: @escaping AgentWorkspaceCreationTiming.Sink = AgentWorkspaceCreationTiming.log', '    }'],
    ['    self.timingClock = timingClock\n    self.timingSink = timingSink\n', ''],
    ['      let preparationStarted = timingClock()\n', ''],
    ['      let isNew = store.find(workspace.workspaceId) == nil\n', ''],
    ['      try persist(store, creation: isNew ? (updated.taskId, preparationStarted) : nil)', '      try persist(store)'],
    ['  private func persist(_ store: InMemoryAgentWorkspaceStore,\n    creation: (taskId: String, started: Int64)? = nil) throws {', '  private func persist(_ store: InMemoryAgentWorkspaceStore) throws {'],
    ['    let data = Data(store.serializedSnapshot().utf8)\n    let commitStarted = creation == nil ? nil : timingClock()\n    try writeFile(data, fileURL)\n    if let creation, let commitStarted {\n      timingSink(AgentWorkspaceCreationTiming.sample(taskId: creation.taskId,\n        started: creation.started, commitStarted: commitStarted, committed: timingClock()))\n    }', '    try writeFile(Data(store.serializedSnapshot().utf8), fileURL)']
  ];
  for (const [before, after] of hooks) {
    assert.equal(source.split(before).length, 2, 'One declared workspace timing hook: ' + before);
    source = source.replace(before, after);
  }
  return source;
}

function validateWorkspaceCreationTiming() {
  const store = read(app + 'FileAgentWorkspaceStore.swift');
  assert.equal(retainedWorkspaceCreationTiming(store), git('show', baseline + ':' + app + 'FileAgentWorkspaceStore.swift'),
    'Retain locking, strict legacy read, revision/identity/bounds, persistence failure and post-commit notification outside declared timing hooks');
  for (const name of ['AgentWorkspaceStore', 'AgentWorkspaceBoundsPolicy', 'AgentWorkspaceModels'])
    assert.equal(read(app + name + '.swift'), git('show', baseline + ':' + app + name + '.swift'), name);
  const persist = store.slice(store.indexOf('  private func persist('), store.indexOf('  private func locked<T>'));
  assert(persist.indexOf('Data(store.serializedSnapshot().utf8)') < persist.indexOf('let commitStarted'));
  assert(persist.indexOf('try writeFile(') < persist.indexOf('timingSink('));
  assert(persist.indexOf('timingSink(') < persist.indexOf('NotificationCenter.default.post('));
  const timing = read(app + 'AgentWorkspaceCreationTiming.swift');
  for (const token of ['DispatchTime.now().uptimeNanoseconds / 1_000_000', 'subtractingReportingOverflow',
    'end <= start ? 0', 'delta.overflow ? Int64.max', 'SHA256.hash(data: Data(taskId.utf8))',
    'privacy: .private(mask: .hash)', 'snapshot_writes=1', 'category: "workspace-latency"']) assert(timing.includes(token), token);
  const sample = timing.slice(timing.indexOf('  struct Sample:'), timing.indexOf('  typealias Sink'));
  for (const token of ['taskId', 'workspaceId', 'goal', 'body', 'path', 'url', 'prompt', 'header', 'key']) assert(!sample.includes(token), token);
  assert(!/Date\(|UserDefaults|URLSession|FileManager/.test(timing));
  const reference = git('show', '65655f0c79c6ab04121150229a65b089180f82f2:apps/android/app/src/main/java/com/galaxyssi/chat/AgentWorkspaceStore.kt');
  for (const token of ['val started = System.nanoTime()', 'val commitStarted = System.nanoTime()',
    'state.database.mutateStrings(updates, removedIds.map(::workspaceKey))',
    'if (isNew) android.util.Log.i("GalaxySSILatency", "workspace_create']) assert(reference.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentWorkspacePersistentStoreTests.swift');
  for (const name of ['SeparatesPreparationWriteAndNotification', 'DoesNotMislabelUpdatesOrOtherMutations',
    'DoesNotPublishFailedCommits', 'KeepsLegacyRevisionZeroAsAnUpdate', 'BoundsAndPrivateCorrelation'])
    assert(tests.includes('func testWorkspaceCreationTiming' + name + '('), name);
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  assert.equal(project.split('AgentWorkspaceCreationTiming.swift in Sources */').length, 3);
}
module.exports = {retainedWorkspaceCreationTiming, validateWorkspaceCreationTiming};
if (require.main === module) {
  validateWorkspaceCreationTiming();
  console.log('iOS successful workspace creation preparation/commit timing source contracts passed; no native or latency acceptance');
}
