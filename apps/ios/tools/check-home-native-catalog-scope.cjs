// Source contracts only; no Swift, native catalog/provider, UI or scheduler execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'a08d14423c650da7fef28d24800f755323909eef';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => {
  const s = clean(fs.readFileSync(path.join(root, f), 'utf8'));
  const audit = path.join(__dirname, 'check-home-audit-worker-scope.cjs');
  return fs.existsSync(audit) ? require(audit).retained(f, s) : s;
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
  if (file.endsWith('/GalaxySSIAndroidParityUI.swift') && s.includes('@StateObject var homeNativeCatalog')) {
    for (const line of ['  @StateObject var homeNativeCatalog = AgentHomeNativeCatalogLoader()\n',
      '        if phase != .active { homeNativeCatalog.invalidate() }\n',
      '        if canPresentNativeCatalog { homeNativeCatalog.refreshIfActive(identity: store.profile.identityFingerprint) }\n']) s = once(s, line);
    s = once(s, '      .onDisappear {\n        homeNativeCatalog.invalidate()\n', '      .onDisappear {\n');
    s = once(s, '        transcriptRuntimeCleared = true\n        homeNativeCatalog.invalidate()\n', '        transcriptRuntimeCleared = true\n');
    const first = '      .task(id: nativeCatalogRefreshKey) {', last = '      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIWorkspaceDidPersist)';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last)); return once(s, block);
  }
  if (file.endsWith('/GalaxySSIAgentHomeState.swift') && s.includes('  var canPresentNativeCatalog: Bool {')) {
    s = once(s, '    guard !hasManualSelection, nativeCatalogIsCurrent else { return nil }', '    guard !hasManualSelection else { return nil }');
    const first = '  var canPresentNativeCatalog:', last = '  private var callableAgentTargets:';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last));
    return once(s, block, section(show(base, file), '  var nativeToolSummary:', last));
  }
  if (file.endsWith('/GalaxySSIAgentHomeRuntimePanel.swift') && s.includes('nativeToolsLoading: !nativeCatalogIsCurrent'))
    return once(s, '      nativeTools: nativeToolDescriptors,\n      nativeToolsLoading: !nativeCatalogIsCurrent,',
      '      nativeTools: AgentPhoneNativeToolCatalog.descriptors(),');
  if (file.endsWith('/GalaxySSIAgentRuntimePanelView.swift') && s.includes('  var nativeToolsLoading = false')) {
    s = once(s, '  var nativeToolsLoading = false\n');
    s = once(s, '        subtitle: nativeToolsLoading ? t("cc_loading", "Loading...") :\n          String(format: t("galaxyssi.agent_runtime.toolbox_summary", "%d local tools"), availableTools.count),',
      '        subtitle: String(format: t("galaxyssi.agent_runtime.toolbox_summary", "%d local tools"), availableTools.count),');
    return once(s, '        emptyTitle: nativeToolsLoading ? t("cc_loading", "Loading...") :\n          t("agent_toolbox_empty", "No local tools are available")',
      '        emptyTitle: t("agent_toolbox_empty", "No local tools are available")');
  }
  return s;
}
module.exports = {retained};
if (require.main === module) {
  for (const name of ['GalaxySSIAndroidParityUI', 'GalaxySSIAgentHomeState', 'GalaxySSIAgentHomeRuntimePanel', 'GalaxySSIAgentRuntimePanelView']) {
    const file = app + name + '.swift';
    assert.equal(retained(file, read(file)), show(base, file), name + ': all other UI/routing/control source retained');
  }
  const file = app + 'AgentHomeNativeCatalogLoader.swift', loader = read(file);
  assert.equal(loader, show(approved, file), 'Only the exact approved worker/ownership implementation');
  assert.equal(loader.split('AgentPhoneNativeToolCatalog.descriptors()').length - 1, 1);
  assert(loader.indexOf('queue.async { [weak self]') < loader.indexOf('let result = read()'));
  for (const token of ['GlobalAgentDashboardRefreshState()', 'qos: .utility', 'state.request(identity: identity)',
    'state.complete(token)', 'guard completion.accepted', 'state.invalidate()', 'guard state.identity != nil',
    'if let result { tools = result; hasSnapshot = true }', 'refreshFailed = result == nil',
    'state.identity == identity && hasSnapshot', 'if let next = completion.next { launch(next) }']) assert(loader.includes(token), token);
  assert(!/UserDefaults|URLSession|MessageCoordinator|\.execute\(|\.invoke\(/.test(loader));
  const state = read(app + 'GalaxySSIAgentHomeState.swift');
  const summary = section(state, '  var canPresentNativeCatalog:', '  private var callableAgentTargets:');
  assert(!summary.includes('AgentPhoneNativeToolCatalog'));
  assert(summary.includes('homeVisible && scenePhase == .active && store.canReadAgentTranscript && !transcriptRuntimeCleared'));
  assert(state.includes('guard !hasManualSelection, nativeCatalogIsCurrent else { return nil }'));
  const ui = read(app + 'GalaxySSIAndroidParityUI.swift');
  assert.equal(ui.split('homeNativeCatalog.invalidate()').length - 1, 4);
  assert(ui.includes('while !Task.isCancelled, canPresentNativeCatalog'));
  assert(ui.includes('Task.sleep(nanoseconds: 30_000_000_000)'));
  assert.throws(() => retained(app + 'GalaxySSIAndroidParityUI.swift', ui.replace('while !Task.isCancelled, canPresentNativeCatalog', 'while true')), assert.AssertionError);
  for (const name of ['GlobalAgentDashboardLoader', 'AgentPhoneNativeToolCatalog', 'AgentNativeToolCore',
    'AgentNetworkRoutingModels', 'AgentIOSBackgroundCognition'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  const testsFile = 'apps/ios/GalaxySSITests/AgentHomeNativeCatalogLoaderTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 6);
  assert(!/\p{Script=Han}/u.test(loader + tests));
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  const registrations = s => s.split('\n').filter(line => /AgentHomeNativeCatalogLoader(?:Tests)?\.swift/.test(line));
  assert.equal(registrations(project).length, 8);
  assert.deepEqual(registrations(project), registrations(show(approved, 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj')));
  const android = clean(cp.execFileSync('git', ['diff', '65655f0c79c6ab04121150229a65b089180f82f2^1',
    '65655f0c79c6ab04121150229a65b089180f82f2', '--', 'apps/android/app/src/main/java/com/galaxyssi/chat/MainActivity.kt'], {cwd: root, encoding: 'utf8'}));
  assert(android.includes('nativeToolCatalog()') && android.includes('+        navigationContentExecutor.execute {'));
  console.log('Home worker catalog, shared display snapshot, loading semantics and lifecycle ownership source contracts passed; six XCTest methods authored, not executed.');
}
