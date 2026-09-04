import Foundation
@testable import GalaxySSI

struct AgentIOSPr2639ScenarioOutcome: Equatable {
  var group: String
  var index: Int
  var passed: Bool
  var detail: String
}

struct AgentIOSPr2639PersistenceReport: Equatable {
  var deletedConversations: Int
  var visibleConversations: Int
  var visibleMessages: Int
  var passed: Int
  var failed: Int
}

enum AgentIOSPr2639RecorderError: Error, Equatable {
  case invalidOutcomeCount(Int)
  case duplicateScenario
  case conversationWriteFailed
  case messageWriteFailed
  case verificationFailed
}

final class AgentIOSPr2639CognitionMatrixRecorder {
  static let conversationPrefix = "ios-pr2639-matrix-"
  static let expectedCount = 1_000

  private let conversations: AgentConversationDatabase
  private let messages: GalaxySSIChatHistoryDatabase

  init(conversations: AgentConversationDatabase, messages: GalaxySSIChatHistoryDatabase) {
    self.conversations = conversations
    self.messages = messages
  }

  func replace(_ outcomes: [AgentIOSPr2639ScenarioOutcome]) throws -> AgentIOSPr2639PersistenceReport {
    guard outcomes.count == Self.expectedCount else {
      throw AgentIOSPr2639RecorderError.invalidOutcomeCount(outcomes.count)
    }
    let scenarioKeys = outcomes.map { "\($0.group):\($0.index)" }
    guard Set(scenarioKeys).count == outcomes.count else {
      throw AgentIOSPr2639RecorderError.duplicateScenario
    }

    let oldIDs = Set(conversations.readAll().map(\.id).filter { $0.hasPrefix(Self.conversationPrefix) })
    let deleted = conversations.delete(oldIDs)
    _ = messages.deleteConversations(oldIDs)

    let records = outcomes.enumerated().map { makeConversation(ordinal: $0.offset + 1, outcome: $0.element) }
    let transcript = outcomes.enumerated().flatMap { makeMessages(ordinal: $0.offset + 1, outcome: $0.element) }
    guard conversations.upsertAll(records) else { throw AgentIOSPr2639RecorderError.conversationWriteFailed }
    guard messages.upsertAll(transcript) else { throw AgentIOSPr2639RecorderError.messageWriteFailed }

    let persisted = conversations.readAll().filter { $0.id.hasPrefix(Self.conversationPrefix) }
    let persistedMessages = messages.messages(contactId: "hermes")
      .filter { $0.conversationId.hasPrefix(Self.conversationPrefix) }
    guard persisted.count == Self.expectedCount,
          persisted.allSatisfy({ $0.privateMode && $0.trackingPaused && $0.status == .active }),
          persistedMessages.count == Self.expectedCount * 2,
          Set(persistedMessages.map(\.conversationId)).count == Self.expectedCount else {
      throw AgentIOSPr2639RecorderError.verificationFailed
    }

    return AgentIOSPr2639PersistenceReport(
      deletedConversations: deleted,
      visibleConversations: persisted.count,
      visibleMessages: persistedMessages.count,
      passed: outcomes.filter(\.passed).count,
      failed: outcomes.filter { !$0.passed }.count
    )
  }

  private func makeConversation(
    ordinal: Int,
    outcome: AgentIOSPr2639ScenarioOutcome
  ) -> AgentConversation {
    let timestamp = 1_760_000_000_000 + Int64(ordinal)
    return AgentConversation(
      id: conversationID(ordinal),
      title: String(format: "iOS cognition %04d - %@", ordinal, outcome.group),
      createdAt: timestamp,
      updatedAt: timestamp + 1,
      selectedModelOrAgent: "iOS cognition architecture",
      contextPolicy: "isolated-regression",
      summary: outcome.passed ? "PASS" : "FAIL",
      privateMode: true,
      trackingPaused: true
    )
  }

  private func makeMessages(
    ordinal: Int,
    outcome: AgentIOSPr2639ScenarioOutcome
  ) -> [ChatMessage] {
    let conversationID = conversationID(ordinal)
    let timestamp = Date(timeIntervalSince1970: 1_760_000_000 + Double(ordinal) / 1_000)
    let turnID = "pr2639-turn-\(ordinal)"
    return [
      ChatMessage(
        id: messageID(ordinal: ordinal, result: false),
        contactId: "hermes",
        content: "group=\(outcome.group) | scenario=\(outcome.index)",
        isMine: true,
        createdAt: timestamp,
        conversationId: conversationID,
        turnId: turnID
      ),
      ChatMessage(
        id: messageID(ordinal: ordinal, result: true),
        contactId: "hermes",
        content: [outcome.passed ? "PASS" : "FAIL", outcome.detail]
          .filter { !$0.isEmpty }
          .joined(separator: " | "),
        isMine: false,
        createdAt: timestamp.addingTimeInterval(0.001),
        conversationId: conversationID,
        turnId: turnID
      )
    ]
  }

  private func conversationID(_ ordinal: Int) -> String {
    Self.conversationPrefix + String(format: "%04d", ordinal)
  }

  private func messageID(ordinal: Int, result: Bool) -> UUID {
    let suffix = ordinal * 2 + (result ? 1 : 0)
    return UUID(uuidString: String(format: "26390000-0000-4000-8000-%012d", suffix))!
  }
}

enum AgentIOSPr2639CognitionMatrix {
  static let groups: [(name: String, count: Int)] = [
    ("foreground_core_memory", 100),
    ("foreground_prompt_compiler", 100),
    ("background_scheduler_and_ingestion", 80),
    ("background_memory_evolution", 160),
    ("background_graph_memory", 120),
    ("background_knowledge_index", 100),
    ("background_skills", 100),
    ("background_knowledge_gap_and_research", 80),
    ("proactive_cognition_loop", 80),
    ("background_memory_critic", 40),
    ("obsidian_knowledge_projection", 40)
  ]

  static func outcomes(detail: String) -> [AgentIOSPr2639ScenarioOutcome] {
    groups.flatMap { group in
      (0..<group.count).map {
        AgentIOSPr2639ScenarioOutcome(group: group.name, index: $0, passed: true, detail: detail)
      }
    }
  }
}
