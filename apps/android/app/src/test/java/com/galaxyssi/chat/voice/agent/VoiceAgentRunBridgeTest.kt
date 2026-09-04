package com.galaxyssi.chat.voice.agent

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceAgentRunBridgeTest {
    private var now = 1_000L

    private fun bridge(
        repository: VoiceAgentRunRepository = InMemoryVoiceAgentRunRepository()
    ) = VoiceAgentRunBridge(
        repository = repository,
        clock = VoiceAgentRunClock { ++now }
    )

    private fun request(key: String = "turn-1") = VoiceAgentRunRequest(
        conversationId = "conversation-1",
        turnId = "turn-1",
        taskId = "task-1",
        sourceMessageId = 101L,
        contactId = "codex-desktop",
        agentId = "codex",
        agentName = "Codex",
        deviceId = "desktop-1",
        goal = "Inspect the project",
        idempotencyKey = key,
        traceId = "trace-1",
        createdAtMillis = now
    )

    private fun taskEvent(
        status: String,
        sequence: Long,
        eventId: String = "event-$sequence-$status"
    ) = JSONObject()
        .put("type", "agent_task_event")
        .put("task_id", "task-1")
        .put("source_message_id", 101L)
        .put("conversation_id", "conversation-1")
        .put("turn_id", "turn-1")
        .put("contact_id", "codex-desktop")
        .put("agent_id", "codex")
        .put("desktop_id", "desktop-1")
        .put("task_status", status)
        .put("status_seq", sequence)
        .put("event_id", eventId)

    @Test
    fun duplicateIdempotencyKeyReturnsTheOriginalRun() {
        val bridge = bridge()

        val first = bridge.createRun(request())
        val duplicate = bridge.createRun(request())

        assertTrue(first.created)
        assertFalse(duplicate.created)
        assertEquals(first.snapshot.runId, duplicate.snapshot.runId)
        assertEquals(1, bridge.snapshots().size)
    }

    @Test
    fun runningDoesNotImplyRemoteAcceptance() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot

        bridge.consumeRemoteEnvelope(taskEvent("running", 2L))
        val running = bridge.find(created.runId)

        assertEquals(VoiceAgentRunState.RUNNING, running?.state)
        assertFalse(running?.hasRemoteAcceptance == true)
    }

    @Test
    fun explicitAcceptedIsReportedOnlyOnce() {
        val bridge = bridge()
        bridge.createRun(request())

        val first = bridge.consumeRemoteEnvelope(taskEvent("accepted", 1L, "accepted-1"))
        val duplicate = bridge.consumeRemoteEnvelope(taskEvent("accepted", 1L, "accepted-1"))

        assertTrue(first.single().firstAcceptance)
        assertTrue(first.single().snapshot.hasRemoteAcceptance)
        assertTrue(duplicate.isEmpty())
    }

    @Test
    fun staleStatusSequenceCannotMoveTheRunBackwards() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot
        bridge.consumeRemoteEnvelope(taskEvent("running", 4L))

        val stale = bridge.consumeRemoteEnvelope(taskEvent("queued", 2L))

        assertTrue(stale.isEmpty())
        assertEquals(VoiceAgentRunState.RUNNING, bridge.find(created.runId)?.state)
        assertEquals(4L, bridge.find(created.runId)?.lastStatusSequence)
    }

    @Test
    fun terminalRunIgnoresLateAndConflictingEvents() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot
        bridge.consumeRemoteEnvelope(
            taskEvent("completed", 5L).put("result_summary", "Done")
        )

        assertTrue(bridge.consumeRemoteEnvelope(taskEvent("running", 6L)).isEmpty())
        assertTrue(bridge.consumeRemoteEnvelope(taskEvent("failed", 7L)).isEmpty())
        val terminal = bridge.find(created.runId)
        assertEquals(VoiceAgentRunState.COMPLETED, terminal?.state)
        assertEquals("Done", terminal?.resultSummary)
    }

    @Test
    fun repositoryRestoresRunAfterBridgeRecreation() {
        val repository = InMemoryVoiceAgentRunRepository()
        val firstBridge = bridge(repository)
        val created = firstBridge.createRun(request()).snapshot
        firstBridge.consumeRemoteEnvelope(taskEvent("accepted", 1L))

        val restored = bridge(repository).find(created.runId)

        assertNotNull(restored)
        assertEquals(VoiceAgentRunState.ACCEPTED, restored?.state)
        assertTrue(restored?.hasRemoteAcceptance == true)
    }

    @Test
    fun remoteEventCanRecoverAMissingLocalSnapshot() {
        val bridge = bridge()

        val transitions = bridge.consumeRemoteEnvelope(taskEvent("accepted", 1L))

        assertEquals(1, transitions.size)
        assertEquals(1, bridge.snapshots().size)
        assertEquals(VoiceAgentRunState.ACCEPTED, bridge.snapshots().single().state)
        assertTrue(bridge.snapshots().single().hasRemoteAcceptance)
    }

    @Test
    fun orderedPartialResultsMergeAndDuplicatesAreIgnored() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot
        val first = taskEvent("running", 2L).put(
            "partial_result",
            JSONObject()
                .put("event_id", "partial-1")
                .put("sequence", 1L)
                .put("text", "First finding. ")
        )
        val second = taskEvent("running", 3L).put(
            "partial_result",
            JSONObject()
                .put("event_id", "partial-2")
                .put("sequence", 2L)
                .put("text", "Second finding.")
        )

        bridge.consumeRemoteEnvelope(first)
        bridge.consumeRemoteEnvelope(second)
        bridge.consumeRemoteEnvelope(second)

        val snapshot = bridge.find(created.runId)
        assertEquals("First finding. Second finding.", snapshot?.partialResult)
        assertEquals("First finding.", snapshot?.firstDiscovery)
        assertEquals(2L, snapshot?.lastPartialSequence)
    }

    @Test
    fun privateProgressNeverReachesTheVisibleSnapshot() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot
        val envelope = taskEvent("running", 2L).put(
            "progress_event",
            JSONObject()
                .put("event_id", "private-1")
                .put("visibility", "private")
                .put("kind", "reasoning")
                .put("text", "Private reasoning")
        )

        bridge.consumeRemoteEnvelope(envelope)

        val snapshot = bridge.find(created.runId)
        assertEquals("", snapshot?.progressMessage)
        assertEquals("", snapshot?.partialResult)
    }

    @Test
    fun approvalEventPersistsWaitingState() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot
        val envelope = taskEvent("waiting_approval", 3L).put(
            "approval_request",
            JSONObject().put("approval_id", "approval-1")
        )

        bridge.consumeRemoteEnvelope(envelope)

        val snapshot = bridge.find(created.runId)
        assertEquals(VoiceAgentRunState.WAITING_APPROVAL, snapshot?.state)
        assertEquals("approval-1", snapshot?.approvalId)
    }

    @Test
    fun versionTwoEnvelopeUsesRunIdentityAndStructuredPayload() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot

        val accepted = JSONObject()
            .put("type", "agent_task_event")
            .put("schema_version", 2)
            .put("run_id", created.runId)
            .put("event_id", "accepted-v2")
            .put("status_seq", 1L)
            .put("event_type", "accepted")
            .put("created_at_ms", 1_500L)
            .put("payload", JSONObject())
        val partial = JSONObject(accepted.toString())
            .put("event_id", "partial-v2")
            .put("status_seq", 2L)
            .put("event_type", "partial_result")
            .put("payload", JSONObject()
                .put("sequence", 1L)
                .put("text", "A verified finding"))

        bridge.consumeRemoteEnvelope(accepted)
        bridge.consumeRemoteEnvelope(partial)

        val snapshot = bridge.find(created.runId)
        assertTrue(snapshot?.hasRemoteAcceptance == true)
        assertEquals(1_500L, snapshot?.acceptedAtMillis)
        assertEquals("A verified finding", snapshot?.partialResult)
    }

    @Test
    fun versionTwoPrivateReasoningIsIgnored() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot
        val event = JSONObject()
            .put("type", "agent_task_event")
            .put("schema_version", 2)
            .put("run_id", created.runId)
            .put("event_id", "private-v2")
            .put("status_seq", 1L)
            .put("event_type", "partial_result")
            .put("payload", JSONObject()
                .put("kind", "reasoning")
                .put("visibility", "private")
                .put("text", "Do not expose this"))

        assertTrue(bridge.consumeRemoteEnvelope(event).isEmpty())
        assertEquals("", bridge.find(created.runId)?.partialResult)
    }

    @Test
    fun oldDesktopFinalTextCompletesThePersistedRun() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot

        val transition = bridge.consumeLegacyFinal(
            sourceMessageId = 101L,
            taskId = "",
            content = "Legacy final result"
        )

        assertNotNull(transition)
        assertEquals(VoiceAgentRunState.COMPLETED, bridge.find(created.runId)?.state)
        assertEquals("Legacy final result", bridge.find(created.runId)?.resultSummary)
        assertNull(bridge.consumeLegacyFinal(101L, "", "Duplicate"))
    }

    @Test
    fun dispatchFailureEndsOnlyTheMatchingRun() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot

        bridge.markDispatchFailed(created.runId, "Publish failed")

        val snapshot = bridge.find(created.runId)
        assertEquals(VoiceAgentRunState.FAILED, snapshot?.state)
        assertEquals("Publish failed", snapshot?.resultSummary)
    }

    @Test
    fun cancellationRequestWaitsForRemoteTerminalConfirmation() {
        val bridge = bridge()
        val created = bridge.createRun(request()).snapshot

        val cancelling = bridge.markCancellationRequested(created.runId)
        bridge.consumeRemoteEnvelope(taskEvent("cancelled", 2L))

        assertEquals(VoiceAgentRunState.CANCELLING, cancelling?.state)
        assertEquals(VoiceAgentRunState.CANCELLED, bridge.find(created.runId)?.state)
    }
}
