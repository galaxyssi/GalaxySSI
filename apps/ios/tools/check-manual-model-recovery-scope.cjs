// Pinned source/packaging contracts, not Swift execution or paired-device acceptance.
const fs = require("node:fs"), path = require("node:path"), cp = require("node:child_process");
const assert = require("node:assert/strict"), crypto = require("node:crypto");
const root = path.resolve(__dirname, "../../.."), sha = "bf8bb0b2a00930e707c333631dab86124eca0efc";
const base = "18af490a3bc260e0fcaae3b8c5a32f5d44e435ed";
const git = args => cp.execFileSync("git", args, {cwd: root, maxBuffer: 16_000_000});
const read = file => fs.readFileSync(path.join(root, file), "utf8").replace(/\r\n/g, "\n");
const swift = name => "apps/ios/GalaxySSI/" + name + ".swift";
const source = name => read(swift(name));
const prior = name => git(["show", base + ":" + swift(name)]).toString();
const changed = git(["diff", "--name-status", "--no-renames", sha + "^1", sha]).toString().trim().split(/\r?\n/).map(l => l.split("\t"));
assert.equal(changed.length, 8);
const inventory = {schema: 1, source: {androidPR: 4438, mergeCommit: sha}, files: changed.map(([status, file]) => ({path: file, status,
  sha256: crypto.createHash("sha256").update(git(["show", sha + ":" + file])).digest("hex")}))};
const android = name => git(["show", sha + ":apps/android/app/src/main/java/com/galaxyssi/chat/" + name + ".kt"]).toString();
assert(android("AgentConnectorFallbackAction").includes('action?.parameters?.get("manual_target_locked") == "true" ||'));
assert(android("MobileNativeAgentExecution").includes("if (AgentConnectorFallbackAction.isTargetLocked(action, failedResult.metadata)) return null"));
assert(!android("MobileNativeAgentCodexRecovery").includes('parameters - "manual_target_locked"'));
assert(android("MobileNativeAgent").includes("recoveryExhausted && safeReplay && !manuallyLocked"));
const network = source("AgentNetworkRoutingModels"), timeout = source("AgentConnectorTimeoutResolver");
const provider = source("AgentControlPlaneActionExecutorModels"), ledger = source("AgentDesktopReplyRecovery");
const service = source("GalaxySSIServices"), policy = source("AgentManualModelRecoveryPolicy");
const lockHelper = '  static func isTargetLocked(action: AgentAction?, metadata: [String: String]) -> Bool {\n    action?.parameters["manual_target_locked"] == "true" || metadata["manual_target_locked"] == "true"\n  }\n';
assert(network.includes(lockHelper));
const checkedNetwork = network.includes("enum AgentAutomaticConnectorRoutePolicy {")
  ? require("./check-stable-auto-admission-scope.cjs").normalizedNetwork : network;
assert.equal(checkedNetwork.replace(lockHelper, "").replace('    guard !isTargetLocked(action: action, metadata: [:]) else { return action }\n', ""), prior("AgentNetworkRoutingModels"));
const pin = '    if AgentConnectorFallbackAction.isTargetLocked(action: item.action, metadata: result.metadata) {\n      result.metadata["manual_target_locked"] = "true"\n    }\n    if let language = item.action.parameters["response_language"], !language.isBlank {\n      result.metadata["response_language"] = language\n    }\n';
const checkedProvider = provider.replace('    var result = AgentConnectorFallbackAction.mergingRoutingMetadata(\n      delegate.execute(action: item.action, screen: item.screen), action: item.action)',
  '    var result = delegate.execute(action: item.action, screen: item.screen)');
assert(provider.includes(pin)); assert.equal(checkedProvider.replace(pin, ""), prior("AgentControlPlaneActionExecutorModels"));
assert(provider.indexOf(pin) < provider.indexOf('    let awaitingResponse = result.metadata["awaiting_response"]'));
const expectedTimeout = prior("AgentConnectorTimeoutResolver")
  .replace('    let message = "\\(targetName) timed out"', '    let manuallyLocked = AgentConnectorFallbackAction.isTargetLocked(action: nil, metadata: pending.metadata)\n    let message = manuallyLocked\n      ? AgentManualModelRecoveryPolicy.timeoutMessage(language: pending.metadata["response_language"] ?? LanguagePolicySettings.auto)\n      : "\\(targetName) timed out"')
  .replace('    metadata["timeout_elapsed_ms"] = String(elapsedMillis)\n', '    metadata["timeout_elapsed_ms"] = String(elapsedMillis)\n    if manuallyLocked {\n      metadata["allow_unavailable_target_fallback"] = "false"\n      metadata["non_retriable"] = "true"\n    }\n');
assert.equal(timeout, expectedTimeout, "Auto timeout gates/timing and metadata remain unchanged; only locked outcome differs");
for (const token of ["var manualTargetLocked: Bool? = nil", "manualTargetLocked == true || codexReplay?.lockedToOrigin == true",
  'binding.displayContactId != "hermes"', "guard !old.isManualTargetLocked, !replay.lockedToOrigin",
  "manualTargetLocked: old.manualTargetLocked", "manualTargetLocked: Bool = false", "manualTargetLocked: manualTargetLocked"])
  assert(ledger.includes(token), token);
const replay = service.split("  private func scheduleCodexReplay(")[1].split("  private func dispatchScheduledCodexReplay(")[0];
assert(replay.indexOf("guard !record.isManualTargetLocked") < replay.indexOf("replay.budget.next("));
for (const token of ["replay.matches(source)", "session.status == .active", "!session.privateMode, !session.trackingPaused", "session.collaborationRoster == nil",
  "binding.desktopId", "confirmedTimeout: timeout", "alternatives: alternatives", "desktopReplyRecovery.scheduleCodexReplay(from: record"])
  assert(replay.includes(token), token);
const dispatch = service.split("  private func dispatchScheduledCodexReplay(")[1].split("  private func finishUndispatchedCodexReplay(")[0];
for (const token of ["guard !record.isManualTargetLocked", "desktopReplyRecovery.record(for: binding) == record", "replay.matches(source)",
  "!GalaxySSITransportPrivacyPolicy.isLocalOnly(binding.fields)", "target.connectorInvocationProfile.models.contains", "guard ticket.allowed",
  "executionMode: .planOnly, codexReplay: record", "finishUndispatchedCodexReplay(binding)"]) assert(dispatch.includes(token), token);
const publish = service.split("    if let codexReplay {")[1].split('    var payload:')[0];
assert(publish.includes("guard !codexReplay.isManualTargetLocked"));
assert(service.includes("manualTargetLocked: locked)"));
const stopped = service.split("  private func finishUndispatchedCodexReplay(")[1].split("  private func manualDesktopTimeoutFeedback(")[0];
for (const token of ["if manuallyLocked {", 'task.verification = "manual_desktop_timeout"', "task.phase = .failed; task.result = detail",
  '![AgentPhase.completed, .cancelled, .failed].contains(task.phase)', "store.appendSystem(detail, to: source.contactId", "release(sourceMessageId: binding.sourceIdentity)"])
  assert(stopped.includes(token), token);
const fallback = service.split("  private func connectorFallbackAction(")[1].split("  private func markLocalNativeActionBlocked(")[0];
assert(fallback.indexOf("guard !AgentConnectorFallbackAction.isTargetLocked(action: action, metadata: failedResult.metadata)") < fallback.indexOf("AgentCallableTargetCatalog.build("));
assert(!fallback.includes('removeValue(forKey: "manual_target_locked")'));
assert(service.includes('reason == "desktop_status_unavailable" && record.isManualTargetLocked'));
assert(policy.includes("record.isManualTargetLocked, record.binding.matches(payload)"));
assert(policy.includes('normalize(payload.string("task_status")) == "timed_out"'));
assert(policy.includes("AgentCodexSilenceRecoveryPolicy.confirmedTimeout("));
assert(service.includes("manualDesktopTimeoutFeedback(appPayload, desktopId:"));
assert(service.includes("let content = manualTimeout ?? (AgentRemoteOutcomePolicy.isFailure(remoteTaskStatus)"));
assert(service.includes("manualTimeout.map { AgentRichContentCodec.encode(AgentRichContentCodec.fromText($0)) }"));
assert(service.includes("if let manualTimeout { richOutputJson = AgentRichContentCodec.encode(AgentRichContentCodec.fromText(manualTimeout)) }"));
// Presentation changes must not edit authenticated packet bytes or receipt identity.
const added = git(["diff", "--unified=0", base, "--", swift("GalaxySSIServices")]).toString().split(/\r?\n/).filter(l => l.startsWith("+") && !l.startsWith("+++"));
assert(!added.some(l => /appPayload\[|payload\[/.test(l)), "Do not rewrite wire payloads to localize a failure");
for (const name of ["AgentDesktopResultRecovery", "AgentConnectorTransportReceiptRecorder", "AgentConnectorTerminalStatusResolver"])
  assert.equal(source(name), prior(name), "Auto budget, confirmed timeout recognition and receipt/authentication gates stay intact: " + name);
let remotePolicy = source("AgentRemoteTaskStatusPolicy");
if (remotePolicy.includes("  static func rankedAlternatives(")) {
  const start = remotePolicy.indexOf("  static func rankedAlternatives("), end = remotePolicy.indexOf("  static func isCodex(", start);
  assert(start >= 0 && end > start);
  remotePolicy = remotePolicy.slice(0, start) + remotePolicy.slice(end);
}
assert.equal(remotePolicy, prior("AgentRemoteTaskStatusPolicy"), "Only #3119 current ranking helper; existing replay budget and timeout recognition unchanged");
const tests = read("apps/ios/GalaxySSITests/AgentRoutingCapabilityTests.swift") + read("apps/ios/GalaxySSITests/AgentConnectorTimeoutResolverTests.swift") + read("apps/ios/GalaxySSITests/AgentRunPolicyTests.swift");
for (const token of ["testManualModelLockCannotBeClearedByFallbackMetadataOrActionPreparation", "testManualTimeoutStopsWithoutGrantingUnavailableTargetFallback",
  "testActionExecutorPinsManualLockBeforeTransportTimeout", "testManualCodexRecoveryCannotBeQueuedEvenWhenTheCallerStripsItsSeedLock",
  "testManualNonCodexLockPersistsAndDoesNotChangeTerminalWirePayloads", "for locked in [true, false]", 'legacy.removeValue(forKey: "manualTargetLocked")',
  "XCTAssertTrue(restoredLegacy.isManualTargetLocked)", "XCTAssertEqual(reopened.pending, [old])", 'for language in ["en", "zh-Hans"]',
  "options: .sortedKeys", "lockedToOrigin: false"]) assert(tests.includes(token), token);
const autoTests = read("apps/ios/GalaxySSITests/AgentConnectorResponseTests.swift");
let originalAutoTests = autoTests;
if (originalAutoTests.includes("  func testCodexRecoveryRanksOnlyCurrentlyEligibleDesktopAgents(")) {
  const start = originalAutoTests.indexOf("  func testCodexRecoveryRanksOnlyCurrentlyEligibleDesktopAgents("),
    end = originalAutoTests.indexOf("  func testLargeResearchReplyKeepsOriginalBytesThroughBothResponseStores(", start);
  assert(start >= 0 && end > start);
  originalAutoTests = originalAutoTests.slice(0, start) + originalAutoTests.slice(end);
}
assert.equal(originalAutoTests, git(["show", base + ":apps/ios/GalaxySSITests/AgentConnectorResponseTests.swift"]).toString());
assert(autoTests.includes("testCodexSilenceBudgetRetriesTwoInitialAttemptsThenAlternativesAndOneFinalAttempt"));
const pbx = read("apps/ios/GalaxySSI.xcodeproj/project.pbxproj");
for (const token of ["AgentManualModelRecoveryPolicy.swift in Sources", "AgentManualModelRecovery.strings in Resources"]) assert(pbx.includes(token));
const mapping = {
  "AgentConnectorFallbackAction.kt": ["AgentNetworkRoutingModels"],
  "MobileNativeAgent.kt": ["AgentConnectorTimeoutResolver", "AgentControlPlaneActionExecutorModels", "AgentManualModelRecoveryPolicy", "AgentDesktopReplyRecovery", "GalaxySSIServices"],
  "MobileNativeAgentCodexRecovery.kt": ["AgentDesktopReplyRecovery", "GalaxySSIServices"],
  "MobileNativeAgentExecution.kt": ["AgentNetworkRoutingModels", "GalaxySSIServices"]
};
const files = inventory.files.map(file => {
  const name = path.basename(file.path); let kind, ios, note;
  if (mapping[name]) {
    kind = "native-manual-target-preservation"; ios = mapping[name].map(swift);
    note = "Action-or-result locks block generic fallback before candidate selection. Preserve locked action inputs in prepare, pin locks/language in provider results and explicit per-request recovery records. Legacy locked Codex seeds and explicit direct contacts remain locked. Reject automatic Codex replay at scheduling, durable queue insertion, restored dispatch and final publish; do not mutate Auto budget. Localize actual manual timeouts/expiry without rewriting authenticated packet or receipt bytes. Status/result queries remain passive and existing trust/session/identity/privacy/capability gates remain in place.";
  } else if (file.path.includes("/androidTest/")) {
    kind = "android-device-reference-not-executed"; ios = ["apps/ios/GalaxySSITests/AgentRoutingCapabilityTests.swift", "apps/ios/GalaxySSITests/AgentConnectorTimeoutResolverTests.swift", "apps/ios/GalaxySSITests/AgentRunPolicyTests.swift", "apps/ios/GalaxySSITests/AgentConnectorResponseTests.swift"];
    note = "Original one-dispatch manual versus bounded Auto fallback/recovery references mapped to Swift fixture sources for lock precedence, action/result pinning, unchanged manual inputs, false fallback flag, legacy/reopened durable queue rejection including stripped seed locks, bilingual scoped feedback and unchanged packets. Existing Auto budget/receipt replay fixtures retained, with the positive retry claim explicitly Auto. No XCTest, Android device, paired Desktop or dispatch-count execution performed.";
  } else if (file.path.includes("/res/")) {
    kind = "exact-bilingual-timeout-label"; ios = ["apps/ios/GalaxySSI/en.lproj/AgentManualModelRecovery.strings", "apps/ios/GalaxySSI/zh-Hans.lproj/AgentManualModelRecovery.strings", swift("AgentManualModelRecoveryPolicy"), "apps/ios/tools/import-manual-model-recovery-text.cjs", "apps/ios/GalaxySSI.xcodeproj/project.pbxproj"];
    note = "One exact English/Chinese label pair from values and values-zh-rCN original XML; localized standalone native table registered in Xcode and fallback string checked against the original English.";
  } else {
    assert.equal(name, "build.gradle.kts"); kind = "android-version-only"; ios = []; note = "No iOS version bump, Android/Desktop changes, build or IPA.";
  }
  for (const target of ios) assert(fs.existsSync(path.join(root, target)), target);
  return {source: file.path, sourceSHA256: file.sha256, kind, ios, note};
});
for (const [suffix, data] of [["SOURCE_INVENTORY", inventory], ["PORT_COVERAGE", {schema: 1, source: inventory.source, verification: "source-contracts-only-not-native-execution", files}]]) {
  const file = "apps/ios/ANDROID_4438_" + suffix + ".json", content = JSON.stringify(data, null, 2) + "\n";
  if (process.argv.includes("--write")) fs.writeFileSync(path.join(root, file), content); else assert.equal(read(file), content);
}
if (process.argv.includes("--checks")) for (const command of ["import-manual-model-recovery-text.cjs --check", "check-atlas-research-navigation-scope.cjs --checks"])
  cp.execFileSync(process.execPath, [path.join(__dirname, command.split(" ")[0]), ...command.split(" ").slice(1)], {cwd: root, stdio: "inherit"});
console.log("Android #4438: eight original hashes/dispositions, lock precedence/durable replay gates/unchanged Auto budget/wire-preserving feedback source contracts. No Swift, XCTest or paired-device execution.");
