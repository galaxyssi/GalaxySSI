// Source contracts only; no Swift, provider, MCP, registry or native discovery execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'ee9e5740ca4e929ab4e39a498a55e9bf8041c806';
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
  const capture = path.join(__dirname, 'check-capture-live-readiness.cjs');
  if (file.endsWith('/AgentPhoneNativeToolCatalog.swift') && fs.existsSync(capture))
    s = require(capture).retained(file, s);
  const media = path.join(__dirname, 'check-media-readiness-registration.cjs');
  if (file.endsWith('/AgentPhoneNativeToolCatalog.swift') && fs.existsSync(media))
    s = require(media).retained(file, s);
  const runtime = path.join(__dirname, 'check-live-runtime-tool-readiness-scope.cjs');
  if (file.endsWith('/AgentPhoneNativeToolCatalog.swift') && fs.existsSync(runtime))
    s = require(runtime).retained(file, s);
  if (file.endsWith('/AgentMcpNativeTools.swift') && s.includes('  static let uncheckedAvailability =')) {
    s = once(s, '  static let uncheckedAvailability = AgentNativeToolAvailability(\n    status: .unavailable, reason: "MCP readiness has not been checked")\n');
    for (const [first, last] of [['  static func definitions(', '  static func operation('],
      ['  private static func definition(', '  private static func description(']]) {
      const block = section(s, first, last);
      assert.equal(block, section(show(approved, file), first, last));
      s = once(s, block, section(show(base, file), first, last));
    }
  }
  if (file.endsWith('/AgentPhoneNativeToolCatalog.swift') && s.includes('initialAvailability: AgentMcpNativeTools.uncheckedAvailability')) {
    s = once(s, '      mcpExecutableDefinitions(provider: resolvedMcpProvider, initialAvailability: AgentMcpNativeTools.uncheckedAvailability) +',
      '      mcpExecutableDefinitions(provider: resolvedMcpProvider) +');
    const first = '  static func mcpExecutableDefinitions(', last = '  static func onDeviceRuntimeExecutableDefinitions(';
    const block = section(s, first, last);
    assert.equal(block, section(show(approved, file), first, last));
    s = once(s, block, section(show(base, file), first, last));
  }
  if (file.endsWith('/AgentLocalModelToolCatalog.swift') && s.includes('match.availability = definition.availabilityProvider.current(nil)')) {
    s = once(s, '        guard let definition = registry.lookup(tool) else {', '        guard let match = registry.lookup(tool)?.descriptor else {');
    s = once(s, '        var match = definition.descriptor\n        match.availability = definition.availabilityProvider.current(nil)\n');
  }
  return s;
}
module.exports = {retained};
if (require.main === module) {
  for (const name of ['AgentMcpNativeTools', 'AgentPhoneNativeToolCatalog', 'AgentLocalModelToolCatalog']) {
    const file = app + name + '.swift';
    assert.equal(retained(file, read(file)), show(base, file), name + ': only approved registration/exact-read hooks change');
  }
  const mcpFile = app + 'AgentMcpNativeTools.swift', mcp = read(mcpFile);
  assert(mcp.includes('availability: initialAvailability ?? provider.availability(operation: operation)'));
  assert(mcp.includes('availabilityProvider: AgentNativeToolAvailabilityProvider { _ in\n        provider.availability(operation: operation)'));
  assert(mcp.includes('initialAvailability: AgentNativeToolAvailability? = nil'));
  const catalogFile = app + 'AgentPhoneNativeToolCatalog.swift', catalog = read(catalogFile);
  assert(catalog.includes('mcpExecutableDefinitions(provider: resolvedMcpProvider, initialAvailability: AgentMcpNativeTools.uncheckedAvailability)'));
  const discoveryFile = app + 'AgentLocalModelToolCatalog.swift', discovery = read(discoveryFile);
  assert(discovery.indexOf('try authorize(invocation)') < discovery.indexOf('definition.availabilityProvider.current(nil)'));
  assert(discovery.indexOf('registry.refreshAvailability()') < discovery.indexOf('definition.availabilityProvider.current(nil)'));
  assert(discovery.includes('"grants_permissions": .bool(false)'));
  const allowed = (f, s) => { try { return retained(f, s) === show(base, f); } catch { return false; } };
  for (const [f, s] of [
    [mcpFile, mcp.replace('initialAvailability ?? provider.availability(operation: operation)', 'AgentNativeToolAvailability.available')],
    [mcpFile, mcp.replace('        provider.availability(operation: operation)', '        AgentNativeToolAvailability.available')],
    [mcpFile, mcp.replace('initialAvailability: AgentNativeToolAvailability? = nil', 'initialAvailability: AgentNativeToolAvailability? = .available')],
    [catalogFile, catalog.replace('initialAvailability: AgentMcpNativeTools.uncheckedAvailability', 'initialAvailability: .available')],
    [discoveryFile, discovery.replace('        match.availability = definition.availabilityProvider.current(nil)\n', '')],
    [discoveryFile, discovery.replace('try authorize(invocation)', 'try invocation.checkpoint()')],
    [discoveryFile, discovery.replace('      registry.refreshAvailability()\n', '')]
  ]) { assert.notEqual(s, read(f)); assert(!allowed(f, s), 'Unsafe or unrelated source mutation must not normalize'); }
  for (const name of ['AgentPhoneNativeTools', 'AgentNativeToolExecutionModels', 'AgentNativeToolCore',
    'AgentMcpCatalogModels', 'AgentIOSMcpClientNativeProvider'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' unchanged');
  const testsFile = 'apps/ios/GalaxySSITests/AgentMcpReadinessPreparationTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 8);
  assert(!/\p{Script=Han}/u.test(tests));
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => line.includes('AgentMcpReadinessPreparationTests.swift'));
  assert.equal(registrations(read(projectFile)).length, 4);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  console.log('Deferred MCP registration, dynamic invocation/exact discovery, source boundaries and eight authored fixture contracts passed; no native execution.');
}
