// Source contracts only; no Swift compile, OS path observation, native sockets or XCTest.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), base = '4c2c22aed7c281d1aaeee38f3f258d5c24313ddc', app = 'apps/ios/GalaxySSI/';
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const old = file => cp.execFileSync('git', ['show', base + ':' + file], {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const policyMarker = '// Network-epoch sampling fixtures; authored only unless executed by XCTest.';
const poolMarker = '// Owned network-observer fixtures; callbacks are synthetic and no OS monitor starts.';
function section(s, a, b) { const x = s.indexOf(a), y = s.indexOf(b, x + a.length); assert(x >= 0 && y > x, a); return s.slice(x, y); }
function retained(file, s) {
  if (file === app + 'GalaxySSIMqttBrokerPool.swift' && s.includes('protocol MqttPoolNetworkMonitoring:')) return s
    .replace(section(s, 'import Network\n', '// Each path owns'), '\n')
    .replace('  private let makeNetworkMonitor: () -> MqttPoolNetworkMonitoring?\n  private var networkMonitor: MqttPoolNetworkMonitoring?\n', '')
    .replace('       networkMonitorFactory: @escaping () -> MqttPoolNetworkMonitoring? = { MqttPoolNetworkMonitor() },\n', '')
    .replace('    self.makeNetworkMonitor = networkMonitorFactory\n', '')
    .replace('      self.startNetworkMonitor()\n', '')
    .replace(section(s, '  private func startNetworkMonitor()', '  func readyGenerations('), '')
    .replace('      self.networkMonitor?.cancel()\n      self.networkMonitor = nil\n', '')
    .replace('    networkMonitor?.cancel()\n', '');
  if (file === app + 'MqttMultipathPolicy.swift') return s
    .replace('    fileprivate var metricEpoch = ""\n', '')
    .replace('  private var metricEpoch = UUID().uuidString\n', '')
    .replace('      metricEpoch = UUID().uuidString\n', '')
    .replace('      clean.metricEpoch = metricEpoch\n', '')
    .replace('if now >= accepted.startedAt, accepted.metricEpoch == metricEpoch {', 'if now >= accepted.startedAt {');
  if (file.endsWith('MqttMultipathPolicyTests.swift') && s.includes(policyMarker))
    return s.slice(0, s.indexOf(policyMarker)).trimEnd() + '\n';
  if (file.endsWith('MqttBrokerPoolTests.swift') && s.includes(poolMarker))
    s = s.slice(0, s.indexOf(poolMarker)).trimEnd() + '\n';
  if (/apps\/ios\/GalaxySSITests\/Mqtt(?:BrokerPool|PeerRoutes|SealedPath|SignalSendTransaction)Tests\.swift$/.test(file))
    return s.replaceAll('GalaxySSIMqttBrokerPool(networkMonitorFactory: { nil }) {', 'GalaxySSIMqttBrokerPool {');
  return s;
}
function includes(s, values) { for (const value of values) assert(s.includes(value), value); }
function validate() {
  for (const file of [app + 'GalaxySSIMqttBrokerPool.swift', app + 'MqttMultipathPolicy.swift',
    ...['MqttBrokerPool', 'MqttMultipathPolicy', 'MqttPeerRoutes', 'MqttSealedPath', 'MqttSignalSendTransaction']
      .map(name => 'apps/ios/GalaxySSITests/' + name + 'Tests.swift')]) {
    assert.equal(retained(file, read(file)), old(file), 'Only declared observer/metric-epoch hooks: ' + file);
    assert.equal(retained(file, retained(file, read(file))), old(file), 'Idempotent retained normalizer: ' + file);
  }
  const pool = read(app + 'GalaxySSIMqttBrokerPool.swift');
  const observer = section(pool, 'protocol MqttPoolNetworkMonitoring:', '// Each path owns');
  includes(observer, ['private let monitor = NWPathMonitor()', 'private var previous: NWPath?',
    'self.previous != path', 'self.previous = path', 'changed()', 'monitor.start(queue: queue)', 'func cancel() { monitor.cancel() }']);
  assert(!/\.debugDescription|\.description|\.availableInterfaces|\.gateways|\.localEndpoint|\.remoteEndpoint|UserDefaults|print\(|Logger/.test(observer));
  const owned = section(pool, '  private func startNetworkMonitor()', '  func readyGenerations(');
  includes(owned, ['networkMonitor?.cancel()', 'networkMonitor = nil', 'guard let monitor = makeNetworkMonitor()',
    'networkMonitor = monitor', 'let configuration = configurationID', 'monitor.start(queue: queue)', '[weak self, weak monitor]',
    'self.queue.async', 'self.running', 'self.networkMonitor === monitor', 'self.configurationID == configuration',
    'self.policy.setNetwork(UUID().uuidString)']);
  assert(!/configurePath|publish\(|disconnect\(|onPathState|wakeForTraffic|sendFrame/.test(owned));
  includes(pool, ['networkMonitorFactory: @escaping () -> MqttPoolNetworkMonitoring? = { MqttPoolNetworkMonitor() }', 'self.startNetworkMonitor()']);
  const stop = section(pool, '  func disconnect()', '  deinit {');
  includes(stop, ['self.running = false', 'self.networkMonitor?.cancel()', 'self.networkMonitor = nil']);
  assert(stop.indexOf('self.running = false') < stop.indexOf('self.networkMonitor?.cancel()'));
  includes(pool.slice(pool.indexOf('  deinit {')), ['networkMonitor?.cancel()']);
  const policy = read(app + 'MqttMultipathPolicy.swift');
  const network = section(policy, '  func setNetwork(', '  @discardableResult');
  includes(network, ['guard network != value else { return }', 'metricEpoch = UUID().uuidString',
    'rtt.removeAll()', 'samplesByBroker.removeAll()', 'chunks.reset()']);
  assert(!/attempts\.|routes\.|paths\./.test(network));
  includes(section(policy, '  func reserveReason(', '  @discardableResult\n  func brokerAck('), ['clean.metricEpoch = metricEpoch']);
  const receipt = section(policy, '  func acceptVerifiedReceipt(', '  @discardableResult\n  func acceptVerifiedMessage(');
  includes(receipt, ['if now >= accepted.startedAt, accepted.metricEpoch == metricEpoch {',
    'return acceptVerifiedMessage(peer: peer, messageID: messageID, contentHash: contentHash)']);
  assert(receipt.indexOf('return acceptVerifiedMessage(') > receipt.indexOf('samplesByBroker[accepted.brokerID] ='));
  const policyTests = read('apps/ios/GalaxySSITests/MqttMultipathPolicyTests.swift').split(policyMarker)[1];
  assert.equal((policyTests.match(/func test/g) || []).length, 6);
  includes(policyTests, ['testOldNetworkReceiptCompletesMessageWithoutTrainingNewNetworkRTT',
    'testSameNetworkKeyKeepsSamplesAndPendingAttemptEligibility', 'testReturningToAnEarlierNetworkKeyDoesNotReviveOldAttemptSamples',
    'testNewNetworkAttemptsStillTrainOnlyOnceAfterVerifiedReceipt', 'testOldNetworkWinnerCompletesNewHedgeWithoutCreatingAnAttributedSample',
    'testNetworkResetDiscardsOldChunkMetricFlightsWithoutChangingReadyRoutes']);
  const poolTests = read('apps/ios/GalaxySSITests/MqttBrokerPoolTests.swift').split(poolMarker)[1];
  assert.equal((poolTests.match(/func test/g) || []).length, 5);
  includes(poolTests, ['testCurrentNetworkObserverResetsSamplesWithoutChangingPathReadiness',
    'testOldNetworkObserverAfterReconfigurationCannotResetNewSamples', 'testReusedObserverStillFencesOldConfigurationCallbacks',
    'testDisconnectedPoolCancelsAndIgnoresOldNetworkObserver', 'testDisabledObserverKeepsInjectedFixtureMetricsDeterministic']);
  for (const file of ['MqttBrokerPool', 'MqttPeerRoutes', 'MqttSealedPath', 'MqttSignalSendTransaction']) {
    const source = read('apps/ios/GalaxySSITests/' + file + 'Tests.swift');
    const original = file === 'MqttBrokerPool' ? source.split(poolMarker)[0] : source;
    assert(!/GalaxySSIMqttBrokerPool \{/.test(original), 'All old fake pools disable the OS observer: ' + file);
  }
  const guard = 'apps/ios/tools/check-mqtt-path-diagnostics-scope.cjs';
  const mainProjectRetention = `    if (name.includes('network-lifecycle')) expected = expected
      .replace("const old = file => cp.execFileSync('git', ['show', base + ':' + file]", "const old = (file, ref = base) => cp.execFileSync('git', ['show', ref + ':' + file]")
      .replace("old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'), 'No deployment, source registration or version churn'", "old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj', 'c1e1529ed1160a34564eb57606dfd209fc7a61ba'), 'Retain latest main deployment, source registration and version'");
`;
  const expected = old(guard)
    .replace("    if (name.includes('active-native')) expected", mainProjectRetention + "    if (name.includes('active-native')) expected")
    .replace("const syncedMain = '26259d6503ef4b60ce8eb2346a1bbb2b85bbf12d';", "const syncedMain = 'c1e1529ed1160a34564eb57606dfd209fc7a61ba';")
    .replace("old(stringsFile), 'Append only diagnostic resource keys'", "old(stringsFile, syncedMain), 'Append only diagnostic resource keys'")
    .replace("old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj'));", "old('apps/ios/GalaxySSI.xcodeproj/project.pbxproj', syncedMain));")
    .replace("const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');",
      "const read = file => require('./check-mqtt-network-metrics-scope.cjs').retained(file, fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));")
    .replace('function retained(file, s) {\n', "function retained(file, s) {\n  s = require('./check-mqtt-network-metrics-scope.cjs').retained(file, s);\n");
  assert.equal(read(guard), expected, 'Previous diagnostic assertions retained');
  for (const name of ['GalaxySSIMqttClient', 'MqttPeerRoutes', 'MqttDeliveryDispatch', 'MqttBusinessTransportRuntime',
    'MqttBusinessReceipts', 'MqttBusinessInbox', 'MqttBusinessOutbox', 'MqttSignalStateJournal', 'MqttChunkThroughput'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), 'No socket/durable/receipt or chunk encoding changes: ' + name);
  console.log('Owned OS network-change observer, old-attempt sample fencing without delivery loss, deterministic fake pools and eleven authored-only fixtures passed source checks; no native/network acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
