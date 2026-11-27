// Source contracts only. No Swift execution, transport run or device certification.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const offer = read('GalaxySSI/AgentPinnedCloudTeamOffer.swift');
for (const token of ['answer_with_optional_team_review', 'request.provider == .openAICompatible',
  'body["tool_choice"] as? String == "auto"', 'payload.singleNativeFunction && payload.index == 0',
  'payload.callId == id', 'calls.count == 1', 'finish == "tool_calls"', '!hasText',
  'call.argumentsJson.utf8.count <= 64_000', 'Set(object.keys) == ["answer", "propose_team_review"]',
  'object["propose_team_review"] == .bool(true)', 'answer.utf16.count <= 8_000',
  '!CloudSupervisedResearch.isControlPayload(answer)', '!CloudWebGrounding.containsInternalToolProtocol(answer)']) assert(offer.includes(token), token);
const adapter = read('GalaxySSI/CloudModelStreamProviderAdapters.swift');
for (const token of ['root.array("choices").count == 1, calls.count == 1', 'CFGetTypeID(value) != CFBooleanGetTypeID()',
  'call["type"] as? String == "function"', 'function["arguments"] is String', 'singleNativeFunction: Self.singleFunction']) assert(adapter.includes(token), token);
const protocol = read('GalaxySSI/CloudModelStreaming.swift');
assert(protocol.includes('singleNativeFunction: Bool = false'));
assert(protocol.includes('decodeIfPresent(Bool.self, forKey: .singleNativeFunction) ?? false'));
const admission = read('GalaxySSI/AgentPinnedCloudTeamAdmission.swift');
for (const token of ['@TaskLocal static var runtime: UUID?', 'budget.profile != .privateMode && budget == AgentTaskBudget(profile: budget.profile)',
  'selection.mode == .manual', '!selection.modelId.isBlank', 'model.apiStyle == .openAICompatible', 'url.user == nil, url.password == nil',
  'route == selectedRoute', 'AgentConversationGoalInference.isCurrent', 'AgentPinnedCloudTeamDelivery.runtime == runtime',
  'AgentLocalTeamReviewWindow.ownsCloud', '!Task.isCancelled', 'model.modelId == route.model',
  'fingerprint(contact: contact, model: model) == route.endpointSHA']) assert(admission.includes(token), token);
const window = read('GalaxySSI/AgentLocalTeamReviewProposal.swift');
for (const token of ['candidate.selection.targetId == route.target, candidate.selection.modelId == route.model',
  'window.cloudRuntime != runtime', 'window.cloudRuntime == runtime', '!requirements.liveDataRequired, !requirements.localOnly',
  'window.answerSHA == AgentBlobProtocol.sha256(Data(message.content.utf8))', 'message.deliveryStatus == .delivered',
  'let stored = store.persistedMessage(id: message.id, contactId: message.contactId)',
  'stored.turnId == candidate.source.turn', 'stored.richOutputJson.isBlank', 'candidate.pin == nil']) assert(window.includes(token), token);
const planner = read('GalaxySSI/CloudModelAgentPlanningProvider.swift');
for (const token of ['guard request.permitsAnswerOnlyResponse, !request.hasAttachments', 'objective: request.planRequest.goal',
  'round == 0, !final', 'AgentPinnedCloudTeamOffer.advertise(roundRequest)', 'reviewFrames.observe(value.payload)',
  'reviewFrames.reject()', 'guard advertised, round == 0', 'await review.accept(answer, store: reviewStore)',
  '"disposition": .string("respond"), "final_response": .string(answer)']) assert(planner.includes(token), token);
assert(planner.indexOf('AgentPinnedCloudTeamOffer.answer(calls') < planner.indexOf('callCount + calls.count <= 12'), 'Consume terminal format before any research tool dispatch');
const engine = read('GalaxySSI/CloudConversationStreamEngine.swift');
for (const token of ['trial == nil, researchRetrySource == nil, evidenceResults.isEmpty',
  'if currentRound == 0, let review', 'reviewAdvertised = offered.bodyJson != roundRequest.bodyJson',
  'guard reviewAdvertised, currentRound == 0', 'await review.accept(answer, store: store)',
  'if inlineCalls.contains(where: { $0.name == AgentPinnedCloudTeamOffer.name })']) assert(engine.includes(token), token);
assert(engine.indexOf('AgentPinnedCloudTeamOffer.answer(structuredCalls') < engine.indexOf('let inlineCalls ='), 'Native answer is not interpreted as an inline tool');
const services = read('GalaxySSI/GalaxySSIServices.swift');
assert.equal((services.match(/AgentPinnedCloudTeamDelivery\.\$runtime\.withValue\(UUID\(\)\)/g) || []).length, 2);
assert(services.includes('cloudDelivered(directIncoming, store: store)') && services.includes('cloudDelivered(final, store: store)'));
const directStart = services.indexOf('private func completeModelDirectResponse(');
const direct = services.slice(directStart, services.indexOf('private func completePlanOnlyTask(', directStart));
assert(direct.indexOf('guard task.phase == .completed') < direct.indexOf('cloudDelivered(directIncoming'), 'No invitation before accepted phone completion');
assert(direct.includes('let directIncoming = store.appendIncoming('), 'Use the actual accepted assistant row');
const ui = read('GalaxySSI/GalaxySSIConversationalTeamView.swift');
assert(ui.includes('if let pin = launch.pin') && ui.includes('current(pin, store: store, conversation: launch.conversation) ? [pin] : []'));
assert(ui.includes('next.pinnedCloud = launch.pin == nil ? nil : true'));
const worker = read('GalaxySSI/AgentConversationalTeamRuntime.swift');
assert(worker.includes('actual.pinnedCloud == original.pinnedCloud'));
assert(worker.includes('original.pinnedCloud != true || AgentPinnedCloudTeamAdmission.current(original.route'));
assert(read('GalaxySSI/AgentConversationalTeamStore.swift').includes('job.pinnedCloud == expected.pinnedCloud'));
const project = read('GalaxySSI.xcodeproj/project.pbxproj');
for (const name of ['AgentPinnedCloudTeamOffer', 'AgentPinnedCloudTeamAdmission', 'AgentPinnedCloudTeamOfferTests']) {
  const source = read(`${name.endsWith('Tests') ? 'GalaxySSITests' : 'GalaxySSI'}/${name}.swift`);
  assert(!/\p{Script=Han}/u.test(source)); assert(Buffer.byteLength(source) < 32_768);
  assert.equal(project.split(name + '.swift in Sources').length - 1, 2);
}
assert.equal((read('GalaxySSITests/AgentPinnedCloudTeamOfferTests.swift').match(/func test/g) || []).length, 13);
console.log('Pinned cloud native invitation, fresh delivery and route source contracts passed; 13 native test methods authored, not executed.');
