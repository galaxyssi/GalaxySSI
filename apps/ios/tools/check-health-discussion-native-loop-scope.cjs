'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../../..');
const prefix = 'apps/ios/GalaxySSI/';
const baseline = '9714b722e92967dcd6ee29907d5cc786e2cdaef6';
const clean = text => text.replace(/\r\n/g, '\n');
const read = file => clean(fs.readFileSync(path.join(root, file), 'utf8'));

function retainedNativeRouting(input) {
  let source = clean(input);
  const hook = `    if review.research == nil, try records.savedCareDiscussionRound(review) != nil {
      return try await GalaxySSIHealthCareModelToolLoop.finish(review, records: records, request: request,
        style: style, ledger: ledger, currentDestination: currentDestination, send: send)
    }
`;
  assert.equal(source.split(hook).length - 1, 1, 'Unique manual-discussion native loop routing hook');
  source = source.replace(hook, '');
  const signature = 'currentDestination: @escaping () -> GalaxySSIContact?, send: @escaping (URLRequest) async throws -> Data';
  assert.equal(source.split(signature).length - 1, 2, 'Explicit callback ownership for both entry points');
  return source.replaceAll(signature, 'currentDestination: () -> GalaxySSIContact?, send: (URLRequest) async throws -> Data');
}
module.exports = { retainedNativeRouting };

if (require.main === module) {
  const old = name => clean(cp.execFileSync('git', ['show', `${baseline}:${prefix}${name}`], { cwd: root, encoding: 'utf8' }));
  for (const name of ['AgentModelToolLoop.swift', 'AgentNativeToolExecutionModels.swift', 'AgentNativeToolCore.swift',
    'AgentModelToolProtocolGeminiAdapter.swift', 'AgentModelToolProtocolModels.swift', 'GalaxySSIServices.swift']) {
    const current = name === 'GalaxySSIServices.swift'
      ? require('./check-health-composer-scope.cjs').retainedHealthComposerGuard(read(prefix + name)) : read(prefix + name);
    assert.equal(current, old(name), `${name}: reuse unchanged core outside declared Health submission guard`);
  }
  const research = old('GalaxySSIHealthCareResearchLifecycle.swift');
  const before = '            route(authorization, owner: records.owner)?.0';
  assert.equal(research.split(before).length - 1, 1);
  assert.equal(read(prefix + 'GalaxySSIHealthCareResearchLifecycle.swift'), research.replace(before, before.replace('route(', 'self.route(')));
  const model = read(prefix + 'GalaxySSIHealthCareModelToolLoop.swift');
  assert.match(model, /AgentModelToolLoop\(modelAdapter: adapter, toolRegistry: registry\)\.run\(loopRequest\)/);
  assert.match(model, /observationHistoryEnabled: false/);
  assert.match(model, /eventSink: \.none, collaborationOwner: nil/);
  assert.match(model, /grantedPermissions: \[\]/);
  assert.match(model, /maxRetriesPerCall: 0/);
  assert.match(model, /maxDepth: 1/);
  assert.match(model, /maxRounds: 16 - saved\.index/);
  assert.match(model, /approval\.reviewedAt\.addingTimeInterval\(GalaxySSIHealthCareDiscussion\.approvalLifetime\)/);
  assert.match(model, /messages: \[\.user\(approval\.question\)\]/);
  assert.match(model, /outcome\.status == \.completed/);
  assert.match(model, /session\.pending == nil/);
  assert.match(model, /session\.catalog\.contains\(where: \{ \$0\.id == call\.toolId \}\)/);
  assert.match(model, /arguments == call\.arguments/);
  assert.match(model, /state\.request\(using: session\.template, approval: session\.approval\)/);
  assert.match(model, /dispatchCareDiscussionRound[\s\S]*?bytes = try await send\(wire\)/);
  assert.match(model, /status: received \? \.sent : \.failed/);
  assert.doesNotMatch(model, /CloudModelAgentPlanningProvider|CloudWebGroundingToolExecutor|AgentPhoneNativeToolCatalog|globalRealtimeContext|currentAgentScreenContext|voiceCorrectionJournal/);
  const tools = read(prefix + 'GalaxySSIHealthCareNativeToolSession.swift');
  assert.match(tools, /InMemoryAgentNativeToolReplayStore\(\)/);
  assert.match(tools, /InMemoryAgentNativeToolAuditStore\(\)/);
  assert.match(tools, /allowed\.contains\(name\), ids\.insert\(name\)\.inserted/);
  assert.match(tools, /invocation\.context\.turnId == approval\.id\.uuidString/);
  assert.match(tools, /invocation\.context\.callerId == Self\.caller, invocation\.context\.collaborationOwner == nil/);
  assert.match(tools, /invocation\.context\.attributes\["workspace_id"\] == workspaceID/);
  assert.match(tools, /records\.validateLocalCareDiscussionTurn\(approval\)/);
  assert.match(tools, /records\.prepareNextCareDiscussionRound\(approval, expected: saved, next: next\)/);
  assert.match(tools, /records\.retainLocalCareDiscussionResponse[\s\S]*?records\.saveLocalCarePlan/);
  assert.doesNotMatch(tools, /URLSession|allHTTPHeaderFields|FileAgentWorkspaceStore|UserDefaults|defaultRuntime\(/);
  const view = read(prefix + 'GalaxySSIHealthCareDiscussionView.swift');
  assert.match(view, /let bytes = try await GalaxySSIHealthCareModelToolLoop\.finish\(review/);
  assert.doesNotMatch(view, /responseBytes\(|beginCloudRequest\(/);
  assert.match(view, /careDiscussionExecution\(review\)\.state == \.applied/);
  assert.equal((read('apps/ios/GalaxySSITests/GalaxySSIHealthCareModelToolLoopTests.swift').match(/func test/g) || []).length, 10);
  console.log('Health native model-loop source scope passed (not native execution or typechecking).');
}
