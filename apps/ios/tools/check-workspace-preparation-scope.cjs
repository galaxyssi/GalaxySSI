// Source contracts only; no Swift, workspace persistence, registry or concurrency is executed.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'df5d6beed47394c1578d1991527628064341a994';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
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
  for (const name of ['AgentWorkspaceNativeToolExecutor', 'AgentPhoneNativeToolCatalogDefaults']) {
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
    executor.replace('    stateLock.lock()\n    defer { stateLock.unlock() }\n    preparePersistentStateUnlocked()\n    let workspaceId', '    let workspaceId')]) {
    assert.notEqual(mutation, executor);
    assert.throws(() => retained(file, mutation), assert.AssertionError);
  }
  assert.notEqual(retained(file, executor + '\n// unrelated mutation\n'), show(base, file));
  for (const name of ['AgentWorkspaceNativeToolStateStore', 'AgentWorkspaceModels', 'AgentNativeToolExecutionModels',
    'AgentPhoneNativeToolCatalog', 'AgentNativeToolCore'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  const testsFile = 'apps/ios/GalaxySSITests/AgentWorkspacePreparationTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 6);
  assert(!/\p{Script=Han}/u.test(tests));
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => line.includes('AgentWorkspacePreparationTests.swift'));
  assert.equal(registrations(read(projectFile)).length, 4);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  console.log('Default background workspace preparation, single locked restore/mutation scope and six authored fixture source contracts passed; no native execution.');
}
