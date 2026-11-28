// Source contracts only. Async fixtures are authored, not executed; no socket/device acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '320d47d69ffaed94011a630664c6b08302eeaeec', approved = 'bec54c2dd2460fe3efd30a28a80c61b9219e997f';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = f => clean(fs.readFileSync(path.join(root, f), 'utf8'));
function git(args) { return clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})); }
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, git(['show', key]));
  return memo.get(key);
}
function once(source, from, to) {
  assert(from.length > 0); assert.equal(source.split(from).length, 2, 'Exact unique physical admission hunk: ' + from.slice(0, 220));
  return source.replace(from, to);
}
function retained(file, source) {
  const scoped = path.join(__dirname, 'check-scoped-member-recall.cjs');
  if (fs.existsSync(scoped)) source = require(scoped).retained(file, source);
  if (file.endsWith('/GalaxySSILinkReliability.swift')) {
    if (!source.includes('pinnedDesktopRunID')) return source;
    if (source.includes('AgentLearningOutboxScope')) {
      // Preserve the separately owned learning scope, including both adjacent optional arguments.
      const bridges = [
        ['  var backgroundLearning = false\n  var learningScope: AgentLearningOutboxScope? = nil\n  var attachmentDeclaration: String? = nil\n  var fileReadScope: String? = nil\n  var pinnedDesktopRunID: String? = nil',
          '  var backgroundLearning = false\n  var attachmentDeclaration: String? = nil\n  var fileReadScope: String? = nil\n  var pinnedDesktopRunID: String? = nil',
          '  var backgroundLearning = false\n  var attachmentDeclaration:',
          '  var backgroundLearning = false\n  var learningScope: AgentLearningOutboxScope? = nil\n  var attachmentDeclaration:'],
        ['    fileReadScope: String? = nil,\n    learningScope: AgentLearningOutboxScope? = nil,\n    pinnedDesktopRunID: String? = nil',
          '    fileReadScope: String? = nil,\n    pinnedDesktopRunID: String? = nil',
          '    fileReadScope: String? = nil\n', '    fileReadScope: String? = nil,\n    learningScope: AgentLearningOutboxScope? = nil\n'],
        ['    backgroundLearning: Bool = false,\n    learningScope: AgentLearningOutboxScope? = nil,\n    pinnedDesktopRunID: String? = nil,',
          '    backgroundLearning: Bool = false,\n    pinnedDesktopRunID: String? = nil,',
          '    backgroundLearning: Bool = false,\n    now: Date', '    backgroundLearning: Bool = false,\n    learningScope: AgentLearningOutboxScope? = nil,\n    now: Date'],
        ['          backgroundLearning: backgroundLearning,\n          learningScope: learningScope,\n          pinnedDesktopRunID: pinnedDesktopRunID',
          '          backgroundLearning: backgroundLearning,\n          pinnedDesktopRunID: pinnedDesktopRunID',
          '          backgroundLearning: backgroundLearning\n', '          backgroundLearning: backgroundLearning,\n          learningScope: learningScope\n'],
        ['          attachmentDeclaration: request.attachmentDeclaration,\n          learningScope: request.learningScope,\n          pinnedDesktopRunID: request.pinnedDesktopRunID',
          '          attachmentDeclaration: request.attachmentDeclaration,\n          pinnedDesktopRunID: request.pinnedDesktopRunID',
          '          attachmentDeclaration: request.attachmentDeclaration\n', '          attachmentDeclaration: request.attachmentDeclaration,\n          learningScope: request.learningScope\n']
      ];
      for (const [from, to] of bridges) source = once(source, from, to);
      source = retainedExact(file, source);
      for (const [, , from, to] of bridges) source = once(source, from, to);
      return source;
    }
  }
  if (file.endsWith('/GalaxySSIServices+Outbox.swift') && !source.includes('pinnedDesktopOutboxAllowed')) return source;
  return retainedExact(file, source);
}
function retainedExact(file, source) {
  const patch = git(['diff', '--no-ext-diff', '--no-color', '--unified=3', base, approved, '--', file]);
  let old = [], current = [], active = false;
  function flush() {
    if (active) source = once(source, current.join('\n') + '\n', old.join('\n') + '\n');
    old = []; current = [];
  }
  for (const line of patch.split('\n')) {
    if (line.startsWith('@@ ')) { flush(); active = true; continue; }
    if (!active || !line) continue;
    if (line.startsWith(' ')) { old.push(line.slice(1)); current.push(line.slice(1)); }
    else if (line.startsWith('-')) old.push(line.slice(1));
    else if (line.startsWith('+')) current.push(line.slice(1));
    else assert(line.startsWith('\\ No newline'), 'Unexpected diff format');
  }
  flush(); assert(active, file); return source;
}
function retainedServices(source) {
  return source.includes('  private func pinnedDesktopQueuedSendIsCurrent(') ? retained(app + 'GalaxySSIServices.swift', source) : source;
}
function optional(name, method, source, file) {
  const moduleFile = path.join(__dirname, name + '.cjs');
  if (!fs.existsSync(moduleFile)) return source;
  return method === 'retained' ? require(moduleFile)[method](file, source) : require(moduleFile)[method](source);
}
function canonical(file, source) {
  if (file === app + 'GalaxySSIServices.swift') {
    for (const [name, method] of [['check-pinned-desktop-team', 'retainedServices'],
      ['check-browser-view-ownership', 'retainedBrowserServices'], ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
      ['check-pairing-history', 'retainedPairingServices']]) source = optional(name, method, source, file);
  } else if (['GalaxySSIServices+Outbox.swift', 'GalaxySSILinkReliability.swift'].some(name => file === app + name)) {
    source = optional('check-learning-outbox-scope', 'retained', source, file);
  }
  return source;
}
module.exports = {retainedServices, retained};
if (require.main === module) {
  const files = ['AgentTeamExecutionHistoryStore', 'AgentTeamExecutionModels', 'GalaxySSILinkReliability',
    'GalaxySSIMqttClient', 'GalaxySSIServices+Outbox', 'GalaxySSIServices', 'MqttBusinessSendDrain',
    'MqttDeliveryDispatch', 'MqttDesktopConnectorProjection', 'MqttPeerRoutes'].map(name => app + name + '.swift');
  files.push('apps/ios/GalaxySSITests/MqttDeliveryDispatchTests.swift');
  for (const file of files) assert.equal(canonical(file, retained(file, read(file))), canonical(file, show(base, file)), file);
  const testsFile = 'apps/ios/GalaxySSITests/AgentPinnedDesktopOutboxTests.swift';
  assert.equal(read(testsFile), show(approved, testsFile));
  assert.equal((read(testsFile).match(/  func test/g) || []).length, 7);
  const client = read(app + 'GalaxySSIMqttClient.swift'), services = read(app + 'GalaxySSIServices.swift');
  const admission = client.slice(client.indexOf('      let candidate = pendingPacketPublishes[index]'), client.indexOf('  private func canSend('));
  for (const token of ['applicationAdmission = ticket', 'let allowed = await authorize()',
    'guard self.applicationAdmission == ticket', 'self.connectionGeneration == generation',
    'self.mqttInflightPacketIds.count < Self.maximumMqttInflight', 'self.canSend(pending)',
    'pending.pathGate.map({ self.authorizes($0) }) ?? true', 'self.writePendingPublication(pending)',
    'self.finishPhysical(pending, acknowledged: false)']) assert(admission.includes(token), token);
  assert(admission.indexOf('await authorize()') < admission.indexOf('self.pendingPacketPublishes.remove(at: current)'), 'Awaited packet remains bounded');
  assert(client.includes('applicationAdmission == nil || $0.applicationAuthorization == nil'), 'Ungated control traffic can drain');
  assert.equal((client.match(/    applicationAdmission = nil/g) || []).length, 2, 'Stop and reconnect invalidate callbacks');
  const outbox = read(app + 'GalaxySSIServices+Outbox.swift');
  assert(outbox.indexOf('pinnedDesktopOutboxAllowed(item) == false') < outbox.indexOf('await mqttClient.publishDurable('));
  const tokens = new Map([
    ['GalaxySSIServices', ['roster.pinnedDesktop == pin', 'routes.remoteFingerprint.caseInsensitiveCompare(pin.route.fingerprint) == .orderedSame',
      'AgentTaskExecutionModePolicy.resolve(request: pin.objective,', '[.paused, .cancelled, .failed, .blocked].contains(task.phase)',
      'identity.taskId == context.owner.sourceMessageId, identity.clientRouteId == pin.route.clientRoute', 'source.content == pin.objective',
      'return try managedBrowserContinuations.control(scope: scope) == .run',
      'savedTeam.pinnedDesktop = store.agentSession', 'pinnedDesktopRunID: desktopPin.map']],
    ['AgentTeamExecutionHistoryStore', ['current.pinnedDesktop == incoming.pinnedDesktop']],
    ['GalaxySSILinkReliability', ['self.pinnedDesktopRunID = pinnedDesktopRunID', 'case pinnedDesktopRunID = "pinned_desktop_run_id"',
      'pinnedDesktopRunID: request.pinnedDesktopRunID']],
    ['MqttBusinessSendDrain', ['direct.applicationAuthorization =', 'saved.wireHash == message.contentHash', 'return (try? await authorize(saved)) == true']],
    ['MqttDesktopConnectorProjection', ['payload.string(AgentPinnedDesktopTeam.pinKey) == pin.route.digest',
      'payload.string(AgentPinnedDesktopTeam.personKey) == team.memberId',
      'payload.string("result_contract") == AgentOutboundTeamContext.workspaceResultContract',
      'payload["agent_invocation"] as? [String: String] == AgentInvocationRequestJsonCodec.encode',
      'else if payload[AgentPinnedDesktopTeam.pinKey] != nil { return false }']],
    ['GalaxySSIMqttClient', ['applicationAuthorization: packet.applicationAuthorization', 'guard self.applicationAdmission == ticket',
      'if allowed, self.hasLiveTransport(), self.connectionGeneration == generation,', 'pending.pathGate.map({ self.authorizes($0) }) ?? true']],
    ['MqttDeliveryDispatch', ['applicationAuthorization: delivery.applicationAuthorization']],
    ['MqttPeerRoutes', ['authorized: authorized, applicationAuthorization: applicationAuthorization']],
    ['GalaxySSIServices+Outbox', ['await self?.pinnedDesktopOutboxAllowed(item) == true']]
  ]);
  let negatives = 0;
  for (const [name, checks] of tokens) {
    const file = app + name + '.swift', source = read(file);
    for (const token of checks) {
      assert(source.includes(token), token);
      assert.throws(() => retained(file, source.replace(token, 'REMOVED_ADMISSION_GATE')), assert.AssertionError, token); negatives++;
    }
  }
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const entries = source => source.split('\n').filter(line => line.includes('AgentPinnedDesktopOutboxTests.swift'));
  assert.equal(entries(read(projectFile)).length, 4);
  assert.deepEqual(entries(read(projectFile)), entries(show(approved, projectFile)));
  assert(services.includes('if desktopPin != nil {\n      scheduleOutboxFlush(after: 0)\n      return .queued'));
  console.log(`Pinned durable ownership, immutable archive, legacy scope, physical direct/hedged/fragment admission and ${negatives} negative source mutations checked. Seven outbox plus two dispatcher fixtures authored, not executed; no socket/race/device acceptance claimed.`);
}
