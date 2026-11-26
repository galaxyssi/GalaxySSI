// Source wiring only; not Swift compilation, executed fixtures or runtime acceptance.
const assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const root = path.resolve(__dirname, '../../..'), app = 'apps/ios/GalaxySSI/';
const base = '64e33aa934a5a4a6b89516533834070a6242e576', cache = new Map();
const read = file => require('./check-scored-route-context-scope.cjs').retained(file,
  fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n'));
function old(file) {
  if (!cache.has(file)) cache.set(file, cp.execFileSync('git', ['show', `${base}:${file}`],
    {cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024}).replace(/\r\n/g, '\n'));
  return cache.get(file);
}
function section(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert(a >= 0 && b > a, start); return source.slice(a, b);
}
function replacement(original, indent) {
  const i = ' '.repeat(indent), j = i + '  ';
  const setup = `${i}let plannerSnapshot = task.plannerSnapshot\n${j}?? capturePlannerSnapshot(conversationId: outgoing.conversationId)\n`;
  const conversation = `${i}let conversation = initialPlanningConversation(\n${j}requestText: task.goal, outgoing: outgoing,\n${j}selectedProviderOnly: plannerSnapshot?.selectedForPhoneTurn == true\n${i})\n`;
  assert(original.startsWith(setup + conversation));
  const validation = original.slice((setup + conversation).length);
  const catchStart = `${j}} catch {\n`, a = validation.indexOf(catchStart);
  assert(a > 0);
  const catchBody = validation.slice(a + catchStart.length, validation.lastIndexOf(`${j}}\n`))
    .split('\n').map(line => line.startsWith('  ') ? line.slice(2) : line).join('\n');
  return `${i}let plannerSnapshot: AgentPlannerModelSnapshot?\n${i}do {\n` +
    `${j}plannerSnapshot = try resumedNativePlannerSnapshot(task: task, outgoing: outgoing)\n` +
    `${j}if let plannerSnapshot {\n${j}  _ = try planner(for: plannerSnapshot)\n${j}}\n${i}} catch {\n` +
    catchBody + `${i}}\n` + conversation;
}
function retained(file, source) {
  source = require('./check-scored-route-context-scope.cjs').retained(file, source);
  if (file.endsWith('GalaxySSI.xcodeproj/project.pbxproj')) return source.split('\n')
    .filter(line => !line.includes('AgentResumedPlannerRouteTests.swift')).join('\n');
  if (file.endsWith('check-supervised-answer-preview-scope.cjs')) return source
    .replace("const read = file => require('./check-resumed-planner-route-scope.cjs').retained(file,\n  fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n'));",
      "const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\\r\\n/g, '\\n');")
    .replace("  source = require('./check-resumed-planner-route-scope.cjs').retained(file, source);\n", '');
  if (file.endsWith('GalaxySSIServices.swift') && source.includes('  func resumedNativePlannerSnapshot(')) {
    source = source.replace(section(source, '  func resumedNativePlannerSnapshot(', '  private func shortcutReviewPlanner('), '');
    for (const [indent, end] of [[6, 'let input = AgentInitialPlanningInput('], [4, 'let planningInput = AgentInitialPlanningInput(']]) {
      const i = ' '.repeat(indent), original = section(old(file), '\n' + i + 'let plannerSnapshot = task.plannerSnapshot\n', i + end).slice(1);
      const expected = replacement(original, indent);
      assert(source.includes(expected), `Exact resumed planning integration at indent ${indent}`);
      source = source.replace(expected, original);
    }
  }
  return source;
}
function validate() {
  for (const file of [app + 'GalaxySSIServices.swift', 'apps/ios/GalaxySSI.xcodeproj/project.pbxproj',
    'apps/ios/tools/check-supervised-answer-preview-scope.cjs']) assert.equal(retained(file, read(file)), old(file), file);
  const service = read(app + 'GalaxySSIServices.swift');
  const helper = section(service, '  func resumedNativePlannerSnapshot(', '  private func shortcutReviewPlanner(');
  for (const token of ['outgoing.isMine', '!outgoing.isSystem', 'outgoing.contactId == "hermes"',
    'task.sessionId == outgoing.conversationId', 'task.taskId == outgoing.turnId.ifBlank(outgoing.id.uuidString)',
    'if let snapshot = task.plannerSnapshot { return snapshot }', 'shortcutReviewPlanner(task: task, outgoing: outgoing)',
    'resumed_planner_scope_changed', 'resumed_planner_route_unavailable']) assert(helper.includes(token), token);
  assert(!helper.includes('capturePlannerSnapshot') && !helper.includes('recordAgentAutoRouteDispatch'));
  assert(helper.indexOf('task.plannerSnapshot') < helper.indexOf('shortcutReviewPlanner'));
  assert.equal((service.match(/plannerSnapshot = try resumedNativePlannerSnapshot\(task: task, outgoing: outgoing\)/g) || []).length, 2);
  assert.equal(section(service, '  private func shortcutReviewPlanner(', '  private func continueObservedNativeOutcomeReview('),
    section(old(app + 'GalaxySSIServices.swift'), '  private func shortcutReviewPlanner(', '  private func continueObservedNativeOutcomeReview('));
  for (const name of ['AgentPlannerModelSnapshot', 'AgentModelPlannerContactResolver', 'AgentInitialPlanningJournal',
    'AgentConnectorTimeoutResolver', 'AgentActionEffectExecutor', 'AgentNetworkRoutingModels', 'GalaxySSIStoreSessions',
    'AgentTaskRequirementAnalyzer', 'MqttBusinessTransportRuntime', 'AgentDataDisclosureLedger'])
    assert.equal(read(app + name + '.swift'), old(app + name + '.swift'), name);
  const tests = read('apps/ios/GalaxySSITests/AgentResumedPlannerRouteTests.swift');
  assert(helper.includes('|| task.taskId == outgoing.id.uuidString'));
  assert.equal((tests.match(/  func test/g) || []).length, 8);
  assert.equal(read('apps/ios/GalaxySSI.xcodeproj/project.pbxproj').split('\n')
    .filter(line => line.includes('AgentResumedPlannerRouteTests.swift')).length, 4);
  console.log('Resumed planner call sites, exact saved snapshots, scoped selection and retained result/transport source contracts passed; no native acceptance.');
}
module.exports = {retained, validate};
if (require.main === module) validate();
