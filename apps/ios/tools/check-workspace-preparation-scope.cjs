// Source contracts only; no Swift, workspace persistence, registry or concurrency is executed.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'df5d6beed47394c1578d1991527628064341a994';
const checked = '4621f2a0b3231df6bfe47cca8ed75c51797b6136';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => {
  const s = clean(fs.readFileSync(path.join(root, f), 'utf8'));
  const mcp = path.join(__dirname, 'check-mcp-readiness-preparation-scope.cjs');
  return fs.existsSync(mcp) ? require(mcp).retained(f, s) : s;
};
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function once(s, from, to = '') { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(b > a, last); return s.slice(a, b);
}
function retained(file, s) {
  if (file.endsWith('/AgentWorkspaceNativeToolStateStore.swift') && s.includes('protocol AgentWorkspaceNativeToolCheckedStateStore:')) {
    assert.equal(s, show(checked, file), 'Only the exact checked persistence implementation normalizes');
    return show(base, file);
  }
  if (file.endsWith('/AgentWorkspaceNativeToolExecutor.swift') && s.includes('  private var workspaceStateDirty = false')) {
    s = once(s, '  private var workspaceStateDirty = false\n');
    for (const [first, last] of [
      ['  private func preparePersistentStateUnlocked()', '  func executableDefinition('],
      ['  private func run(toolId:', '  private func initialize('],
      ['  private func persistWorkspaces()', '  private static func restoreWorkspaces(']
    ]) {
      const block = section(s, first, last);
      assert.equal(block, section(show(checked, file), first, last), 'Only exact checked restore/commit hooks normalize');
      s = once(s, block, section(show(approved, file), first, last));
    }
  }
  if (file.endsWith('/AgentWorkspaceNativeToolExecutor.swift') && s.includes('  private var persistentStatePrepared = false')) {
    s = once(s, '  static let preparationQueue = DispatchQueue(label: "galaxyssi.workspace-restore", qos: .utility)\n');
    s = once(s, '  private let stateLock = NSLock()\n  private var persistentStatePrepared = false\n');
    s = once(s, '    runtimeRoot: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(),\n    preparationQueue: DispatchQueue? = nil',
      '    runtimeRoot: URL = AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL()');
    const first = '    self.runtimeRoot = runtimeRoot\n', last = '  func executableDefinition(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last), 'Only exact preparation and locking implementation');
    s = once(s, block, section(show(base, file), first, last));
    return once(s, '    stateLock.lock()\n    defer { stateLock.unlock() }\n    preparePersistentStateUnlocked()\n');
  }
  if (file.endsWith('/AgentPhoneNativeToolCatalogDefaults.swift') && s.includes('preparationQueue: AgentWorkspaceNativeToolExecutor.preparationQueue'))
    return once(s, '      runtimeRoot: AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(storageRootURL: storageRootURL),\n      preparationQueue: AgentWorkspaceNativeToolExecutor.preparationQueue',
      '      runtimeRoot: AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL(storageRootURL: storageRootURL)');
  return s;
}
module.exports = {retained};
if (require.main === module) {
  for (const name of ['AgentWorkspaceNativeToolExecutor', 'AgentPhoneNativeToolCatalogDefaults', 'AgentWorkspaceNativeToolStateStore']) {
    const file = app + name + '.swift';
    assert.equal(retained(file, read(file)), show(base, file), name + ': all operation/provider code retained');
  }
  const file = app + 'AgentWorkspaceNativeToolExecutor.swift', executor = read(file);
  const prepare = section(executor, '  private func preparePersistentState() {', '  func executableDefinition(');
  assert(prepare.includes('stateLock.lock()\n    defer { stateLock.unlock() }'));
  assert(prepare.indexOf('guard !persistentStatePrepared') < prepare.indexOf('stateStore?.load()'));
  assert(prepare.indexOf('stateStore?.load()') < prepare.indexOf('persistentStatePrepared = true'));
  const run = section(executor, '  private func run(toolId:', '  private func initialize(');
  assert(run.indexOf('stateLock.lock()') < run.indexOf('preparePersistentStateUnlocked()'));
  assert(run.indexOf('preparePersistentStateUnlocked()') < run.indexOf('let workspaceId ='));
  assert.equal(executor.split('stateStore?.load()').length - 1, 1);
  const init = section(executor, '  init(\n', '  private func preparePersistentState()');
  assert(init.includes('preparationQueue: DispatchQueue? = nil'));
  assert(init.includes('preparationQueue.async { [weak self] in self?.preparePersistentState() }'));
  assert(init.includes('} else {\n      preparePersistentState()'));
  for (const mutation of [executor.replace('preparationQueue.async', 'preparationQueue.sync'),
    executor.replace('guard !persistentStatePrepared else { return }', ''),
    executor.replace('  private let stateLock = NSLock()', '  private let stateLock = NSRecursiveLock()'),
    executor.replace('    preparePersistentStateUnlocked()\n    guard persistentStatePrepared', '    guard persistentStatePrepared'),
    executor.replace('    guard persistentStatePrepared else {', '    guard true else {'),
    executor.replace('        workspaces = previous\n        return failure(.ioError', '        return failure(.ioError'),
    executor.replace('guard case .success = result else { workspaces = previous; return result }', 'guard case .success = result else { return result }'),
    executor.replace('    workspaceStateDirty = true', '    workspaceStateDirty = false')]) {
    assert.notEqual(mutation, executor);
    assert.throws(() => retained(file, mutation), assert.AssertionError);
  }
  assert.notEqual(retained(file, executor + '\n// unrelated mutation\n'), show(base, file));
  assert(prepare.includes('(stateStore as? AgentWorkspaceNativeToolCheckedStateStore)?.loadChecked()'));
  assert(run.indexOf('guard persistentStatePrepared') < run.indexOf('let result = runPrepared('));
  assert(run.indexOf('guard case .success = result') < run.indexOf('try savePersistentState()'));
  assert(run.includes('workspaces = previous'));
  const storageFile = app + 'AgentWorkspaceNativeToolStateStore.swift', storage = read(storageFile);
  assert.equal(storage, show(checked, storageFile));
  assert(storage.includes('error.code == .fileReadNoSuchFile'));
  const save = section(storage, '  func saveChecked(_ workspaces: [String: [String: AgentWorkspaceNativeToolStoredEntry]]) throws {', '  func clear()');
  assert(save.indexOf('_ = try loadUnlocked()') < save.indexOf('try data.write('));
  for (const mutation of [storage.replace('error.code == .fileReadNoSuchFile', 'true'),
    storage.replace('    _ = try loadUnlocked()\n', '')])
    assert.throws(() => retained(storageFile, mutation), assert.AssertionError);
  for (const name of ['AgentWorkspaceModels', 'AgentNativeToolExecutionModels',
    'AgentPhoneNativeToolCatalog', 'AgentNativeToolCore'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  const testsFile = 'apps/ios/GalaxySSITests/AgentWorkspacePreparationTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 6);
  assert(!/\p{Script=Han}/u.test(tests));
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => line.includes('AgentWorkspacePreparationTests.swift'));
  assert.equal(registrations(read(projectFile)).length, 4);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  const faultsFile = 'apps/ios/GalaxySSITests/AgentWorkspacePersistenceTests.swift', faults = read(faultsFile);
  assert.equal(faults, show(checked, faultsFile)); assert.equal((faults.match(/  func test/g) || []).length, 6);
  assert(!/\p{Script=Han}/u.test(faults));
  const faultRegistrations = s => s.split('\n').filter(line => line.includes('AgentWorkspacePersistenceTests.swift'));
  assert.equal(faultRegistrations(read(projectFile)).length, 4);
  assert.deepEqual(faultRegistrations(read(projectFile)), faultRegistrations(show(checked, projectFile)));
  console.log('Default workspace background preparation, checked restore/commit rollback and twelve authored fixture source contracts passed; no native execution.');
}
