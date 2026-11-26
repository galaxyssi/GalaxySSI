// Source contracts, not Swift compilation, executed discovery or model/device acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = '5f60bac1b8571768f6f12f426dee5950c6f87bd0';
const read = file => require('./check-interactive-request-hedge-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const git = args => cp.execFileSync('git', args, {cwd: root, maxBuffer: 32 * 1024 * 1024});
const cache = new Map();
function old(file) { if (!cache.has(file)) cache.set(file, git(['show', `${base}:${file}`]).toString().replace(/\r\n/g, '\n')); return cache.get(file); }
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function retained(file, source) {
  source = require('./check-interactive-request-hedge-scope.cjs').retained(file, source);
  if (file.endsWith('check-journal-codex-replay-scope.cjs')) return source
    .replace("const read = file => require('./check-progressive-tool-catalog-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-progressive-tool-catalog-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n').filter(line =>
    !['AgentToolInspectionCatalog.swift', 'AgentProgressiveToolCatalog.swift', 'AgentProgressiveToolCatalogTests.swift'].some(name => line.includes(name))).join('\n');
  if (file.endsWith('AgentNativeToolCore.swift')) return source.replace('  var toolCatalog: (() -> AgentMcpJSONObject)? = nil\n', '');
  if (file.endsWith('AgentNativeToolExecutionModels.swift')) return source
    .replace('    var invocation = AgentNativeToolInvocation(', '    let invocation = AgentNativeToolInvocation(')
    .replace('    invocation.toolCatalog = { [weak self] in self?.catalogObject() ?? [:] }\n', '');
  if (file.endsWith('AgentPhoneNativeToolCatalog.swift')) return source
    .replace('AgentSystemEvidenceNativeToolCatalog.definitions() + AgentToolInspectionCatalog.definitions()', 'AgentSystemEvidenceNativeToolCatalog.definitions()')
    .replace('      AgentToolInspectionCatalog.executableDefinitions() +\n', '');
  if (file.endsWith('AgentModelPlanningPrompt.swift') && source.includes('AgentProgressiveToolCatalog.render(')) return source
    .replace(section(source, '    if !AgentPhoneRuntimePolicy.shouldUsePhoneRuntime(goal: request.planRequest.goal),', '    let research = includesResearch ?'), '')
    .replace('Use CALL_NATIVE_TOOL actions from the available catalog or its discovery receipts and wait for their receipts.',
      'Use only listed CALL_NATIVE_TOOL actions and wait for their receipts.');
  return source;
}
function validate() {
  const manifest = JSON.parse(read('apps/ios/ANDROID_4584_PORT_COVERAGE.json'));
  const files = git(['diff', '--name-only', manifest.androidBase, manifest.androidHead]).toString().trim().split(/\r?\n/);
  assert.equal(manifest.androidPR, 4584); assert.equal(files.length, 22);
  assert.deepEqual(manifest.files.map(file => file.path), files);
  for (const file of manifest.files) assert.equal(crypto.createHash('sha256').update(git(['show', `${manifest.androidHead}:${file.path}`])).digest('hex'), file.sha256, file.path);
  for (const file of [app + 'AgentNativeToolCore.swift', app + 'AgentNativeToolExecutionModels.swift', app + 'AgentPhoneNativeToolCatalog.swift',
    app + 'AgentModelPlanningPrompt.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', 'apps/ios/tools/check-journal-codex-replay-scope.cjs'])
    assert.equal(retained(file, read(file)), old(file), file);
  const core = read(app + 'AgentNativeToolCore.swift'), registry = read(app + 'AgentNativeToolExecutionModels.swift');
  assert(core.indexOf('var toolCatalog:') > core.indexOf('struct AgentNativeToolInvocation {'));
  assert(registry.includes('invocation.toolCatalog = { [weak self] in self?.catalogObject() ?? [:] }'));
  const catalog = read(app + 'AgentToolInspectionCatalog.swift');
  for (const token of ['invocation.checkpoint()', 'invocation.toolCatalog?()', '"tool_not_disclosed"', '"schema_path_not_found"',
    '"tool_catalog_changed"', '"tool_discovery_cursor_invalid"', '"target_executed": .bool(false)',
    'object.string("query_sha256") == queryHash', 'availability.removeValue(forKey: "checked_at_epoch_ms")',
    'matches.contains(where: { $0.string("id") == after })', 'output["capability_absent"] = .bool(false)',
    'String(index) == key', 'AgentNativeToolDescriptor(', 'concurrency: .parallelReadOnly, effect: .readOnly']) assert(catalog.includes(token), token);
  for (const token of ['registry.invoke(', 'URLSession', 'UserDefaults', 'FileManager', 'installPack(', 'grantedConsents.insert']) assert(!catalog.includes(token), token);
  const progressive = read(app + 'AgentProgressiveToolCatalog.swift');
  for (const token of ['eligible.count > 12', 'toolIds.isSubset', 'action.status == .completed', 'result.count == 4',
    'AgentToolInspectionCatalog.describe', 'recent.contains($0.id)', 'entryPoints.contains($0.id)', 'required.contains(key)',
    'choices.count', 'list<', 'struct Manifest', 'let rows: [String]']) assert(progressive.includes(token), token);
  const prompt = read(app + 'AgentModelPlanningPrompt.swift');
  assert(prompt.indexOf('AgentProgressiveToolCatalog.render') < prompt.indexOf('    let research = includesResearch ?'));
  assert(prompt.includes('rows: progressive.rows.map { ToolInventory.Row(compact: $0, full: $0) }'));
  const tests = read('apps/ios/GalaxySSITests/AgentProgressiveToolCatalogTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 9);
  for (const token of ['full.subset {', 'limited.invoke(', 'registry.invoke(descriptor.id', 'executions, 0', 'tool_catalog_changed',
    'AgentModelPlanningPrompt.build(', 'AgentProgressiveToolCatalog.recent(history)']) assert(tests.includes(token), token);
  for (const name of ['AgentToolInspectionCatalog.swift', 'AgentProgressiveToolCatalog.swift', 'AgentProgressiveToolCatalogTests.swift'])
    assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n').filter(line => line.includes(name)).length, 4);
  for (const name of ['AgentPlanNodeJournal', 'AgentActionEffectExecutor', 'AgentMcpCoreModels', 'MqttMultipathPolicy', 'MqttDeliveryDispatch', 'AgentConnectorStreamUpdate'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  console.log('Pinned Android inventory, invoking-registry inspection, progressive signatures and retained execution source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
