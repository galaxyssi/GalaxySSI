// Source contracts only; no Foundation, XCTest, DNS, HTTP or renderer execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '8a794e82ebe8f09790e41139295ffb7ac1ee9701';
const app = 'apps/ios/GalaxySSI/', tests = 'apps/ios/GalaxySSITests/AgentIOSWebMediaNativeToolTests.swift';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const unknown = 'provider_network_policy_unspecified', pinned = 'public_https_pinned_dns_v1';
const extra = `    for definition in definitions where [AgentIOSWebMediaNativeToolCatalog.webSearch,
      AgentIOSWebMediaNativeToolCatalog.webFetch, AgentIOSWebMediaNativeToolCatalog.httpRequest,
      AgentIOSWebMediaNativeToolCatalog.webHead, AgentIOSWebMediaNativeToolCatalog.fileDownload,
      AgentIOSWebMediaNativeToolCatalog.webDownload].contains(definition.id) {
      XCTAssertEqual(definition.provenanceMetadata["network_policy"], "provider_network_policy_unspecified")
    }
    provider.declaredNetworkPolicy = "synthetic_explicit_policy"
    var declaredContext = networkContext
    declaredContext.invocationId = "declared-network-policy"
    let declared = registry.invoke(AgentIOSWebMediaNativeToolCatalog.webSearch,
      input: ["query": .string("GalaxySSI"), "max_results": .int(1)], context: declaredContext)
    XCTAssertTrue(declared.isSuccess)
    XCTAssertEqual(declared.metadata["network_policy"], .string("synthetic_explicit_policy"))
`;
const raw = "fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')";
const wrapped = "require('./check-web-network-assurance-scope.cjs').retained(file, " + raw + ')';
const hooks = new Map([
  ...['check-special-use-address-scope.cjs', 'check-public-address-policy-scope.cjs', 'check-image-search-fusion-scope.cjs', 'check-public-search-parsing-scope.cjs'].map(name => [name, [raw, wrapped]]),
  ['check-search-result-capacity-scope.cjs', ["clean(fs.readFileSync(path.join(root, file), 'utf8'))", "require('./check-web-network-assurance-scope.cjs').retained(file, clean(fs.readFileSync(path.join(root, file), 'utf8')))" ]],
  ['check-encoded-web-request-scope.cjs', ["  let source = clean(fs.readFileSync(path.join(root, file), 'utf8'));", "  let source = clean(fs.readFileSync(path.join(root, file), 'utf8'));\n  source = require('./check-web-network-assurance-scope.cjs').retained(file, source);"]]
]);
function retained(file, source) {
  if (file.endsWith('AgentIOSWebMediaNativeTools.swift')) return source.split(unknown).join(pinned);
  if (file.endsWith('AgentIOSWebMediaNativeToolTests.swift')) return source
    .replace('      var declaredNetworkPolicy: String?\n', '')
    .replace('          var metadata: AgentMcpJSONObject = [:]\n          if let declaredNetworkPolicy { metadata["network_policy"] = .string(declaredNetworkPolicy) }\n', '')
    .replace(']) { current, _ in current }, metadata: metadata', ']) { current, _ in current }')
    .replace(extra, '').split(unknown).join(pinned);
  const hook = hooks.get(file.replace(/\\/g, '/').split('/').pop());
  return hook ? source.replace(hook[1], hook[0]) : source;
}
function validate() {
  const file = app + 'AgentIOSWebMediaNativeTools.swift', source = read(file);
  assert.equal(source.split(unknown).length, 4);
  assert(!source.includes(pinned));
  assert.equal(retained(file, source), old(file));
  assert(source.includes('metadata["network_policy"] ?? .string("' + unknown + '")'));
  assert.equal(retained(tests, read(tests)), old(tests));
  assert(read(tests).includes(extra));
  for (const [name, hook] of hooks) {
    const file = 'apps/ios/tools/' + name;
    assert.equal(read(file), old(file).replace(hook[0], hook[1]), name);
  }
  for (const name of ['AgentIOSURLSessionWebMediaProvider', 'AgentIOSURLSessionWebIntelligenceProvider',
    'AgentIOSDynamicWebRenderer', 'AgentIOSPublicAddressPolicy', 'AgentIOSWebCrawlPolicy', 'AgentIOSWebEvidencePack'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  console.log('Unspecified provider DNS assurance, declared policy preservation, retained production transport and extended fixture source contracts passed; no native/network acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
