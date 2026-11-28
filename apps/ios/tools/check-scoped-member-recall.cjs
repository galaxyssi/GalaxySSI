// Source contracts only. No Swift/ICU, Signal, database, thread confinement or device execution.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = 'c6bad3465c673dfb2dcecb23b095185c129c7447', approved = 'dff8f994d56fb4741229a31abc535031cac467c2';
const clean = s => s.replace(/\r\n/g, '\n'), read = f => clean(fs.readFileSync(path.join(root, f), 'utf8')), memo = new Map();
function git(args) { return clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})); }
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, git(['show', key]));
  return memo.get(key);
}
function once(source, from, to = '') {
  assert(from.length > 0); assert.equal(source.split(from).length, 2, 'Exact unique scoped recall delta: ' + from.slice(0, 180));
  return source.replace(from, to);
}
function retainedExact(file, source) {
  const patch = git(['diff', '--no-ext-diff', '--no-color', '--unified=0', base, approved, '--', file]);
  let old = [], current = [], active = false;
  function flush() {
    if (active) source = once(source, '\n' + current.join('\n') + '\n', '\n' + (old.length ? old.join('\n') + '\n' : ''));
    old = []; current = [];
  }
  for (const line of patch.split('\n')) {
    if (line.startsWith('@@ ')) { flush(); active = true; continue; }
    if (!active || !line) continue;
    if (line.startsWith('-')) old.push(line.slice(1));
    else if (line.startsWith('+')) current.push(line.slice(1));
    else assert(line.startsWith('\\ No newline'), 'Unexpected zero-context diff format');
  }
  flush(); assert(active, file); return source;
}
function retainedProjection(source) {
  source = once(source, '    var originalRecallOffer: AgentScopedMemberRecall.Offer? = nil\n');
  source = once(source, '      if payload[AgentScopedMemberRecall.flag] != nil {\n' +
    '        guard let originalRecallOffer, originalRecallOffer.matches(payload) else { return false }\n      }\n' +
    '      if originalRecallOffer != nil && team == nil { return false }\n');
  source = once(source, '      return ((originalRecallOffer != nil && AgentScopedMemberRecall.trueFlag(payload[AgentScopedMemberRecall.flag])) ||\n' +
    '        payload["agent_team_message"] as? Bool == true) &&', '      return payload["agent_team_message"] as? Bool == true &&');
  return once(source, '  var receiveScopedMemberRecall: (([String: Any], MqttPeerChatProjection.Destination) async throws -> Void)? = nil\n');
}
const markers = {
  GalaxySSIServices: '  private var scopedMemberAuthorizationReplay',
  AgentTeamExecutionHistoryStore: 'replacement.originalRecallOffer == member.originalRecallOffer',
  AgentTeamExecutionModels: 'var originalRecallOffer: AgentScopedMemberRecall.Offer?',
  AgentTeamPlanBridgeModels: 'var originalRecallOffer: AgentScopedMemberRecall.Offer?',
  MqttDesktopConnectorProjection: 'var originalRecallOffer: AgentScopedMemberRecall.Offer?',
  MqttBusinessTransportRuntime: '  func publishScopedMemberRecallResult(',
  GalaxySSISignalEngine: '  func makeScopedMemberRecallResultWire('
};
function retained(file, source) {
  const name = path.basename(file, '.swift');
  if (!markers[name] || !source.includes(markers[name])) return source;
  if (name === 'MqttDesktopConnectorProjection') return retainedProjection(source);
  const combined = name === 'GalaxySSIServices' && source.includes('originalRecallOffer: context.member.originalRecallOffer, pinnedDesktop: context.team.pinnedDesktop)');
  if (combined) source = once(source, 'originalRecallOffer: context.member.originalRecallOffer, pinnedDesktop: context.team.pinnedDesktop)',
    'originalRecallOffer: context.member.originalRecallOffer)');
  source = retainedExact(file, source);
  if (combined) source = once(source, '        (!context.member.status.isTerminal || context.member.status == .interrupted))',
    '        (!context.member.status.isTerminal || context.member.status == .interrupted), pinnedDesktop: context.team.pinnedDesktop)');
  return source;
}
const retainedServices = source => retained(app + 'GalaxySSIServices.swift', source);
module.exports = {retainedServices, retained};
function optional(name, method, file, source) {
  const location = path.join(__dirname, name + '.cjs');
  if (!fs.existsSync(location)) return source;
  const guard = require(location);
  assert.equal(typeof guard[method], 'function', name + ' must expose exact composition');
  return method === 'retained' ? guard[method](file, source) : guard[method](source);
}
function canonical(file, source) {
  if (file.endsWith('/GalaxySSIServices.swift')) {
    for (const [name, method] of [['check-pinned-desktop-team', 'retainedServices'],
      ['check-browser-view-ownership', 'retainedBrowserServices'], ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
      ['check-pairing-history', 'retainedPairingServices']]) source = optional(name, method, file, source);
  } else if (file.endsWith('/AgentTeamPlanBridgeModels.swift') && source.includes('AgentPinnedDesktopTeam.pinKey')) {
    source = optional('check-pinned-desktop-team', 'retained', file, source);
  } else if (/\/(?:MqttDesktopConnectorProjection|AgentTeamExecutionHistoryStore|AgentTeamExecutionModels)\.swift$/.test(file) && source.includes('pinnedDesktop')) {
    source = optional('check-pinned-desktop-outbox', 'retained', file, source);
  }
  return source;
}
if (require.main === module) {
  for (const name of Object.keys(markers)) {
    const file = app + name + '.swift';
    assert.equal(canonical(file, retained(file, read(file))), show(base, file), file + ' outside exact declared ownership');
  }
  const policyFile = app + 'AgentScopedMemberRecall.swift', policy = read(policyFile);
  const testsFile = 'apps/ios/GalaxySSITests/AgentScopedMemberRecallTests.swift', tests = read(testsFile);
  assert.equal(policy, show(approved, policyFile)); assert.equal(tests, show(approved, testsFile));
  assert.equal((tests.match(/  func test/g) || []).length, 16);
  const services = read(app + 'GalaxySSIServices.swift');
  const authorization = services.slice(services.indexOf('    if request.phase == "authorize" {'), services.indexOf('    guard let initial = scopedMemberRecallProbe(request, link: link)'));
  assert(authorization.includes('AgentScopedMemberRecall.authorize(request, replay: &replay'));
  assert(!/recallCollaborationOriginal|handleDesktopNativeEvidenceRecall|handleDesktopCollaborationExchange|\.execute\(|\.generate\(/.test(authorization), 'No data/effect callback in preflight');
  for (const token of ['requested == (observed ?? 1)', 'requested > 1, observed == requested - 1',
    'CFGetTypeID(number) == CFBooleanGetTypeID()', 'textFields.allSatisfy({ payload[$0] is String })',
    'arguments.isEmpty, Set(payload.keys).isSubset(of: fields)', 'entry.waiting == waiting',
    'guard entries.count < 128', 'first.offer == last.offer', 'probe() == last',
    'waiting ? "generation_not_ready" : "authorized"']) assert(policy.includes(token), token);
  assert(!/URLSession|FileManager|\.execute\(|\.generate\(|grantedPermissions|grantedConsents|normalizedModelId/.test(policy));
  const gates = new Map([
    ['GalaxySSIServices', ['followupContext == nil, executionMode == .autoComplete',
      'scopedMemberAuthorizationReplay = replay', 'offer.scope.sourceId == request.source',
      'offer.transportBinding == GalaxySSITransportReceiptJournal.binding',
      'person.id == offer.personID, person.resourceId == offer.contact, person.modelId == offer.model',
      'context.owner.closedRecallGeneration != request.generation', 'requireResearchAccess: true),\n      let offer = context.member.originalRecallOffer',
      'guard (try? managedBrowserContinuations.control(scope: run)) == .run',
      'scopedMemberRecallProbe(request, link: link) == initial', 'memberBoundAssignment.merging([',
      'memberAdmission.map({ scopedMemberRecallIsCurrent($0, payload: payload, link: link) }) ?? current.owner.permitsRecall',
      'if let memberAdmission, !scopedMemberRecallIsCurrent(memberAdmission, payload: payload, link: link)',
      'originalRecallOffer: savedTeam.members.first(where:', '_ = offer.encode(&payload)',
      '_ = try? managedBrowserContinuations.writeControl(.run, scope: scope)']],
    ['AgentTeamExecutionHistoryStore', ['replacement.originalRecallOffer == member.originalRecallOffer']],
    ['AgentTeamExecutionModels', ['originalRecallOffer = try container.decodeIfPresent(AgentScopedMemberRecall.Offer.self']],
    ['MqttDesktopConnectorProjection', ['guard let originalRecallOffer, originalRecallOffer.matches(payload)',
      'if originalRecallOffer != nil && team == nil { return false }']],
    ['MqttBusinessTransportRuntime', ['guard target.desktop, let receive = desktopConnector?.receiveScopedMemberRecall',
      'payload.string("client_route_id") == target.routeId else { return false }', 'guard valid(), !stopped else { return false }']],
    ['GalaxySSISignalEngine', ['AgentScopedMemberRecall.acceptsResponse(try request.applicationPayload()) else',
      'request.attachmentTransferID.isEmpty, request.sourceMessageID.isEmpty']]
  ]);
  let negatives = 0;
  for (const [name, tokens] of gates) for (const token of tokens) {
    const file = app + name + '.swift', source = read(file); assert(source.includes(token), token);
    assert.throws(() => assert.equal(canonical(file, retained(file, source.replace(token, 'REMOVED_SCOPED_RECALL_GATE'))),
      show(base, file)), assert.AssertionError, token); negatives++;
  }
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const entries = source => source.split('\n').filter(line => /AgentScopedMemberRecall(?:Tests)?\.swift/.test(line));
  assert.equal(entries(read(projectFile)).length, 8);
  assert.deepEqual(entries(read(projectFile)), entries(show(approved, projectFile)));
  assert(!/\p{Script=Han}/u.test(policy + tests));
  console.log(`Original-member offer, content-free preflight, generation/nonce pinning, read/confirm revalidation, both Signal routes and ${negatives} negative source mutations checked. Sixteen Swift fixtures authored, not executed; no native/private-data/model/device acceptance claimed.`);
}
