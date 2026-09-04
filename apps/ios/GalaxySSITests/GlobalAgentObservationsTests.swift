import XCTest
@testable import GalaxySSI

final class GlobalAgentObservationsTests: XCTestCase {
  func testUserAttachmentIsBoundedCausalAndNeverExposesInlineDataOrSecrets() {
    let inlineData = String(repeating: "very-sensitive-binary-payload", count: 100)
    let entry = transcriptEntry(
      role: .user,
      richBlocks: [
        AgentRichBlock(
          id: "attachment-1",
          type: .image,
          title: "homework.png",
          uri: "content://private.provider/items/secret-path",
          dataB64: inlineData,
          mimeType: "image/png",
          metadata: ["token": "secret-token", "size_bytes": "4096"]
        )
      ]
    )

    let events = GlobalRichObservationExtractor.extract(
      conversation: conversation(),
      entry: entry,
      rootEventId: "transcript:root"
    )

    XCTAssertEqual(events.count, 1)
    let event = events[0]
    XCTAssertEqual(event.type, .attachmentAdded)
    XCTAssertEqual(event.causalEventIds, Set(["transcript:root"]))
    XCTAssertTrue(event.content.contains("homework.png"))
    XCTAssertFalse(event.content.contains(inlineData))
    XCTAssertFalse(event.metadata.values.contains { $0.contains("secret-token") || $0.contains("secret-path") })
    XCTAssertEqual(event.metadata["resource_scheme"], "content")
    XCTAssertTrue(event.contentRef.hasPrefix("encrypted://agent-transcript/"))
  }

  func testDuplicateRichBlocksProduceOneObservation() {
    let block = AgentRichBlock(
      id: "artifact-1",
      type: .file,
      title: "report.pdf",
      uri: "file:///private/report.pdf",
      mimeType: "application/pdf"
    )
    let entry = transcriptEntry(role: .assistant, richBlocks: [block, block])

    let events = GlobalRichObservationExtractor.extract(
      conversation: conversation(),
      entry: entry,
      rootEventId: "transcript:root"
    )

    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0].type, .artifactCreated)
  }

  func testPrivateOrPausedConversationsPublishNoRichObservations() {
    let entry = transcriptEntry(
      role: .user,
      richBlocks: [
        AgentRichBlock(
          id: "private-file",
          type: .file,
          title: "private.txt",
          uri: "content://private/file"
        )
      ]
    )

    XCTAssertTrue(
      GlobalRichObservationExtractor.extract(
        conversation: conversation(privateMode: true),
        entry: entry,
        rootEventId: "transcript:private"
      ).isEmpty
    )
    XCTAssertTrue(
      GlobalRichObservationExtractor.extract(
        conversation: conversation(trackingPaused: true),
        entry: entry,
        rootEventId: "transcript:paused"
      ).isEmpty
    )
  }

  func testProcessRowsUseTerminalToolLifecycleTypesWhileReasoningRemainsMessage() {
    let completed = transcriptEntry(
      role: .process,
      text: "Codex Agent completed",
      dedupeKey: "connector-task:task-1"
    )
    let failed = completed.with(text: "Codex Agent failed: timeout")
    let narration = completed
      .with(text: "Inspect the current project before editing")
      .with(dedupeKey: "pending:plan:step")

    XCTAssertEqual(GlobalRichObservationExtractor.transcriptEventType(completed, updated: true), .toolCompleted)
    XCTAssertEqual(GlobalRichObservationExtractor.transcriptEventType(failed, updated: true), .toolFailed)
    XCTAssertEqual(GlobalRichObservationExtractor.transcriptEventType(narration, updated: true), .messageUpdated)
  }

  func testRecordedRunPublishesTaskToolsAndArtifactsWithoutRawPathsOrSecretFields() {
    let run = AgentRecordedRun(
      runId: "run-1",
      conversationId: "conversation-a",
      taskThreadId: "thread-1",
      originalRequest: "Read the phone battery and create a report",
      toolCalls: [
        AgentToolCallRecord(
          id: "tool-1",
          toolName: "ios.device.battery",
          status: .succeeded,
          result: [
            "battery_level": .int(42),
            "token": .string("do-not-copy")
          ],
          startedAtMillis: 1_100,
          completedAtMillis: 1_200
        )
      ],
      artifacts: [
        AgentArtifactReference(
          id: "artifact-1",
          uri: "file:///private/report.json",
          name: "report.json",
          mimeType: "application/json",
          metadataJson: #"{"size_bytes":128,"path":"/private/report.json"}"#,
          createdAtMillis: 1_250
        )
      ],
      executionResourceId: "custom-route://secret-agent",
      status: .completed,
      createdAtMillis: 1_000,
      completedAtMillis: 1_300
    )

    let events = GlobalRecordedRunObservationExtractor.completed(run, conversationTitle: "Device status")

    XCTAssertEqual(events.count, 3)
    let tool = events.first { $0.type == .toolCompleted }
    let artifact = events.first { $0.type == .artifactCreated }
    XCTAssertTrue(tool?.content.contains("battery_level=42") ?? false)
    XCTAssertFalse(tool?.content.contains("do-not-copy") ?? true)
    XCTAssertFalse(artifact?.metadata.values.contains { $0.contains("/private/report.json") } ?? true)
    XCTAssertTrue(artifact?.contentRef.hasPrefix("encrypted://agent-runs/") ?? false)
    XCTAssertEqual(tool?.metadata["verified"], "true")
    XCTAssertEqual(events[0].metadata["execution_resource_id"]?.hasPrefix("resource:"), true)
  }

  func testStartedAndFeedbackEventsCarryRunCausality() {
    let run = AgentRecordedRun(
      runId: "run-2",
      conversationId: "conversation-a",
      taskThreadId: "thread-2",
      originalRequest: "Prepare a concise summary",
      activeSkillId: "skill-summary",
      executionResourceId: "codex",
      status: .running,
      createdAtMillis: 2_000
    )

    let started = GlobalRecordedRunObservationExtractor.started(run, conversationTitle: "Summaries")
    let feedback = GlobalRecordedRunObservationExtractor.feedback(
      run: run,
      feedback: "Helpful, keep it concise",
      timestampMillis: 2_500,
      conversationTitle: "Summaries"
    )

    XCTAssertEqual(started.id, "recorded-run:run-2:started")
    XCTAssertEqual(started.type, .taskUpdated)
    XCTAssertEqual(started.metadata["execution_resource_id"], "codex")
    XCTAssertEqual(feedback.type, .userFeedback)
    XCTAssertEqual(feedback.causalEventIds, Set([started.id]))
    XCTAssertEqual(feedback.metadata["feedback_kind"], "run_feedback")
  }

  private func conversation(
    privateMode: Bool = false,
    trackingPaused: Bool = false
  ) -> AgentConversation {
    AgentConversation(
      id: "conversation-a",
      title: "GalaxySSI planning",
      createdAt: 1_000,
      updatedAt: 1_000,
      privateMode: privateMode,
      trackingPaused: trackingPaused
    )
  }

  private func transcriptEntry(
    role: AgentTranscriptRole,
    text: String = "Attachment",
    dedupeKey: String = "",
    richBlocks: [AgentRichBlock] = []
  ) -> AgentTranscriptEntry {
    AgentTranscriptEntry(
      id: "entry-1",
      role: role,
      text: text,
      timestampMillis: 1_000,
      dedupeKey: dedupeKey,
      conversationId: "conversation-a",
      turnId: "turn-1",
      taskId: "task-1",
      richOutputJson: AgentRichContentCodec.encode(richBlocks)
    )
  }
}

private extension AgentTranscriptEntry {
  func with(text: String) -> AgentTranscriptEntry {
    var copy = self
    copy.text = text
    return copy
  }

  func with(dedupeKey: String) -> AgentTranscriptEntry {
    var copy = self
    copy.dedupeKey = dedupeKey
    return copy
  }
}
