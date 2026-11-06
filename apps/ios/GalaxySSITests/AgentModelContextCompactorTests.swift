import Foundation
import XCTest
@testable import GalaxySSI

final class AgentModelContextCompactorTests: XCTestCase {
  func testHandoffPreservesInstructionsLiveHandlesAndReadOnlyRecoveryAcrossProviderChange() throws {
    let first = AgentModelToolCall(callId: "waiting", toolId: "phone.browser.wait")
    let mutation = AgentModelToolCall(callId: "uncertain", toolId: AgentEffectRecoveryRecord.browserMutationTools.sorted()[0])
    let latest = AgentModelToolCall(callId: "recent", toolId: "phone.search")
    let source: [AgentModelMessage] = [
      .system("System policy exactly."),
      .user("Original goal: keep the session."),
      AgentModelMessage(role: .assistant, text: "Tentative progress", toolCalls: [first, mutation],
                        providerRoute: "old-route"),
      .tool(AgentModelToolResultContent(callId: first.callId, toolId: first.toolId, status: "succeeded",
        output: ["control_owner": .string("user"), "handoff_id": .string("owned-handoff"),
                 "host_wait_key": .string("owned-wait"), "host_wait_generation": .int(4)])),
      .tool(AgentModelToolResultContent(callId: mutation.callId, toolId: mutation.toolId,
        status: "verification_failed", invocationId: "retained-operation")),
      .user("Additional constraint: never resubmit."),
      AgentModelMessage(role: .assistant, toolCalls: [latest], providerRoute: "old-route"),
      .tool(AgentModelToolResultContent(callId: latest.callId, toolId: latest.toolId, status: "succeeded",
        message: "Last batch result"))
    ]
    let budget = ConversationContextBudget(contextWindowTokens: 8_192, reservedOutputTokens: 512)
    let projection = try AgentModelContextHandoffProjection.prepare(source, budget: budget, route: "new-route")
    let checkpoint = try XCTUnwrap(projection.newHandoff)
    XCTAssertEqual(checkpoint.sourceCount, source.count)
    XCTAssertEqual(projection.messages.filter { $0.role == .user }.prefix(2).map(\.text),
                   ["Original goal: keep the session.", "Additional constraint: never resubmit."])
    XCTAssertEqual(projection.messages.first?.text, "System policy exactly.")
    XCTAssertFalse(projection.messages.contains { !$0.toolCalls.isEmpty || $0.toolResult != nil })
    XCTAssertTrue(projection.messages.last?.text.hasPrefix(AgentUntrustedEvidenceBoundary.textMarker) == true)
    for retained in ["owned-handoff", "owned-wait", "retained-operation",
                     AgentEffectRecoveryRecord.browserObserver, "Last batch result", "completion_verified"] {
      XCTAssertTrue(checkpoint.evidence.contains(retained), "Missing \(retained)")
    }
    let marker = AgentModelMessage(role: .assistant, text: "Continue.", contextHandoff: checkpoint,
                                   providerRoute: "new-route")
    let replay = try AgentModelContextHandoffProjection.prepare(source + [marker], budget: budget, route: "new-route")
    XCTAssertNil(replay.newHandoff)
    XCTAssertEqual(replay.messages.last?.text, "Continue.")
    var changed = source
    changed[1].text = "Different goal."
    XCTAssertThrowsError(try AgentModelContextHandoffProjection.prepare(changed + [marker], budget: budget, route: "new-route")) {
      XCTAssertEqual(($0 as? AgentModelLoopRecoveryError)?.code, "model_context_handoff_binding_changed")
    }
    XCTAssertThrowsError(try AgentModelContextHandoffProjection.prepare(
      Array(source.dropLast()), budget: budget, route: "new-route"
    )) {
      XCTAssertEqual(($0 as? AgentModelLoopRecoveryError)?.code, "model_context_waiting_for_tool_results")
    }
  }

  func testHandoffUnderBudgetPressureUsesAllProviderEncodersAndFailsOnOversizedRequiredReferences() throws {
    let budget = ConversationContextBudget(contextWindowTokens: 4_096, reservedOutputTokens: 1_024)
    let call = AgentModelToolCall(callId: "call_1", toolId: "phone.read")
    var source: [AgentModelMessage] = [
      .user("Read this information."),
      AgentModelMessage(role: .assistant, toolCalls: [call], providerRoute: "current"),
      .tool(AgentModelToolResultContent(callId: call.callId, toolId: call.toolId, status: "succeeded",
        output: ["raw_document": .string(String(repeating: "long content ", count: 2_000))],
        message: "Read the document."))
    ]
    let small = try AgentModelContextHandoffProjection.prepare(Array(source.prefix(1)), budget: budget, route: "current")
    XCTAssertNil(small.newHandoff)
    XCTAssertEqual(small.messages, Array(source.prefix(1)))
    let projection = try AgentModelContextHandoffProjection.prepare(source, budget: budget, route: "current")
    XCTAssertNotNil(projection.newHandoff)
    for provider in [AgentModelToolProvider.openAICompatible, .anthropic, .gemini] {
      let wire = try AgentModelToolProtocolAdapters.adapter(for: provider).encodeConversation(projection.messages)
      let text = AgentMcpJSONCodec.stringify(wire)
      XCTAssertTrue(text.contains("GALAXYSSI_UNTRUSTED_EVIDENCE"))
      XCTAssertTrue(text.contains("Read this information."))
      XCTAssertFalse(text.contains("raw_document"))
    }
    source[2].toolResult?.output["host_wait_key"] = .string(String(repeating: "must retain ", count: 2_000))
    XCTAssertThrowsError(try AgentModelContextHandoffProjection.prepare(source, budget: budget, route: "current")) {
      XCTAssertEqual(($0 as? AgentModelLoopRecoveryError)?.code, "model_context_required_evidence_too_large")
    }
  }

  func testAgentModelContextCompactorCompactsOldToolBlocksWithoutBreakingPairs() {
    var messages: [AgentModelMessage] = [
      .system("Use tools carefully."),
      .user("Inspect all files and report the result.")
    ]
    for index in 0..<8 {
      messages.append(.assistant(toolCalls: [
        AgentModelToolCall(
          callId: "call-\(index)",
          toolId: "galaxyssi.workspace.file.read",
          arguments: [
            "path": .string("/workspace/file-\(index).txt"),
            "content": .string(String(repeating: "argument ", count: 300))
          ]
        )
      ]))
      messages.append(.tool(AgentModelToolResultContent(
        callId: "call-\(index)",
        toolId: "galaxyssi.workspace.file.read",
        status: "success",
        output: ["content": .string(String(repeating: "tool output ", count: 1_000))],
        message: "Read file \(index)"
      )))
    }

    let result = AgentModelContextCompactor.compact(
      messages,
      budget: ConversationContextBudget(
        contextWindowTokens: 8_192,
        reservedOutputTokens: 2_048,
        triggerRatio: 0.40,
        targetRatio: 0.30
      )
    )

    XCTAssertTrue(result.compacted)
    XCTAssertLessThan(result.compactedEstimatedTokens, result.originalEstimatedTokens)
    XCTAssertLessThan(result.messages.count, messages.count)
    XCTAssertTrue(result.messages.contains {
      $0.role == .system && $0.text.contains("[EARLIER TOOL ACTIVITY - REFERENCE ONLY]")
    })
    let retainedCallIds = Set(result.messages.flatMap(\.toolCalls).map(\.callId))
    let retainedResultIds = Set(result.messages.compactMap(\.toolResult).map(\.callId))
    XCTAssertFalse(retainedCallIds.isEmpty)
    XCTAssertEqual(retainedCallIds, retainedResultIds)
    XCTAssertEqual(result.messages.last, messages.last)
  }

  func testAgentModelContextCompactorKeepsUnresolvedToolCalls() {
    let unresolved = AgentModelMessage.assistant(toolCalls: [
      AgentModelToolCall(callId: "pending", toolId: "galaxyssi.workspace.file.read")
    ])
    let messages = [
      AgentModelMessage.system(String(repeating: "system ", count: 1_000)),
      AgentModelMessage.user("Start"),
      AgentModelMessage.assistant("Older " + String(repeating: "content ", count: 1_000)),
      unresolved
    ]

    let result = AgentModelContextCompactor.compact(
      messages,
      budget: ConversationContextBudget(
        contextWindowTokens: 4_096,
        reservedOutputTokens: 1_024,
        triggerRatio: 0.25,
        targetRatio: 0.20,
        minimumRecentGroups: 1,
        maximumSummaryTokens: 256
      )
    )

    XCTAssertTrue(result.compacted)
    XCTAssertTrue(result.messages.contains(unresolved))
  }

  func testAgentModelContextCompactorModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentModelMessage.self,
      from: Data(
        #"""
        {
          "role": "ASSISTANT",
          "text": "Checking.",
          "tool_calls": [
            {
              "call_id": "call-1",
              "tool_id": "galaxyssi.workspace.file.read",
              "arguments": {"path": "README.md"}
            }
          ]
        }
        """#.utf8
      )
    )
    let budget = try JSONDecoder().decode(
      ConversationContextBudget.self,
      from: Data(
        #"""
        {
          "context_window_tokens": 8192,
          "reserved_output_tokens": 2048,
          "trigger_ratio": 0.5,
          "target_ratio": 0.3,
          "minimum_recent_groups": 2,
          "maximum_summary_tokens": 512,
          "maximum_message_characters": 2000
        }
        """#.utf8
      )
    )
    let encoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)

    XCTAssertEqual(decoded.role, .assistant)
    XCTAssertEqual(decoded.toolCalls.singleValue().callId, "call-1")
    XCTAssertEqual(decoded.toolCalls.singleValue().arguments["path"], .string("README.md"))
    XCTAssertEqual(budget.inputBudgetTokens, 6_144)
    XCTAssertTrue(encoded.contains(#""tool_calls":["#))
    XCTAssertTrue(encoded.contains(#""tool_id":"galaxyssi.workspace.file.read""#))
  }
}

private extension Array {
  func singleValue(file: StaticString = #filePath, line: UInt = #line) -> Element {
    XCTAssertEqual(count, 1, file: file, line: line)
    return self[0]
  }
}
