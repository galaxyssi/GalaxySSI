// Source contracts only. No Swift, audit store, UI or native runtime is executed.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '85bbbd172eaef1db4644d2c96ffb6beb62e4bbdb';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
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
  if (file.endsWith('/GalaxySSIAndroidParityUI.swift') && s.includes('@StateObject var homeAudit')) {
    s = once(s, '  @StateObject var homeAudit = AgentHomeAuditLoader()',
      '  @State var agentRuntimeAuditRecords: [AgentNativeToolAuditRecord] = []');
    s = once(s, '        homeVisible = false\n        homeAudit.invalidate()\n', '        homeVisible = false\n');
    return once(s, '      .task(id: auditRefreshIdentity) { refreshAgentRuntimeAuditRecords() }\n');
  }
  if (file.endsWith('/GalaxySSIAgentHomeSessionLifecycle.swift') && s.includes('  var auditRefreshIdentity:')) {
    const first = '  var auditRefreshIdentity:', last = '  func refreshAgentRouteState()';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last));
    s = once(s, block, section(show(base, file), '  func refreshAgentRuntimeAuditRecords()', last));
    return once(s, '  func clearAgentRuntimePlaintextPresentation() {\n    homeAudit.invalidate()\n',
      '  func clearAgentRuntimePlaintextPresentation() {\n');
  }
  return s;
}
module.exports = {retained};
if (require.main === module) {
  const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
  for (const name of ['GalaxySSIAndroidParityUI', 'GalaxySSIAgentHomeSessionLifecycle']) {
    const file = app + name + '.swift'; let s = read(file);
    const catalog = path.join(__dirname, 'check-home-native-catalog-scope.cjs');
    if (fs.existsSync(catalog)) s = require(catalog).retained(file, s);
    assert.equal(retained(file, s), show(base, file), 'All other presentation/lifecycle source retained');
  }
  const file = app + 'AgentHomeAuditLoader.swift', loader = read(file);
  assert.equal(loader, show(approved, file));
  for (const token of ['GlobalAgentDashboardRefreshState()', 'qos: .utility', 'state.request(identity: identity)',
    'self.state.complete(token)', 'guard completion.accepted', 'state.invalidate()',
    'guard !identity.isBlank else { invalidate(); return }', 'state.identity == identity',
    'if let next = completion.next { self.launch(next) }', 'list(limit: 12, toolId: "", status: nil)']) assert(loader.includes(token), token);
  assert(loader.indexOf('queue.async { [weak self]') < loader.indexOf('let result = read()'));
  assert(!/\.execute\(|\.invoke\(|URLSession|UserDefaults|\.append\(|\.clear\(/.test(loader));
  const lifecycle = read(app + 'GalaxySSIAgentHomeSessionLifecycle.swift');
  assert(!lifecycle.includes('makePersistentStores'));
  assert(lifecycle.includes('homeVisible, scenePhase == .active, store.canReadAgentTranscript'));
  assert(lifecycle.includes('!transcriptRuntimeCleared, !store.profile.identityFingerprint.isBlank'));
  assert(lifecycle.includes('homeAudit.records(for: auditRefreshIdentity)'));
  for (const changed of [lifecycle.replace('!transcriptRuntimeCleared, ', ''),
    lifecycle.replace('homeAudit.refresh(identity: identity)', 'homeAudit.refresh(identity: "shared")')])
    assert.throws(() => retained(app + 'GalaxySSIAgentHomeSessionLifecycle.swift', changed), assert.AssertionError);
  const ui = read(app + 'GalaxySSIAndroidParityUI.swift');
  assert.throws(() => retained(app + 'GalaxySSIAndroidParityUI.swift', ui.replace('homeAudit.invalidate()', 'homeAudit.refresh(identity: "shared")')), assert.AssertionError);
  const panel = app + 'GalaxySSIAgentHomeRuntimePanel.swift', catalog = path.join(__dirname, 'check-home-native-catalog-scope.cjs');
  assert.equal(fs.existsSync(catalog) ? require(catalog).retained(panel, read(panel)) : read(panel), show(base, panel));
  for (const name of ['AgentNativeToolAuditStore', 'AgentNativeToolDefaultStores', 'GlobalAgentDashboardLoader',
    'GalaxySSIAgentHomeOutputView', 'AgentNativeToolCore'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  const testsFile = 'apps/ios/GalaxySSITests/AgentHomeAuditLoaderTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 5);
  assert(!/\p{Script=Han}/u.test(loader + tests));
  const project = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => /AgentHomeAuditLoader(?:Tests)?\.swift/.test(line));
  assert.equal(registrations(read(project)).length, 8);
  assert.deepEqual(registrations(read(project)), registrations(show(approved, project)));
  console.log('Home audit worker, exact source scope, owner/lifecycle gates and project registrations passed; five XCTest methods authored, not executed.');
}
