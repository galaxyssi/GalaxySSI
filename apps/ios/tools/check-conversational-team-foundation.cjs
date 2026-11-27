// Source contracts only. This does not execute Swift or validate live concurrency/background scheduling.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const read = file => fs.readFileSync(path.join(root, 'apps/ios', file), 'utf8').replace(/\r\n/g, '\n');
const contract = read('GalaxySSI/AgentConversationalTeamProtocol.swift');
const engine = read('GalaxySSI/AgentConversationalTeamEngine.swift');
for (const token of ['maximumRoles = 10', 'maximumParallel = 3', 'maximumCalls = 12',
  'Set(parents).count == parents.count', 'parents.allSatisfy(roleID)', 'ids.count == roles.count',
  'role.parents.allSatisfy(ids.contains)', '!role.parents.contains(role.id)',
  'roles.filter { $0.parents.contains(role.id) }.count <= 3',
  'AgentSkillManifestValidator.topologicalSteps', 'fields.count == 5', 'tail.count == 2',
  'rows.count == 3', 'rows[2] == "END"', 'raw.utf16.count <= 6_000',
  '(1...2_000).contains(finding.utf16.count)', '(1...600).contains(dissent.utf16.count)',
  'body.utf16.count <= 8_000', 'Return public results, not reasoning traces', 'No tools, external actions or private records']) assert(contract.includes(token), token);
for (const token of ['calls < Contract.maximumCalls', 'running.count == Contract.maximumParallel',
  'role.parents.allSatisfy({ reports[$0] != nil })', 'role.parents.map { parent',
  'withThrowingTaskGroup(of: Contract.Report.self)', 'let report = try await group.next()',
  'defer { group.cancelAll() }', 'Task.checkCancellation()', '120_000_000_000',
  'let ordered = try plan.roles.map', 'ordered.map(\\.json)', 'report.dissent.map',
  'onEvent(.interrupted)', 'onEvent(.stopped)']) assert(engine.includes(token), token);
assert(!/GalaxySSIHealthRecords|MessageCoordinator|enqueueDesktop|AgentNativeToolRegistry|URLSession|AgentSkillRuntime/.test(engine + contract),
  'Core orchestration must not acquire a provider, tool, health, desktop or Skill execution authority');
const event = engine.slice(engine.indexOf('  enum Event:'), engine.indexOf('  struct Outcome:'));
assert(!/String|objective|assignment|finding/.test(event), 'Progress must contain only bounded metadata');
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentConversationalTeamProtocol', 'AgentConversationalTeamEngine', 'AgentConversationalTeamCommand',
  'AgentConversationalTeamJob', 'AgentConversationalTeamStore', 'AgentConversationalTeamJobTests', 'AgentConversationalTeamStoreTests',
  'AgentConversationalTeamRuntime', 'AgentConversationalTeamBackground', 'AgentConversationalTeamLifecycle', 'GalaxySSIConversationalTeamView',
  'AgentConversationalTeamProtocolTests', 'AgentConversationalTeamEngineTests', 'AgentConversationalTeamCommandTests']) {
  const file = `${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`;
  const source = read(file);
  assert(!/\p{Script=Han}/u.test(source), name + ' localized resource placement');
  assert(Buffer.byteLength(source) < 32_768, name + ' scoped file size');
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2, name + ' registration');
}
assert.equal((read('GalaxySSITests/AgentConversationalTeamProtocolTests.swift').match(/func test/g) || []).length, 13);
assert.equal((read('GalaxySSITests/AgentConversationalTeamEngineTests.swift').match(/func test/g) || []).length, 7);
assert.equal((read('GalaxySSITests/AgentConversationalTeamCommandTests.swift').match(/func test/g) || []).length, 8);
const command = read('GalaxySSI/AgentConversationalTeamCommand.swift');
for (const token of ['case start(String), stop, help, tooLong, privateObjective', 'text.hasPrefix("/")',
  'text.prefix(5).lowercased() == "/team"', 'quoted.stringByReplacingMatches', 'NSRange(prefix.startIndex..., in: prefix)',
  'matches(visible, key: "negative"', '!matches(value, key: "meta"', 'requested ? makeStart(text) : nil',
  'objective.utf16.count <= 4_000', 'key: "health"', 'language: LanguagePolicySettings.zhCN']) assert(command.includes(token), token);
const strings = read('GalaxySSI/zh-Hans.lproj/Localizable.strings');
const keys = new Set();
for (const match of strings.matchAll(/^"galaxyssi\.conversation_team\.([^"\n]+)" = ("(?:[^"\\]|\\.)*");$/gm)) {
  assert(!keys.has(match[1]), 'Duplicate team resource: ' + match[1]); keys.add(match[1]);
  const value = JSON.parse(match[2]);
  if (match[1].startsWith('pattern_')) new RegExp(value, 'i');
}
for (const key of ['help_alias', 'stop_alias', 'pattern_stop', 'pattern_negative', 'pattern_meta', 'pattern_request', 'pattern_with_team', 'pattern_health']) {
  assert(keys.has(key), 'Localized command rule: ' + key);
}
const job = read('GalaxySSI/AgentConversationalTeamJob.swift');
const store = read('GalaxySSI/AgentConversationalTeamStore.swift');
for (const token of ['case queued, running, finished, stopped', 'state == .queued', 'state == .running',
  'calls < AgentConversationalTeamProtocol.maximumCalls', 'value.calls += 1', 'answer.utf16.count <= 64_000']) assert(job.includes(token), token);
for (const token of ['NSRecursiveLock()', 'AgentTurnReceiptEvidence.hash(owner)', 'AgentTurnReceiptEvidence.hash(conversation)',
  'try read(job.conversation) == expected', 'job.objective == expected.objective, job.route == expected.route',
  'job.revision == expected.revision + 1', 'guard !expected.active, job.state == .queued',
  'GalaxySSIEncryptedUserDefaultsStore.load', 'GalaxySSIEncryptedUserDefaultsStore.write', '".deleted"']) assert(store.includes(token), token);
const wire = read('GalaxySSI/AgentConversationGoalInference.swift');
assert(wire.includes('prompt: String? = nil') && wire.includes('system: system, prompt: prompt'), 'Exact shared text payload path');
assert.equal((read('GalaxySSITests/AgentConversationalTeamJobTests.swift').match(/func test/g) || []).length, 5);
assert.equal((read('GalaxySSITests/AgentConversationalTeamStoreTests.swift').match(/func test/g) || []).length, 6);
const runtime = read('GalaxySSI/AgentConversationalTeamRuntime.swift');
for (const token of ['private weak var store:', 'ticket = UUID(); work?.cancel()', 'guard self.graceToken == token',
  'guard grant == value', 'GalaxySSIStore.canRestoreConversationGoalState()', 'Task.isCancelled',
  'actual.id == original.id && actual.state == .running', 'actual.objective == original.objective && actual.route == original.route',
  'let next = try previous.reserveCall()', 'repository(store).replace(next, expected: previous)',
  'requestID: "conversation-team-\\(original.id)-\\(next.calls)"', 'AgentConversationGoalInference.text',
  'if initial.state == .running', 'initial.finish(text("interrupted"', 'let running = try initial.begin()',
  'try repository.replace(running, expected: initial)', 'AgentConversationalTeamEngine.run',
  'try repository.replace(finished, expected: actual)', 'store.persistTransportIncoming', 'try repository(store).retire(job)']) assert(runtime.includes(token), token);
assert(runtime.indexOf('initial.finish(text("interrupted"') < runtime.indexOf('AgentConversationalTeamEngine.run'), 'Uncertain recovery before dispatch');
assert(runtime.indexOf('try repository.replace(running, expected: initial)') < runtime.indexOf('AgentConversationalTeamEngine.run'), 'Durable claim before dispatch');
assert(runtime.indexOf('store.persistTransportIncoming') < runtime.indexOf('try repository(store).retire(job)'), 'Durable publication before retirement');
assert(!/localizedDescription|print\(|NSLog\(|error\.description/.test(runtime), 'No raw provider failure logging');
const ui = read('GalaxySSI/GalaxySSIConversationalTeamView.swift');
for (const token of ['valid() && scene == .active', 'launch.selection == AgentModelSelectionSettings.selection',
  'guard launch.selection.mode == .manual', '$0.target == target', '$0.model == launch.selection.modelId',
  'choices.indices.contains(selected)', 'routes().contains(route)', 'GalaxySSIHealthAgentLab.intent',
  'try repository.replace(next, expected: nil)', 'AgentConversationalTeamRuntime.shared.publish(actual',
  'launch.revision == teamDraftRevision', 'AgentMentionText.parse(text, targets: targets).requestedMembers.isEmpty']) assert(ui.includes(token), token);
const home = read('GalaxySSI/GalaxySSIAndroidParityUI.swift');
assert(home.includes('if storedDraft != newValue { teamDraftRevision = UUID(); conversationalTeamLaunch = nil; modelTeamReview.invalidate() }'), 'Every draft edit invalidates consent');
assert(home.includes('draft: Binding(get: { draft }, set: { draft = $0 })'), 'Composer edits use the revision-tracked setter');
assert(home.includes('.onChange(of: attachments.map(\\.id)) { _ in conversationalTeamLaunch = nil; modelTeamReview.invalidate() }'), 'Extras invalidate consent');
const submit = read('GalaxySSI/GalaxySSIAgentHomeMessageSubmission.swift');
assert(submit.indexOf('if offerConversationalTeam(') < submit.indexOf('if offerConversationGoal('), 'Local command intercept precedes ordinary dispatch');
const app = read('GalaxySSI/GalaxySSIViews.swift');
assert(app.includes('AgentConversationalTeamBackground.register()') && app.includes('AgentConversationalTeamLifecycle(store: runtime.store)'), 'App lifecycle hookup');
const background = read('GalaxySSI/AgentConversationalTeamBackground.swift');
assert(background.includes('expected: epoch') && background.includes('generation != expected') && background.includes('expireBackground(grant)'), 'Generation-bound background expiration');
assert(read('GalaxySSI/BackgroundModes.plist').includes('<string>com.galaxyssi.chat.ios.conversation-team</string>'), 'Typed BG permission');
assert(read('GalaxySSI/GalaxySSIStoreSessions.swift').includes('AgentConversationalTeamStore(owner: profile.identityFingerprint, defaults: defaults, secrets: secrets).remove(id)'), 'Conversation deletion');
const hostStore = read('GalaxySSI/GalaxySSIStore.swift');
assert(hostStore.includes('AgentConversationalTeamStore.destroyAll') && hostStore.includes('sourceTrace != AgentConversationalTeamRuntime.stage'), 'Reset and memory isolation');
for (const key of ['title', 'help', 'objective', 'model', 'no_provider', 'consent', 'background', 'authorize', 'stop', 'close',
  'changed', 'unavailable', 'refused', 'queued', 'calls', 'receipt', 'disagreements', 'interrupted', 'failed', 'stopped',
  'state_queued', 'state_running', 'state_finished', 'state_stopped']) assert(keys.has(key), key);
console.log('Conversational team protocol, command, consent, persistence, worker and lifecycle source contracts passed; native test sources not executed.');
