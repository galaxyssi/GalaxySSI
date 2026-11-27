// Source contracts only; no Swift/UI/native provider or scheduler execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'bf68594c9ac3ea6f66a6782e3528228c11ddea3d';
const file = app + 'GalaxySSISettingsView.swift', clean = s => s.replace(/\r\n/g, '\n');
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
const show = (ref, f) => clean(cp.execFileSync('git', ['show', ref + ':' + f], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000}));
function section(s, first, last) {
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(a >= 0 && b > a, last);
  assert(!s.slice(a + first.length, b).includes(first), 'Unique hook in owning section: ' + first);
  return s.slice(a, b);
}
function retained(source) {
  if (!source.includes('struct GalaxySSISettingsRuntimeSummary:')) return source;
  const pinned = show(approved, file), prior = show(base, file);
  const prefix = source.slice(0, source.indexOf('struct SettingsView: View {'));
  assert.equal(prefix, pinned.slice(0, pinned.indexOf('struct SettingsView: View {')));
  source = source.replace(prefix, prior.slice(0, prior.indexOf('struct SettingsView: View {')));
  for (const line of ['  @Environment(\\.scenePhase) private var scenePhase\n',
    '  @State private var settingsStatsOwner = ""\n', '  @State private var settingsRefreshRevision: UInt64 = 0\n',
    '  @State private var settingsVisible = false\n']) {
    assert.equal(source.split(line).length, 2); source = source.replace(line, '');
  }
  for (const [first, last] of [['  var body: some View {', '  private var settingsLoadingContent: some View {'],
    ['  private var settingsStatsTaskID: String {', '  private var profileSection: some View {']]) {
    const current = section(source, first, last);
    assert.equal(current, section(pinned, first, last), 'Only exact approved settings lifecycle hooks normalize');
    source = source.replace(current, section(prior, first, last));
  }
  return source;
}
module.exports = {retained};
if (require.main === module) {
  const source = read(file);
  assert.equal(retained(source), show(base, file), 'Entire settings UI retained outside approved summary/lifecycle hooks');
  const key = section(source, '  static func key(for store:', '  static func prepare(store:');
  assert(!/AgentPhoneNativeToolCatalog|AgentMcpRegistry|FileAgentMcpStore|LocalModelRuntimeSettings/.test(key), 'No runtime scan while SwiftUI computes a task/prewarm key');
  assert(key.includes('store.profile.identityFingerprint'));
  const loader = section(source, '  fileprivate static func load()', '  static func project(');
  assert.equal(loader.split('AgentPhoneNativeToolCatalog.descriptors()').length - 1, 1);
  assert.equal(loader.split('AgentMcpRegistry(').length - 1, 1);
  const prepare = section(source, '  static func prepare(store:', '\nstruct SettingsView: View {');
  assert(prepare.includes('await Task.detached(priority: .utility) { GalaxySSISettingsRuntimeSummary.load() }.value'));
  assert(!/AgentPhoneNativeToolCatalog|AgentMcpRegistry|FileAgentMcpStore/.test(prepare));
  for (const token of ['generation == requestGeneration', '!Task.isCancelled', 'key(for: store) == sourceKey',
    'ProcessInfo.processInfo.systemUptime', 'runtime.nativeToolTotal', 'runtime.mcpReady']) assert(prepare.includes(token), token);
  for (const token of ['while !Task.isCancelled, settingsVisible, scenePhase == .active',
    'Task.sleep(nanoseconds: 30_000_000_000)', 'settingsVisible = false', '.receive(on: RunLoop.main)',
    'store.profile.identityFingerprint == owner', 'if settingsStatsLoading, let cached']) assert(source.includes(token), token);
  const android = clean(cp.execFileSync('git', ['diff', '65655f0c79c6ab04121150229a65b089180f82f2^1',
    '65655f0c79c6ab04121150229a65b089180f82f2', '--', 'apps/android/app/src/main/java/com/galaxyssi/chat/MainActivity.kt'], {cwd: root, encoding: 'utf8'}));
  assert(android.includes('+        navigationContentExecutor.execute {'));
  assert(android.includes('nativeToolCatalog()') && android.includes('prewarmContextSnapshot()'));
  assert.throws(() => retained(source.replace('generation == requestGeneration', 'true')), assert.AssertionError);
  assert.throws(() => retained(source.replace('while !Task.isCancelled, settingsVisible, scenePhase == .active', 'while true')), assert.AssertionError);
  for (const name of ['AgentPhoneNativeToolCatalog', 'AgentMcpCatalogModels', 'AgentMcpPackageModels',
    'GalaxySSINavigationContentPrewarm', 'GalaxySSIMainTabView'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  const tests = read('apps/ios/GalaxySSITests/GalaxySSISettingsRuntimeSummaryTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 6); assert(!/\p{Script=Han}/u.test(tests));
  const project = read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj');
  const registrations = s => s.split('\n').filter(line => line.includes('GalaxySSISettingsRuntimeSummaryTests.swift'));
  assert.equal(registrations(project).length, 4);
  assert.deepEqual(registrations(project), registrations(show(approved, 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj')));
  console.log('Settings worker-only runtime scans, dynamic projection, monotonic cache and visible-page lifecycle source contracts passed; six XCTest methods authored, not executed.');
}
