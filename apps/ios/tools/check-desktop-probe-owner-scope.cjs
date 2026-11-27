// Source contracts only; does not execute Swift, MQTT, timers or native fixtures.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '1d68be9b738d8cbc48745b51554dbb24b4aa3129';
const read = file => require('./check-connector-acceptance-evidence-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
const old = file => cp.execFileSync('git', ['show', `${base}:${file}`],
  {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n');
const hook = '      // Offline legacy probes also advance the clock owned by the journal query pump.\n' +
  '      guard usesLegacyMqtt else { continue }\n';
function retained(file, source) {
  source = require('./check-connector-acceptance-evidence-scope.cjs').retained(file, source);
  if (file.endsWith('GalaxySSIServices.swift')) return source.replace(hook, '');
  if (file.endsWith('check-phone-local-model-resource-scope.cjs')) return source
    .replace("const read = file => require('./check-desktop-probe-owner-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n')), cache = new Map();",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'), cache = new Map();")
    .replace("  source = require('./check-desktop-probe-owner-scope.cjs').retained(file, source);\n", '');
  return source;
}
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function validate() {
  const serviceFile = app + 'GalaxySSIServices.swift', source = read(serviceFile);
  assert.equal(source.split(hook).length, 2, 'One explicit legacy probe-owner gate');
  assert.equal(retained(serviceFile, source), old(serviceFile), 'All other coordinator behavior retained');
  const sweep = section(source, '  private func sweepDesktopReplyRecovery()', '  private func discoverLegacyDesktopReplies()');
  assert(sweep.includes(hook + '      let online = mqttClient.relationshipSubscriptionsReady\n' +
    '      if online && published >= 8 { continue }\n' +
    '      let observationRequest = desktopReplyRecovery.request(binding, online: online, now: now)'));
  assert(sweep.indexOf('if record.codexDispatchPending == true') < sweep.indexOf(hook), 'Do not disable journal Codex dispatch');
  assert(sweep.indexOf('completeAcceptedDesktopReply(record)') < sweep.indexOf(hook), 'Retain committed-result projection');
  assert(sweep.indexOf('persistRecoveredDesktopResult(payload, record: record)') < sweep.indexOf(hook));
  const recovery = read(app + 'AgentDesktopReplyRecovery.swift');
  const request = section(recovery, '  func request(_ binding:', '  @discardableResult\n  func observeLiveLease(');
  assert(request.indexOf('record.lastProbeAt = now') < request.indexOf('guard save(next), online else'));
  assert(request.indexOf('record.misses = min(record.misses, 1_000_000) + 1') < request.indexOf('guard save(next), online else'));
  const journal = section(source, '  private func journalBackedDesktopRecoveryQueries(', '  private func commitJournalBackedDesktopResult(');
  assert(journal.includes('guard requests.count < 4, ready(record.binding) else { continue }'));
  assert(journal.includes('desktopReplyRecovery.request(record.binding, online: true, now: now)'));
  const pump = section(read(app + 'MqttBusinessTransportRuntime.swift'), '  private func pumpDesktopRecoveryQueries()', '  private func pumpDesktopResultReceipts()');
  for (const token of ['target.routeId == binding.identity.clientRouteId', '!revokingScopes.contains',
    'routes.readyForTopic', 'connector.recoveryQueryRequest(payload, target: target)',
    'engine.makeRecoveryQueryWire(request)', 'routes.publishTransientControl']) assert(pump.includes(token), token);
  for (const file of ['AgentDesktopReplyRecovery', 'AgentDesktopResultRecovery', 'MqttBusinessTransportRuntime',
    'MqttDesktopConnectorProjection', 'AgentConnectorTimeoutResolver', 'AgentAutomationModels'])
    assert.equal(read(app + file + '.swift'), old(app + file + '.swift'), file);
  const parent = 'apps/ios/tools/check-phone-local-model-resource-scope.cjs';
  assert.equal(retained(parent, read(parent)), old(parent), 'Parent scope assertions retained');
  console.log('Exclusive legacy probe ownership, retained journal readiness/authentication and unchanged recovery kernels source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
