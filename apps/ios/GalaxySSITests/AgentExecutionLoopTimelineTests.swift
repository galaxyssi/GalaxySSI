import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
  func testAgentExecutionLoopTimelinePolicyProjectsCanonicalPhases() {
    let plan = AgentExecutionLoopTimelinePolicy.project(loopEvent(.plan))
    let act = AgentExecutionLoopTimelinePolicy.project(
      loopEvent(
        .act,
        actionId: "tool-1",
        toolCall: true,
        usage: AgentExecutionLoopUsage(iterations: 1, actions: 1, toolCalls: 1)
      )
    )
    let observe = AgentExecutionLoopTimelinePolicy.project(loopEvent(.observe, actionId: "tool-1"))
    let replan = AgentExecutionLoopTimelinePolicy.project(loopEvent(.replan, actionId: "tool-1"))

    XCTAssertEqual(plan.controlEventType, .planning)
    XCTAssertEqual(act.controlEventType, .toolStarted)
    XCTAssertEqual(act.toolCallId, "tool-1")
    XCTAssertEqual(observe.controlEventType, .toolProgress)
    XCTAssertEqual(replan.controlEventType, .retrying)
    XCTAssertEqual(plan.payload["timeline_kind"]?.stringValue, "plan")
    XCTAssertEqual(act.payload["timeline_kind"]?.stringValue, "tool")
    XCTAssertEqual(replan.payload["timeline_kind"]?.stringValue, "retry")
  }

  func testAgentExecutionLoopTimelinePolicyProjectsRecoveryCompletionAndRevision() {
    let recovered = AgentExecutionLoopTimelinePolicy.project(
      loopEvent(.act, previousPhase: .failed, actionId: "retry", retry: true)
    )
    let completed = AgentExecutionLoopTimelinePolicy.project(loopEvent(.completed))
    let event = loopEvent(
      .act,
      actionId: "action",
      toolCall: true,
      revision: 7,
      usage: AgentExecutionLoopUsage(iterations: 1, actions: 1, toolCalls: 1)
    )
    let projection = AgentExecutionLoopTimelinePolicy.project(event)
    let runEvent = runControlEvent(type: projection.controlEventType, payload: projection.payload)

    XCTAssertEqual(recovered.controlEventType, .runRecovered)
    XCTAssertEqual(recovered.payload["loop_retry"]?.boolValue, true)
    XCTAssertEqual(completed.controlEventType, .runCompleted)
    XCTAssertNil(completed.label)
    XCTAssertEqual(projection.payload["loop_revision"]?.intValue, 7)
    XCTAssertEqual(projection.payload["loop_actions"]?.intValue, 1)
    XCTAssertEqual(projection.payload["loop_tool_calls"]?.intValue, 1)
    XCTAssertEqual(projection.payload["loop_action_id"]?.stringValue, "action")
    XCTAssertTrue(AgentExecutionLoopTimelinePolicy.isSameRevision(event: runEvent, revision: 7))
    XCTAssertFalse(AgentExecutionLoopTimelinePolicy.isSameRevision(event: runEvent, revision: 8))
  }

  func testAgentExecutionLoopTimelinePolicyKeysActionsAndPlaceholderSuppression() {
    let event = loopEvent(.plan, revision: 3)
    let key = AgentExecutionLoopTimelinePolicy.transcriptDedupeKey(turnId: "turn", event: event)
    let genericAct = transcriptEntry("generic-act", text: "Executing task step", dedupeKey: "agent-loop:turn:ACT:2")
    let genericObserve = transcriptEntry("generic-observe", text: "Inspecting result", dedupeKey: "agent-loop:turn:OBSERVE:3")
    let detailedStart = transcriptEntry("tool-start", text: "Phone Linux: python app.py", dedupeKey: "audit:4:TOOL_STARTED:1")
    let detailedComplete = transcriptEntry("tool-complete", text: "Phone Linux completed", dedupeKey: "audit:5:TOOL_COMPLETED:1")

    XCTAssertEqual(AgentExecutionLoopTimelinePolicy.phaseFromTranscriptDedupeKey(key), .plan)
    XCTAssertNil(AgentExecutionLoopTimelinePolicy.phaseFromTranscriptDedupeKey("audit:1"))
    XCTAssertNil(AgentExecutionLoopTimelinePolicy.phaseFromTranscriptDedupeKey("agent-loop:turn:FUTURE:1"))
    XCTAssertEqual(
      AgentExecutionLoopTimelinePolicy.suppressSupersededPlaceholders([
        genericAct,
        genericObserve,
        detailedStart,
        detailedComplete
      ]),
      [detailedStart, detailedComplete]
    )
    XCTAssertEqual(
      AgentExecutionLoopTimelinePolicy.suppressSupersededPlaceholders([genericAct, genericObserve]),
      [genericAct, genericObserve]
    )

    for phase in [AgentPhase.planning, .waitingConfirmation, .executing, .verifying] {
      XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(phase), [.pause, .cancel])
    }
    for phase in [AgentPhase.observing, .waitingResponse] {
      XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(phase), [.cancel])
    }
    XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(.paused), [.resume, .cancel])
    XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(.blocked), [.replan, .cancel])
    XCTAssertEqual(AgentExecutionLoopTimelinePolicy.actionsForPhase(.failed), [.retry, .replan])
    XCTAssertTrue(AgentExecutionLoopTimelinePolicy.actionsForPhase(.completed).isEmpty)
    XCTAssertTrue(AgentExecutionLoopTimelinePolicy.actionsForPhase(.cancelled).isEmpty)
  }

  func testAgentRunTimelineContractCoverageMatchesAndroidKinds() {
    let events = [
      runControlEvent(type: .planning),
      runControlEvent(type: .toolStarted, toolCallId: "tool-1"),
      runControlEvent(type: .toolCompleted, toolCallId: "tool-1"),
      runControlEvent(type: .retrying),
      runControlEvent(type: .runCompleted)
    ]
    let coverage = AgentRunTimelineContract.coverage(events)
    let failed = AgentRunTimelineContract.coverage([runControlEvent(type: .runFailed)])
    let declared = runControlEvent(type: .stepStarted, payload: ["timeline_kind": .string("verify")])

    XCTAssertTrue(coverage.hasPlan)
    XCTAssertEqual(coverage.toolEventCount, 2)
    XCTAssertEqual(coverage.retryEventCount, 1)
    XCTAssertTrue(coverage.hasResult)
    XCTAssertTrue(coverage.complete)
    XCTAssertTrue(failed.hasFailure)
    XCTAssertTrue(failed.terminal)
    XCTAssertFalse(failed.complete)
    XCTAssertEqual(AgentRunTimelineContract.kind(declared), .verify)
  }

  func testAgentExecutionLoopTimelineModelsUseAndroidWireNames() throws {
    let decoded = try JSONDecoder().decode(
      AgentRunControlEvent.self,
      from: Data(
        #"""
        {
          "event_id": "event",
          "conversation_id": "conversation",
          "message_id": "turn",
          "task_id": "task",
          "run_id": "run",
          "step_id": "step",
          "tool_call_id": "tool",
          "agent_id": "galaxyssi-mobile",
          "device_id": "phone",
          "type": "TOOL_STARTED",
          "sequence": 4,
          "timestamp_millis": 1234,
          "payload": {
            "timeline_kind": "tool",
            "loop_revision": 7,
            "loop_retry": true
          }
        }
        """#.utf8
      )
    )
    let fallbackPhase = try JSONDecoder().decode(
      AgentExecutionLoopPhase.self,
      from: Data(#""future""#.utf8)
    )
    let fallbackType = try JSONDecoder().decode(
      AgentRunControlEventType.self,
      from: Data(#""future""#.utf8)
    )
    let encodedEvent = String(decoding: try JSONEncoder().encode(loopEvent(.act, previousPhase: .failed)), as: UTF8.self)
    let encodedProjection = String(
      decoding: try JSONEncoder().encode(AgentExecutionLoopTimelinePolicy.project(loopEvent(.act, actionId: "tool"))),
      as: UTF8.self
    )

    XCTAssertEqual(decoded.type, .toolStarted)
    XCTAssertEqual(decoded.toolCallId, "tool")
    XCTAssertEqual(decoded.payload["loop_revision"]?.intValue, 7)
    XCTAssertEqual(decoded.payload["loop_retry"]?.boolValue, true)
    XCTAssertEqual(fallbackPhase, .plan)
    XCTAssertEqual(fallbackType, .runFailed)
    XCTAssertTrue(AgentExecutionLoopPhase.completed.isTerminal)
    XCTAssertTrue(AgentExecutionLoopUsage(activeDurationMillis: 20, activeSinceMillis: 100).elapsedActiveMillis(nowMillis: 150, phase: .act) == 70)
    XCTAssertTrue(encodedEvent.contains(#""previous_phase":"FAILED""#))
    XCTAssertTrue(encodedProjection.contains(#""control_event_type":"STEP_STARTED""#))
    XCTAssertTrue(encodedProjection.contains(#""timeline_contract":"galaxyssi.run-timeline/1.0""#))
  }
}
