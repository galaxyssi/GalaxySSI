// Source contracts only. No Swift compilation, execution, transport or device acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '041b7c8481b5831355d56e527ece86bb0056c77a', approved = '43b1b20032c7dca4352ed1bd897c1f9a93b89b88';
const clean = s => s.replace(/\r\n/g, '\n'), memo = new Map();
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));
function git(args) { return clean(cp.execFileSync('git', args, {cwd: root, encoding: 'utf8', maxBuffer: 16_000_000})); }
function show(ref, file) {
  const key = ref + ':' + file;
  if (!memo.has(key)) memo.set(key, git(['show', key]));
  return memo.get(key);
}
function once(source, from, to) {
  assert(from.length > 0); assert.equal(source.split(from).length, 2, 'Exact unique pinned-team hunk retained');
  return source.replace(from, to);
}
// Reverse only exact application hunks, not an entire coordinator or arbitrary later changes.
function retained(file, source) {
  const scoped = path.join(__dirname, 'check-scoped-member-recall.cjs');
  if (fs.existsSync(scoped)) source = require(scoped).retained(file, source);
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
  flush(); assert(active, file);
  return source;
}
function retainedServices(source) {
  const scoped = path.join(__dirname, 'check-scoped-member-recall.cjs');
  if (fs.existsSync(scoped)) source = require(scoped).retainedServices(source);
  const outbox = path.join(__dirname, 'check-pinned-desktop-outbox.cjs');
  if (fs.existsSync(outbox)) source = require(outbox).retainedServices(source);
  if (!source.includes('    pinnedDesktopTeamTurn: String? = nil,')) return source;
  return retained(app + 'GalaxySSIServices.swift', source);
}
module.exports = {retainedServices, retained};
if (require.main === module) {
  const serviceFile = app + 'GalaxySSIServices.swift', services = read(serviceFile);
  let normalized = retainedServices(services);
  for (const [name, method] of [
    ['check-browser-view-ownership', 'retainedBrowserServices'],
    ['check-unplanned-native-dispatch', 'retainedUnplannedDispatchServices'],
    ['check-pairing-history', 'retainedPairingServices']
  ]) {
    const file = path.join(__dirname, name + '.cjs');
    if (fs.existsSync(file)) normalized = require(file)[method](normalized);
  }
  assert.equal(normalized, show(base, serviceFile), 'Non-pinned coordinator behavior retained with exact optional composition');
  for (const name of ['AgentConversationModels', 'AgentTeamPlanBridgeModels', 'GalaxySSIConversationalTeamView', 'GalaxySSIStoreSessions']) {
    const file = app + name + '.swift';
    assert.equal(retained(file, read(file)), show(base, file), name + ' changes confined to pinned-team integration');
  }
  const helperFile = app + 'AgentPinnedDesktopTeam.swift', viewFile = app + 'GalaxySSIPinnedDesktopTeamView.swift';
  const testsFile = 'apps/ios/GalaxySSITests/AgentPinnedDesktopTeamTests.swift';
  for (const file of [helperFile, viewFile, testsFile]) assert.equal(read(file), show(approved, file), file);
  const helper = read(helperFile), view = read(viewFile), tests = read(testsFile);
  for (const token of ['candidates.count == 1', 'contact.pinned_team_codex_v1 == true',
    '!blocked.contains(contact.id)', 'contact.identityFingerprint.caseInsensitiveCompare(link.desktopFingerprint) == .orderedSame',
    'target.invocationProfile.models.contains(where: { $0.id == selection.modelId })',
    'selection.reasoningEffort == .automatic || target.invocationProfile.reasoningEfforts.contains(selection.reasoningEffort)',
    'consumed = true', 'AgentTaskRequirementAnalyzer.analyze(objective).localOnly',
    'session.parentConversationId.isBlank', 'spec.definition.members.count == 2',
    'context.member.context[pinKey] == binding.route.digest', 'context.member.context[personKey] == context.member.memberId']) assert(helper.includes(token), token);
  assert(!/normalizedModelId|canonicalModelId|URLSession|\.publish\(|grantedPermissions|grantedConsents/.test(helper + view));
  assert(view.indexOf('review.claim(') < view.indexOf('store.createPinnedDesktopTeam('));
  assert(view.indexOf('store.createPinnedDesktopTeam(') < view.indexOf('    applied()'));
  assert(view.indexOf('    applied()') < view.indexOf('store.switchAgentSession('));
  assert(view.includes('requiredAgentConversationID: group.id, pinnedDesktopTeamTurn: turn'));
  let negatives = 0;
  for (const token of ['pin.turn == pinnedDesktopTeamTurn', 'pin.objective == trimmed',
    'AgentTeamDispatchIds.supervisorRunId(teamId: pin.teamID)) == nil,', 'turnId: pinnedDesktopTeamTurn ?? voiceSessionId',
    'roster?.pinnedDesktop == nil ? currentAgentScreenContext : AgentScreenContext(foregroundApp: "")',
    'if !isCollaboration, requestedMembers.count == 1', 'outgoing.turnId == pin.turn, outgoing.content == pin.objective',
    'AgentPinnedDesktopTeam.owns(spec, binding: pin, roster: roster)',
    'summary: desktopPin == nil ? recentLocalConversationContext(',
    'globalContext: desktopPin == nil ? GalaxySSIGlobalAgentRuntimeBridge.compiledConversationContext(',
    'includeGlobalContext: desktopPin == nil',
    'invocation == AgentInvocationRequestJsonCodec.encode(modelId: pin.route.model, reasoningEffort: pin.route.effort)',
    'guard control == .run else', 'AgentPinnedDesktopTeam.owns(teamContext, binding: pin, roster: roster)']) {
    assert(services.includes(token), token);
    assert.throws(() => retainedServices(services.replace(token, 'REMOVED_PIN_GATE')), assert.AssertionError); negatives++;
  }
  const compilerFile = app + 'AgentTeamPlanBridgeModels.swift', compiler = read(compilerFile);
  for (const token of ['pin.matches(roster), mentionedMemberIds.isEmpty, plan.goal == pin.objective',
    'roster.pinnedDesktop == nil ? count : 1', 'roster.pinnedDesktop?.teamID ??',
    'if action.parameters[AgentPinnedDesktopTeam.pinKey] != nil { return action }']) {
    assert(compiler.includes(token));
    assert.throws(() => retained(compilerFile, compiler.replace(token, 'REMOVED_PIN_GATE')), assert.AssertionError); negatives++;
  }
  assert.equal((tests.match(/func test/g) || []).length, 13);
  const projectFile = 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj';
  const entries = s => s.split('\n').filter(line => /(?:AgentPinnedDesktopTeam(?:Tests)?|GalaxySSIPinnedDesktopTeamView)\.swift/.test(line));
  assert.equal(entries(read(projectFile)).length, 12);
  assert.deepEqual(entries(read(projectFile)), entries(show(approved, projectFile)));
  assert(!/\p{Script=Han}/u.test(helper + view + tests));
  console.log(`Pinned Desktop entry, isolated group, exact graph/model/effort, stable retry, explicit run control and ${negatives} negative source mutations checked. Thirteen Swift fixtures authored, not executed; queued-revocation and live parity remain unverified.`);
}
