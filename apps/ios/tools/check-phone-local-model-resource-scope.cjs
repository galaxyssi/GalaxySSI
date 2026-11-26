// Source evidence only, not native inference, offline/private execution or compiled fixture acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/', base = '104e4e156ed187a8e5980813efc901bb08d2bd34';
const read = file => require('./check-connector-acceptance-evidence-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n')), cache = new Map();
function old(file) {
  if (!cache.has(file)) cache.set(file, cp.execFileSync('git', ['show', `${base}:${file}`],
    {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  return cache.get(file);
}
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
const localBlock = `    if let profile = activeLocalProfiles.first {
      var local = AgentCallableTarget(
        id: "local-llm",
        title: profile.displayName.ifBlank(profile.id),
        kind: .model,
        status: localModelReady(profile) ? .available : .needsSetup,
        capabilities: [.chat, .reasoning, .toolUse, .localInference],
        failureDomain: "local-model",
        adapterType: "ios-local-model"
      )
      local.providerProfile = ProviderProfileCatalog.phoneLocalModelProfile(for: local, modelId: profile.id,
        contextWindowTokens: min(LocalModelRuntimeSettings.contextTokens(), profile.maximumContextTokens))
      targets.append(local)
    }
`;
function retained(file, source) {
  source = require('./check-connector-acceptance-evidence-scope.cjs').retained(file, source);
  if (file.endsWith('check-scored-route-context-scope.cjs')) return source
    .replace("const read = file => require('./check-phone-local-model-resource-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')), cache = new Map();",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'), cache = new Map();")
    .replace("  source = require('./check-phone-local-model-resource-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('AgentPhoneLocalModelResourceTests.swift')).join('\n');
  if (file.endsWith('AgentProviderProfileCatalog.swift') && source.includes('  static func isPhoneLocalModel(')) return source
    .replace(section(source, '  static func isPhoneLocalModel(', '  static func fromTarget('), '')
    .replace('    if let phone = phoneLocalModelProfile(for: target) { return phone }\n', '');
  if (file.endsWith('AgentNetworkRoutingModels.swift') && source.includes('var local = AgentCallableTarget(')) {
    const start = '    if let profile = activeLocalProfiles.first {', end = '    return targets\n  }\n\n  static func selectableAgentTargets';
    assert.equal(section(source, start, end), localBlock);
    return source.replace(localBlock, section(old(file), start, end))
      .replace('    if ProviderProfileCatalog.isPhoneLocalModel(target) { return .onDeviceModel }\n', '');
  }
  return source;
}
function validate() {
  for (const file of [app + 'AgentProviderProfileCatalog.swift', app + 'AgentNetworkRoutingModels.swift',
    'apps/ios/GalaxySSI.xcodeproj/project.pbxproj', 'apps/ios/tools/check-scored-route-context-scope.cjs'])
    assert.equal(retained(file, read(file)), old(file), file);
  const profile = read(app + 'AgentProviderProfileCatalog.swift');
  const native = section(profile, '  static func isPhoneLocalModel(', '  static func fromTarget(');
  for (const token of ['target.id == "local-llm"', 'target.kind == .model', 'target.adapterType == "ios-local-model"',
    'target.capabilities.contains(.localInference)', 'profile.resourceId == target.id', 'profile.location == .phone',
    'profile.adapterType == target.adapterType', 'providerId: "galaxyssi-connectors"', 'productId: "local-llm"',
    'maxOutputTokens: 0, maxParallelRuns: 2', 'trust: .phoneSystem', 'ProviderPricingProfile(tier: .free)',
    'supportsBackground: false', '"native_product_identity": "local-llm"']) assert(native.includes(token), token);
  assert(profile.indexOf('if let providerProfile = target.providerProfile') < profile.indexOf('if let phone = phoneLocalModelProfile(for: target)'));
  for (const token of ['URLSession', 'FileManager', 'generateAsync', 'setContextTokens', '.set(', 'recordSuccess']) assert(!native.includes(token), token);
  const tests = read('apps/ios/GalaxySSITests/AgentPhoneLocalModelResourceTests.swift');
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  for (const token of ['AgentCallableTargetCatalog.build(', 'AgentResourceCatalog.build(', 'AgentTaskBudgetPolicy.evaluate(',
    'AgentAutomaticRouteAdmission.rejectionReason(', 'AgentRuntimeIdentity.key(before)', 'remote.adapterType = "ollama"']) assert(tests.includes(token), token);
  for (const file of ['GalaxySSIServices', 'AgentTaskBudgetModels', 'AgentGlobalRunSlots', 'LocalModelInferenceRuntime',
    'LocalModelRuntimePreflightModels', 'AgentProviderResourceRanking', 'AgentDataDisclosureLedger', 'MqttBusinessTransportRuntime'])
    assert.equal(read(app + file + '.swift'), old(app + file + '.swift'), file);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n')
    .filter(line => line.includes('AgentPhoneLocalModelResourceTests.swift')).length, 4);
  console.log('Native phone model classification, ready/profile binding, offline admission and retained remote/runtime identity source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
