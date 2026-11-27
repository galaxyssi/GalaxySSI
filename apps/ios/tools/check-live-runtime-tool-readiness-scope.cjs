// Source contracts only. No Swift, Linux/QEMU, Git, evolution or native provider execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '4d6e0f2a0e2582e01d8d6c93887ab6b0d31ee487';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function show(ref, f) {
  const key = ref + ':' + f;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
const files = new Map([
  ['AgentIOSRuntimeNativeTools', ['provider.availability(operation: operation)', '  private static let readOnlyObservationOperations:']],
  ['AgentIOSSelfEvolutionNativeTools', ['provider.availability(operation: operation)', '  private static func description(']],
  ['AgentIOSProjectRepositoryReadTools', ['runtimeProvider.availability(operation: .execute)', '  private static func toolId(']],
  ['AgentIOSProjectRepositoryMutationCatalog', ['runtimeProvider.availability(operation: .execute)', '  private static func toolId(']]
]);
function once(s, from, to = '') { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length);
  assert(b > a, last); return s.slice(a, b);
}
function retained(file, s) {
  const name = path.basename(file, '.swift'), spec = files.get(name);
  if (!spec || !s.includes('      availabilityProvider: AgentNativeToolAvailabilityProvider { _ in')) return s;
  const block = section(s, '  private static func definition(', spec[1]);
  assert.equal(block, section(show(approved, file), '  private static func definition(', spec[1]), 'Only exact live readiness hook');
  const added = ',\n      availabilityProvider: AgentNativeToolAvailabilityProvider { _ in\n        ' + spec[0] + '\n      }';
  return once(s, added);
}
module.exports = {retained};
if (require.main === module) {
  const allowed = (file, s) => { try { return retained(file, s) === show(base, file); } catch { return false; } };
  for (const [name, [provider]] of files) {
    const file = app + name + '.swift', source = read(file);
    assert.equal(retained(file, source), show(base, file), name + ': every other contract/executor line retained');
    assert.equal(source.split('availabilityProvider: AgentNativeToolAvailabilityProvider').length - 1, 1);
    const hook = '      availabilityProvider: AgentNativeToolAvailabilityProvider { _ in\n        ' + provider + '\n      }';
    for (const changed of [source.replace(hook, '      availabilityProvider: .constant(.available)'),
      source.replace(hook, hook.replace(provider, 'descriptor.availability')), source + '\n// unrelated mutation\n']) {
      assert.notEqual(changed, source); assert(!allowed(file, changed), 'Stale/fabricated readiness or unrelated edits cannot normalize');
    }
  }
  for (const name of ['AgentNativeToolExecutionModels', 'AgentNativeToolCore', 'AgentPhoneNativeTools',
    'AgentPhoneNativeToolCatalog', 'AgentIOSDefaultOnDeviceRuntimeProvider', 'AgentIOSQemuRuntime']) {
    const file = app + name + '.swift'; let source = read(file);
    const mcp = path.join(__dirname, 'check-mcp-readiness-preparation-scope.cjs');
    if (fs.existsSync(mcp)) source = require(mcp).retained(file, source);
    assert.equal(source, show(base, file), name + ' unchanged outside exact independent MCP hooks');
  }
  const testsFile = 'apps/ios/GalaxySSITests/AgentRuntimeToolReadinessTests.swift', tests = read(testsFile);
  assert.equal(tests, show(approved, testsFile)); assert.equal((tests.match(/  func test/g) || []).length, 8);
  assert(!/\p{Script=Han}/u.test(tests));
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => line.includes('AgentRuntimeToolReadinessTests.swift'));
  assert.equal(registrations(read(projectFile)).length, 4);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  console.log('Four live runtime/project/evolution readiness hooks, twelve negative source mutations and eight authored fixture contracts passed; no native execution.');
}
