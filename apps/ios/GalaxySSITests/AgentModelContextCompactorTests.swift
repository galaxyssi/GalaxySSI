import Foundation
import XCTest
@testable import GalaxySSI

final class AgentModelContextCompactorTests: XCTestCase {
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
