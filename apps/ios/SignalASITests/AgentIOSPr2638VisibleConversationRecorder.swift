import Foundation
@testable import SignalASI

struct AgentIOSPr2638ExecutionResult: Equatable {
  var testCase: AgentIOSPr2627To2633Case
  var passed: Bool
  var durationMillis: Int64
  var detail: String
}

struct AgentIOSPr2638PersistenceSummary: Equatable {
  var conversationsBefore: Int
  var conversationsAfter: Int
  var persistedCount: Int
  var passedCount: Int
  var failedCount: Int
}

enum AgentIOSPr2638PersistenceError: Error, Equatable {
  case incompleteCorpus(Int)
  case duplicateConversationID
  case transcriptWriteFailed
  case conversationWriteFailed
  case verificationFailed(String)
}

final class AgentIOSPr2638VisibleConversationRecorder {
  static let expectedCount = 1_000

  private let conversations: AgentConversationDatabase
  private let transcripts: AgentTranscriptEntryStore

  init(
    conversations: AgentConversationDatabase,
    transcripts: AgentTranscriptEntryStore
  ) {
    self.conversations = conversations
    self.transcripts = transcripts
  }

  func persist(
    _ results: [AgentIOSPr2638ExecutionResult]
  ) throws -> AgentIOSPr2638PersistenceSummary {
    guard results.count == Self.expectedCount else {
      throw AgentIOSPr2638PersistenceError.incompleteCorpus(results.count)
    }
    let conversationIDs = results.map(\.testCase.conversationID)
    guard Set(conversationIDs).count == results.count else {
      throw AgentIOSPr2638PersistenceError.duplicateConversationID
    }

    let conversationIDSet = Set(conversationIDs)
    let before = conversations.readAll().filter { conversationIDSet.contains($0.id) }.count
    let records = results.map(makeConversation)
    let entries = results.flatMap(makeEntries)
    guard transcripts.replaceBatch(entries) else {
      throw AgentIOSPr2638PersistenceError.transcriptWriteFailed
    }
    guard conversations.upsertAll(records) else {
      throw AgentIOSPr2638PersistenceError.conversationWriteFailed
    }
    try verify(results)

    return AgentIOSPr2638PersistenceSummary(
      conversationsBefore: before,
      conversationsAfter: results.count,
      persistedCount: results.count,
      passedCount: results.filter(\.passed).count,
      failedCount: results.filter { !$0.passed }.count
    )
  }

  private func makeConversation(_ result: AgentIOSPr2638ExecutionResult) -> AgentConversation {
    let testCase = result.testCase
    let timestamp = 1_750_000_000_000 + Int64(testCase.ordinal)
    return AgentConversation(
      id: testCase.conversationID,
      title: String(format: "iOS regression %04d", testCase.ordinal),
      createdAt: timestamp,
      updatedAt: timestamp + max(result.durationMillis, 0),
      selectedModelOrAgent: "iOS production contracts",
      contextPolicy: "isolated-regression",
      summary: result.passed ? "PASS" : "FAIL",
      status: .active,
      privateMode: true,
      trackingPaused: true
    )
  }

  private func makeEntries(_ result: AgentIOSPr2638ExecutionResult) -> [AgentTranscriptEntry] {
    let testCase = result.testCase
    let timestamp = 1_750_000_000_000 + Int64(testCase.ordinal)
    let prefix = testCase.conversationID
    let specification = [
      "PR #\(testCase.pullRequest)",
      "suite=\(testCase.suiteID)",
      "profile=\(testCase.profileID)",
      "risk=\(testCase.riskID)"
    ].joined(separator: " | ")
    let measured = [
      result.passed ? "PASS" : "FAIL",
      "duration_ms=\(max(result.durationMillis, 0))",
      result.detail
    ].filter { !$0.isEmpty }.joined(separator: " | ")
    return [
      AgentTranscriptEntry(
        id: "\(prefix)-user",
        role: .user,
        text: specification,
        timestampMillis: timestamp,
        dedupeKey: "pr2638:\(testCase.id):specification",
        conversationId: prefix,
        turnId: "\(testCase.id)-turn"
      ),
      AgentTranscriptEntry(
        id: "\(prefix)-result",
        role: .assistant,
        text: measured,
        timestampMillis: timestamp + max(result.durationMillis, 1),
        dedupeKey: "pr2638:\(testCase.id):result",
        conversationId: prefix,
        turnId: "\(testCase.id)-turn"
      )
    ]
  }

  private func verify(_ results: [AgentIOSPr2638ExecutionResult]) throws {
    let expectedIDs = Set(results.map(\.testCase.conversationID))
    let persistedConversations = conversations.readAll().filter { expectedIDs.contains($0.id) }
    let entriesByConversation = Dictionary(
      grouping: transcripts.listConversations(expectedIDs),
      by: \.conversationId
    )
    guard persistedConversations.count == Self.expectedCount,
          entriesByConversation.values.reduce(0, { $0 + $1.count }) == Self.expectedCount * 2 else {
      throw AgentIOSPr2638PersistenceError.verificationFailed("batch-count")
    }
    let conversationsByID = Dictionary(uniqueKeysWithValues: persistedConversations.map { ($0.id, $0) })
    for result in results {
      let conversationID = result.testCase.conversationID
      guard let conversation = conversationsByID[conversationID],
            conversation.privateMode,
            conversation.trackingPaused,
            conversation.status == .active else {
        throw AgentIOSPr2638PersistenceError.verificationFailed(conversationID)
      }
      let entries = entriesByConversation[conversationID] ?? []
      guard entries.count == 2,
            Set(entries.map(\.id)) == Set(["\(conversationID)-user", "\(conversationID)-result"]) else {
        throw AgentIOSPr2638PersistenceError.verificationFailed(conversationID)
      }
    }
  }
}
