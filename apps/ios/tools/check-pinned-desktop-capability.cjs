// Presence source contracts only, not Swift, pairing, MQTT or Desktop execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = '280195ad2021a2cf6bb8cf1c48ea1f97b01be129';
const memo = new Map(), clean = s => s.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, clean(cp.execFileSync('git', ['show', key], {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})));
  return memo.get(key);
}
function section(s, first, last) {
  assert.equal(s.split(first).length, 2, first);
  const a = s.indexOf(first), b = s.indexOf(last, a + first.length); assert(b > a, last); return s.slice(a, b);
}
function once(s, from, to = '') { assert.equal(s.split(from).length, 2, from); return s.replace(from, to); }
const historyGuard = s => section(s, '      if contact.isDesktopHistoryOnly', '      contact.desktop_disconnected = nil');
function retainedStore(s) {
  if (!s.includes('      let capabilityInventory = AgentPinnedDesktopCodexCapability.inventory(payload)')) return s;
  const file = app + 'GalaxySSIStore.swift';
  for (const [first, last] of [
    ['  @discardableResult\n  private func upsertDesktopAgentContacts(payloads:', '  private func desktopAgentPayloads(from pairing:'],
    ['  private func desktopAgentPayloads(\n    from agents:', '  private func singleDesktopAgentPayload(']
  ]) {
    const block = section(s, first, last);
    let normalized = block, original = section(show(base, file), first, last);
    if (first.includes('upsertDesktopAgentContacts')) {
      const paired = historyGuard(show('c1a85545b107b89f353fe73c7003008cbf5629ed', file));
      if (historyGuard(block) === paired) {
        normalized = once(normalized, paired, historyGuard(original));
        original = once(original, historyGuard(original), paired);
      }
    }
    assert.equal(normalized, section(show(approved, file), first, last), 'Exact compact presence reception/inheritance only');
    s = once(s, block, original);
  }
  const marker = '  private func connectorProtocols(from payload:';
  return once(s, marker, section(show(base, file), '  private func connectorCapabilities(from payload:', marker) + marker);
}
module.exports = {retainedStore};
if (require.main === module) {
  const file = app + 'GalaxySSIStore.swift', source = read(file);
  let retained = retainedStore(source);
  for (const [name, method] of [['check-cloud-tool-invocation-journal', 'retainedStore'], ['check-pairing-history', 'retainedPairingStore']]) {
    const optional = path.join(__dirname, name + '.cjs');
    if (fs.existsSync(optional)) retained = require(optional)[method](retained);
  }
  assert.equal(retained, show(base, file), 'All non-presence Store behavior retained outside exact optional reset/pairing hooks');
  const helperFile = app + 'AgentPinnedDesktopCodexCapability.swift', helper = read(helperFile);
  const testsFile = 'apps/ios/GalaxySSITests/AgentPinnedDesktopCodexCapabilityTests.swift', tests = read(testsFile);
  assert.equal(helper, show(approved, helperFile)); assert.equal(tests, show(approved, testsFile));
  const core = app + 'GalaxySSICoreModels.swift';
  assert.equal(once(read(core), '  var pinned_team_codex_v1: Bool? = nil\n'), show(base, core), 'Only optional wire-compatible contact metadata added');
  for (const token of ['agent["capabilities"] as? [Any]', '($0 as? String) == id',
    'advertised(agent), remaining.isEmpty, adapter == nil', 'remaining.count != strings.count',
    'agentID == "codex", advertised(agent), let link, link.paired', 'desktopID == link.desktopId',
    'fingerprint.caseInsensitiveCompare(link.desktopFingerprint) == .orderedSame']) assert(helper.includes(token), token);
  assert(!/URLSession|\.execute\(|\.publish\(|grantedPermissions|grantedConsents|\.claim\(/.test(helper));
  for (const token of ['if let connectorCapabilities {', 'else if !preserveCompactMetadata',
    'compactPinAdvertisement && !desktopFingerprint.isBlank &&',
    'priorContact?.identityFingerprint.caseInsensitiveCompare(desktopFingerprint) == .orderedSame',
    'priorContact?.deliveryMode.isGalaxySSILinkFamily == true',
    'compactPinAdvertisement && !preserveCompactMetadata', 'capabilityInventory?.markerRemoved == true',
    'AgentPinnedDesktopCodexCapability.inheritedCapabilities(value)',
    '["adapter", "provider_profile", "invocation_profile"].contains(key)']) assert(source.includes(token), token);
  let negatives = 0;
  for (const token of ['($0 as? String) == id', 'remaining.isEmpty, adapter == nil', 'agentID == "codex",',
    'link.paired', 'desktopID == link.desktopId', '!fingerprint.isBlank',
    'fingerprint.caseInsensitiveCompare(link.desktopFingerprint) == .orderedSame', 'remaining.count != strings.count']) {
    assert(helper.includes(token)); assert.throws(() => assert.equal(helper.replace(token, ''), show(approved, helperFile)), assert.AssertionError); negatives++;
  }
  for (const token of ['if let connectorCapabilities {', 'else if !preserveCompactMetadata',
    'compactPinAdvertisement && !desktopFingerprint.isBlank &&',
    'priorContact?.identityFingerprint.caseInsensitiveCompare(desktopFingerprint) == .orderedSame',
    'priorContact?.deliveryMode.isGalaxySSILinkFamily == true', 'capabilityInventory?.markerRemoved == true',
    'AgentPinnedDesktopCodexCapability.boundAdvertisement(payload',
    'AgentPinnedDesktopCodexCapability.inheritedCapabilities(value)',
    '["adapter", "provider_profile", "invocation_profile"].contains(key)']) {
    assert(source.includes(token)); assert.throws(() => retainedStore(source.replace(token, '')), assert.AssertionError); negatives++;
  }
  const paired = historyGuard(show('c1a85545b107b89f353fe73c7003008cbf5629ed', file));
  const combined = once(source, historyGuard(source), paired);
  assert.equal(historyGuard(retainedStore(combined)), paired, 'Pending stronger fingerprint restoration remains intact');
  assert.throws(() => retainedStore(combined.replace('GalaxySSIPairingLifecycle.canRestoreHistory(contact, pairedFingerprint: current.desktopFingerprint)', 'true')), assert.AssertionError);
  negatives++;
  for (const name of ['AgentConnectorModels', 'AgentNetworkRoutingModels', 'AgentPlanLifecyclePolicy'])
    assert.equal(read(app + name + '.swift'), show(base, app + name + '.swift'), name + ' execution/selection policy unchanged');
  assert.equal((tests.match(/  func test/g) || []).length, 12);
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const registrations = s => s.split('\n').filter(line => /AgentPinnedDesktopCodexCapability(?:Tests)?\.swift/.test(line));
  assert.equal(registrations(read(projectFile)).length, 8);
  assert.deepEqual(registrations(read(projectFile)), registrations(show(approved, projectFile)));
  const android = show('fe9259f1b9ef7ec5ea69c4f83b65abc40ae172d0', 'apps/android/app/src/main/java/com/galaxyssi/chat/PinnedDesktopTeam.kt');
  assert(android.includes('const val CAPABILITY = "pinned_team_codex_v1"'));
  assert(android.includes('rest.takeUnless { it.length() == 0 && adapter == null }'));
  assert(!/\p{Script=Han}/u.test(helper + tests));
  console.log(`Compact Codex pin presence, identity-scoped metadata retention and ${negatives} negative source mutations checked; twelve Swift fixtures authored, not executed. Full Android #4694 entry/dispatch parity is not claimed.`);
}
