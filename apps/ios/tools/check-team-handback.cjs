// Source contracts only; these assertions do not compile or execute Swift.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n');
const engine = read('GalaxySSI/AgentConversationalTeamEngine.swift');
for (const token of ['if reviewed.requiresHandback', 'guard calls + 2 <= Contract.maximumCalls',
  'onEvent(.rewriting); try reserveCall()', '"brief": plan.synthesis, "reports": ordered.map(\\.json)',
  '"draft": draft, "objection": objection', 'input("rewrite", objective: objective, fields: rewriteFields)',
  'AgentTeamDraftAudit.replacement(rawRewrite, rejected: draft)', 'onEvent(.rechecking(index, plan.roles.count)); try reserveCall()',
  'auditFields["draft"] = candidate; auditFields["rejected_draft"] = draft; auditFields["objection"] = objection',
  'input("recheck", objective: objective, fields: auditFields), limit: 1_300', 'AgentTeamDraftAudit.recheck(rawRecheck)',
  'answer = candidate', 'catch is CancellationError { throw CancellationError() }',
  'catch AgentTeamDraftAudit.Failure.withheld(let reason) { throw withhold(reason) }',
  'catch { throw withhold(objection) }', 'issue: .withheld(reason), objections: objections', 'roleCount: plan.roles.count']) assert(engine.includes(token), token);
assert(engine.indexOf('guard calls + 2') < engine.indexOf('onEvent(.rewriting)'), 'Fund both turns before rewrite');
assert(engine.indexOf('AgentTeamDraftAudit.recheck(rawRecheck)') < engine.indexOf('answer = candidate'), 'Publish only rechecked replacement');
assert.equal(engine.split('input("rewrite",').length - 1, 1, 'One rewrite site');
assert.equal(engine.split('input("recheck",').length - 1, 1, 'One recheck site');
const audit = read('GalaxySSI/AgentTeamDraftAudit.swift');
for (const token of ['requiresHandback: returnToWriter || sameDraft(answer, draft)', '[\\s\\p{Z}\\u0085]+',
  'AgentTeamPlanJSONPreflight(json, limits: .audit)', 'try preflight.validate()', 'raw.utf16.count <= 17_300',
  'Set(value.keys) == ["answer"]', '!sameDraft(answer, rejected)', 'keys == ["verdict"]',
  'keys == ["verdict", "objection"]', 'guard !isReviewPlaceholder(reason) else { throw Failure.invalid }', 'throw Failure.withheld(reason)',
  'Do not accept a paraphrase that leaves the error intact', 'Do not invent evidence']) assert(audit.includes(token), token);
const preflight = read('GalaxySSI/AgentTeamPlanJSONPreflight.swift');
assert(preflight.includes('Limits(depth: 4, nodes: 64, entries: 32, string: 8_000)'));
assert(preflight.includes('Limits(depth: 5, nodes: 100, entries: 10, string: 400)'));
const recheck = audit.slice(audit.indexOf('static func recheck'), audit.indexOf('static func parse'));
assert(!recheck.includes('revise'), 'No recursive correction verdict');
const name = 'AgentTeamHandbackTests';
const tests = read(`GalaxySSITests/${name}.swift`);
assert.equal((tests.match(/func test/g) || []).length, 16);
assert.equal(read('GalaxySSI.xcodeproj/project.pbxproj').split(name + '.swift in Sources').length - 1, 2);
for (const token of ['workers: 7', 'for workers in [8, 9]', '\\u0076erdict', '\\u0061nswer',
  'stage + "-cancel"', 'result.calls, 7', 'result.roleCount, 3', 'recheck[key], audit[key]',
  'rejected.objections.count', 'events.contains(.rechecking(3, 3))']) assert(tests.includes(token), token);
const strings = read('GalaxySSI/zh-Hans.lproj/Localizable.strings');
for (const key of ['rewriting', 'rechecking']) {
  assert.equal(strings.split(`"galaxyssi.conversation_team.${key}" =`).length - 1, 1);
  assert(read('GalaxySSI/GalaxySSIConversationalTeamView.swift').includes(`t("${key}",`));
}
for (const file of ['GalaxySSI/AgentTeamDraftAudit.swift', 'GalaxySSI/AgentConversationalTeamEngine.swift', `GalaxySSITests/${name}.swift`]) {
  assert(!/\p{Script=Han}/u.test(read(file))); assert(Buffer.byteLength(read(file)) < 32_768);
}
console.log('Bounded writer handback and independent recheck source contracts passed; 16 native test methods authored, not executed.');
