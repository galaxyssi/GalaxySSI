package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTranscriptPresentationPolicyTest {

    @Test
    fun reasoningPrefixDoesNotCreateDuplicateNarrationIdentity() {
        val summary = "上次克隆失败，将先检查现有工作区。"

        assertEquals(
            AgentTranscriptPresentationPolicy.processNarrationIdentity(summary),
            AgentTranscriptPresentationPolicy.processNarrationIdentity("推理 · $summary")
        )
        assertEquals(
            AgentTranscriptPresentationPolicy.processNarrationIdentity("Inspect the repository first."),
            AgentTranscriptPresentationPolicy.processNarrationIdentity(
                "Reason · Inspect the repository first."
            )
        )
    }
    @Test
    fun placesOneProcessGroupBetweenTheUserAndAssistant() {
        val conversationId = "conversation"
        val turnId = "turn"
        val entries = listOf(
            entry("process-before-user", AgentTranscriptRole.PROCESS, conversationId, turnId, 1L),
            entry("user", AgentTranscriptRole.USER, conversationId, turnId, 2L),
            entry("process-running", AgentTranscriptRole.PROCESS, conversationId, turnId, 3L),
            entry("process-linux", AgentTranscriptRole.PROCESS, conversationId, turnId, 4L),
            entry("assistant", AgentTranscriptRole.ASSISTANT, conversationId, turnId, 5L)
        )

        val visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

        assertEquals(
            listOf(AgentTranscriptRole.USER, AgentTranscriptRole.PROCESS, AgentTranscriptRole.ASSISTANT),
            visible.map(AgentTranscriptEntry::role)
        )
        assertEquals("process-linux", visible[1].text)
    }

    @Test
    fun foldsACompletedConnectorEventWithARemoteTurnIdIntoTheLatestLocalTurn() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "conversation", "turn", 10L),
            entry("running", AgentTranscriptRole.PROCESS, "conversation", "turn", 20L),
            entry("assistant", AgentTranscriptRole.ASSISTANT, "conversation", "turn", 30L),
            entry("completed", AgentTranscriptRole.PROCESS, "conversation", "remote-codex-turn", 40L)
        )

        val visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

        assertEquals(
            listOf(AgentTranscriptRole.USER, AgentTranscriptRole.PROCESS, AgentTranscriptRole.ASSISTANT),
            visible.map(AgentTranscriptEntry::role)
        )
        assertEquals("completed", visible[1].text)
        assertEquals("turn", visible[1].turnId)
    }

    @Test
    fun processGroupKeepsStableRenderIdAsNewStepsArrive() {
        val user = entry("user", AgentTranscriptRole.USER, "conversation", "turn", 10L)
        val firstStep = entry(
            "planning",
            AgentTranscriptRole.PROCESS,
            "conversation",
            "turn",
            20L,
            "pending:plan:first"
        )
        val nextStep = entry(
            "running",
            AgentTranscriptRole.PROCESS,
            "conversation",
            "turn",
            30L,
            "pending:plan:second"
        )

        val initial = AgentTranscriptPresentationPolicy.collapseProcessGroups(
            listOf(user, firstStep)
        )
        val updated = AgentTranscriptPresentationPolicy.collapseProcessGroups(
            listOf(user, firstStep, nextStep)
        )

        assertEquals(initial[1].id, updated[1].id)
        assertEquals(
            AgentTranscriptRenderPolicy.identity(initial[1]),
            AgentTranscriptRenderPolicy.identity(updated[1])
        )
        assertEquals("running", updated[1].text)
    }

    @Test
    fun processGroupKeepsStableRenderIdWhenItsOnlyStatusRowIsReplaced() {
        val user = entry("user", AgentTranscriptRole.USER, "conversation", "turn", 10L)
        val accepted = entry(
            "accepted",
            AgentTranscriptRole.PROCESS,
            "conversation",
            "turn",
            20L,
            "pending:plan:accepted"
        )
        val running = entry(
            "running",
            AgentTranscriptRole.PROCESS,
            "conversation",
            "turn",
            30L,
            "pending:plan:running"
        )

        val initial = AgentTranscriptPresentationPolicy.collapseProcessGroups(listOf(user, accepted))
        val updated = AgentTranscriptPresentationPolicy.collapseProcessGroups(listOf(user, running))
        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = initial.map(AgentTranscriptEntry::id),
            renderedSignatures = initial.associate { entry ->
                entry.id to AgentTranscriptRenderPolicy.signature(entry)
            },
            incoming = updated
        )

        assertEquals(initial[1].id, updated[1].id)
        assertEquals(
            AgentTranscriptRenderPolicy.identity(initial[1]),
            AgentTranscriptRenderPolicy.identity(updated[1])
        )
        assertFalse(diff.reset)
        assertEquals(listOf(1), diff.replacementIndices)
    }

    @Test
    fun classifiesProcessRowsForCodexStyleIcons() {
        assertEquals(
            AgentTranscriptPresentationPolicy.ProcessVisualKind.ANALYSIS,
            AgentTranscriptPresentationPolicy.processVisualKind("\u5df2\u5206\u6790\u8bf7\u6c42")
        )
        assertEquals(
            AgentTranscriptPresentationPolicy.ProcessVisualKind.COMMAND,
            AgentTranscriptPresentationPolicy.processVisualKind("\u6b63\u5728\u8fd0\u884c\u624b\u673a\u672c\u5730 Linux")
        )
        assertEquals(
            AgentTranscriptPresentationPolicy.ProcessVisualKind.FILE,
            AgentTranscriptPresentationPolicy.processVisualKind("Edited 2 files")
        )
        assertEquals(
            AgentTranscriptPresentationPolicy.ProcessVisualKind.IMAGE,
            AgentTranscriptPresentationPolicy.processVisualKind("\u5df2\u67e5\u770b 1 \u5f20\u56fe\u7247")
        )
        assertEquals(
            AgentTranscriptPresentationPolicy.ProcessVisualKind.NETWORK,
            AgentTranscriptPresentationPolicy.processVisualKind("Web search complete")
        )
    }

    @Test
    fun expandsActiveProcessAndCollapsesCompletedProcessByDefault() {
        assertTrue(AgentTranscriptPresentationPolicy.processExpanded(false, false, false))
        assertFalse(AgentTranscriptPresentationPolicy.processExpanded(false, false, true))
        assertFalse(AgentTranscriptPresentationPolicy.processExpanded(true, false, false))
        assertTrue(AgentTranscriptPresentationPolicy.processExpanded(true, true, false))
    }

    @Test
    fun voiceRunLookupOnlyRunsForActiveCancellableTasks() {
        assertTrue(AgentTranscriptPresentationPolicy.shouldLookupVoiceRun(false, true, "task-1"))
        assertFalse(AgentTranscriptPresentationPolicy.shouldLookupVoiceRun(true, true, "task-1"))
        assertFalse(AgentTranscriptPresentationPolicy.shouldLookupVoiceRun(false, false, "task-1"))
        assertFalse(AgentTranscriptPresentationPolicy.shouldLookupVoiceRun(false, true, ""))
    }

    @Test
    fun hidesOnlySuccessfulAsynchronousConnectorDispatchCompletion() {
        assertFalse(
            AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
                AgentActionKind.CALL_CONNECTOR,
                succeeded = true,
                awaitingResponse = true
            )
        )
        assertFalse(
            AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
                AgentActionKind.CALL_CONNECTOR,
                succeeded = true,
                awaitingResponse = null
            )
        )
        assertTrue(
            AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
                AgentActionKind.CALL_CONNECTOR,
                succeeded = true,
                awaitingResponse = false
            )
        )
        assertTrue(
            AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
                AgentActionKind.CALL_CONNECTOR,
                succeeded = false,
                awaitingResponse = true
            )
        )
        assertTrue(
            AgentTranscriptPresentationPolicy.shouldRenderToolCompletion(
                AgentActionKind.CALL_NATIVE_TOOL,
                succeeded = true,
                awaitingResponse = false
            )
        )
    }

    @Test
    fun formatsEveryProcessingDurationInSeconds() {
        assertEquals("1s", AgentTranscriptPresentationPolicy.formatElapsedSeconds(0L))
        assertEquals("1s", AgentTranscriptPresentationPolicy.formatElapsedSeconds(999L))
        assertEquals("1s", AgentTranscriptPresentationPolicy.formatElapsedSeconds(1_999L))
        assertEquals("2s", AgentTranscriptPresentationPolicy.formatElapsedSeconds(2_000L))
        assertEquals("59s", AgentTranscriptPresentationPolicy.formatElapsedSeconds(59_999L))
        assertEquals("1m", AgentTranscriptPresentationPolicy.formatElapsedSeconds(60_000L))
        assertEquals("1m 17s", AgentTranscriptPresentationPolicy.formatElapsedSeconds(77_000L))
        assertEquals("1h", AgentTranscriptPresentationPolicy.formatElapsedSeconds(3_600_000L))
        assertEquals("1h 17m 26s", AgentTranscriptPresentationPolicy.formatElapsedSeconds(4_646_000L))
    }

    @Test
    fun separatesModelNarrationFromContiguousToolActivity() {
        val entries = listOf(
            entry("Analyzed the request · Codex", AgentTranscriptRole.PROCESS, "conversation", "turn", 1L,
                "audit:1:REASONING_SUMMARY:fallback"),
            entry("tool-start", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L,
                "audit:2:TOOL_STARTED:x"),
            entry("tool-complete", AgentTranscriptRole.PROCESS, "conversation", "turn", 3L,
                "audit:3:TOOL_COMPLETED:x"),
            entry("Implement a small Python program", AgentTranscriptRole.PROCESS, "conversation", "turn", 4L,
                "pending:plan:action"),
            entry("phone-linux", AgentTranscriptRole.PROCESS, "conversation", "turn", 5L,
                "audit:5:TOOL_STARTED:y"),
            entry("phone-linux-complete", AgentTranscriptRole.PROCESS, "conversation", "turn", 6L,
                "audit:6:TOOL_COMPLETED:y")
        )

        val segments = AgentTranscriptPresentationPolicy.processSegments(entries)

        assertEquals(
            listOf(
                AgentTranscriptPresentationPolicy.ProcessContentKind.TOOL_ACTIVITY,
                AgentTranscriptPresentationPolicy.ProcessContentKind.NARRATION,
                AgentTranscriptPresentationPolicy.ProcessContentKind.TOOL_ACTIVITY
            ),
            segments.map(AgentTranscriptPresentationPolicy.ProcessSegment::kind)
        )
        assertEquals(listOf(3, 1, 2), segments.map { it.entries.size })
    }

    @Test
    fun replacesGenericConnectorFallbacksWithVisibleCodexProgress() {
        val entries = listOf(
            entry("Analyzed the request", AgentTranscriptRole.PROCESS, "conversation", "turn", 1L,
                "audit:1:REASONING_SUMMARY:fallback"),
            entry("Running Codex", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L,
                "audit:2:TOOL_STARTED:codex"),
            entry("I will inspect the provided input before acting.", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 3L,
                "connector-event:task:REASONING_SUMMARY:codex:commentary:1"),
            entry("Viewed 1 image", AgentTranscriptRole.PROCESS, "conversation", "turn", 4L,
                "connector-event:task:TOOL_EVENT:codex:image_view:1")
        )

        val segments = AgentTranscriptPresentationPolicy.processSegments(entries)
        val visibleText = segments.flatMap { segment -> segment.entries }.map(AgentTranscriptEntry::text)

        assertEquals(
            listOf(
                "I will inspect the provided input before acting.",
                "Viewed 1 image"
            ),
            visibleText
        )
        assertEquals(
            listOf(
                AgentTranscriptPresentationPolicy.ProcessContentKind.NARRATION,
                AgentTranscriptPresentationPolicy.ProcessContentKind.TOOL_ACTIVITY
            ),
            segments.map(AgentTranscriptPresentationPolicy.ProcessSegment::kind)
        )
    }

    @Test
    fun hidesGenericExecutionLoopScaffoldingAndConnectorHeartbeat() {
        val entries = listOf(
            entry("Planning", AgentTranscriptRole.PROCESS, "conversation", "turn", 1L,
                "agent-loop:turn:PLAN:1"),
            entry("Checking the result", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L,
                "agent-loop:turn:OBSERVE:2"),
            entry("Waiting for a resource", AgentTranscriptRole.PROCESS, "conversation", "turn", 3L,
                "agent-loop:turn:WAITING_RESPONSE:3"),
            entry("Working", AgentTranscriptRole.PROCESS, "conversation", "turn", 4L,
                "connector-event:task:TOOL_EVENT:codex:heartbeat:1"),
            entry("No progress reported", AgentTranscriptRole.PROCESS, "conversation", "turn", 5L,
                "task-watchdog:turn"),
            entry("Finalizing", AgentTranscriptRole.PROCESS, "conversation", "turn", 6L,
                "agent-loop:turn:FINALIZE:4")
        )

        assertTrue(AgentTranscriptPresentationPolicy.processSegments(entries).isEmpty())
    }

    @Test
    fun keepsModelNarrationAndConcreteToolsWhileHidingLoopScaffolding() {
        val entries = listOf(
            entry("Planning", AgentTranscriptRole.PROCESS, "conversation", "turn", 1L,
                "agent-loop:turn:PLAN:1"),
            entry("I will inspect the workbook before changing it.", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 2L,
                "connector-event:task:REASONING_SUMMARY:codex:commentary:1"),
            entry("Ran python validate_workbook.py", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 3L,
                "connector-event:task:TOOL_EVENT:codex:command:1"),
            entry("Verifying", AgentTranscriptRole.PROCESS, "conversation", "turn", 4L,
                "agent-loop:turn:VERIFY:2")
        )

        val segments = AgentTranscriptPresentationPolicy.processSegments(entries)

        assertEquals(
            listOf(
                "I will inspect the workbook before changing it.",
                "Ran python validate_workbook.py"
            ),
            segments.flatMap(AgentTranscriptPresentationPolicy.ProcessSegment::entries)
                .map(AgentTranscriptEntry::text)
        )
        assertEquals(
            listOf(
                AgentTranscriptPresentationPolicy.ProcessContentKind.NARRATION,
                AgentTranscriptPresentationPolicy.ProcessContentKind.TOOL_ACTIVITY
            ),
            segments.map(AgentTranscriptPresentationPolicy.ProcessSegment::kind)
        )
    }

    @Test
    fun rendersModelNarrationButNotInternalToolActivityInTheConversation() {
        val entries = listOf(
            entry("I will inspect the workbook before changing it.", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 1L,
                "connector-event:task:REASONING_SUMMARY:codex:commentary:1"),
            entry("Ran python validate_workbook.py", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 2L,
                "connector-event:task:TOOL_EVENT:codex:command:1"),
            entry("Viewed 1 image", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 3L,
                "connector-event:task:TOOL_EVENT:codex:image_view:2")
        )

        val visible = AgentTranscriptPresentationPolicy.narrationSegments(entries)

        assertEquals(1, visible.size)
        assertEquals(
            AgentTranscriptPresentationPolicy.ProcessContentKind.NARRATION,
            visible.single().kind
        )
        assertEquals(
            listOf("I will inspect the workbook before changing it."),
            visible.single().entries.map(AgentTranscriptEntry::text)
        )
    }

    @Test
    fun hidesToolOnlyProcessDetailsFromTheConversation() {
        val entries = listOf(
            entry("Running Codex", AgentTranscriptRole.PROCESS, "conversation", "turn", 1L,
                "audit:1:TOOL_STARTED:codex"),
            entry("Codex completed", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L,
                "audit:2:TOOL_COMPLETED:codex")
        )

        assertTrue(AgentTranscriptPresentationPolicy.narrationSegments(entries).isEmpty())
    }

    @Test
    fun hidesLegacyAggregatedToolStepSummariesFromStoredConversations() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "conversation", "turn", 1L),
            entry("\u8fd0\u884c\u4e86 3 \u4e2a\u5de5\u5177\u6b65\u9aa4", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L,
                "pending:legacy:tool-summary"),
            entry("Ran 2 tool steps.", AgentTranscriptRole.PROCESS, "conversation", "turn", 3L,
                "pending:legacy:tool-summary-en"),
            entry("assistant", AgentTranscriptRole.ASSISTANT, "conversation", "turn", 4L)
        )

        val visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

        assertEquals(listOf("user", "assistant"), visible.map(AgentTranscriptEntry::text))
        assertTrue(AgentTranscriptPresentationPolicy.processSegments(entries).isEmpty())
    }

    @Test
    fun recognizesInternalCancellationMessagesForUiLocalization() {
        assertEquals(
            AgentTranscriptPresentationPolicy.ControlMessageKind.CANCELLED,
            AgentTranscriptPresentationPolicy.controlMessageKind("Task cancelled")
        )
        assertEquals(
            AgentTranscriptPresentationPolicy.ControlMessageKind.CANCELLED,
            AgentTranscriptPresentationPolicy.controlMessageKind(" task CANCELED ")
        )
        assertEquals(
            null,
            AgentTranscriptPresentationPolicy.controlMessageKind("The user discussed a cancelled task")
        )
    }

    @Test
    fun removesRedundantConnectorCompletionFromTheRenderedTurn() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "conversation", "turn", 1L),
            entry("tool", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L,
                "audit:2:TOOL_COMPLETED:x"),
            entry("duplicate", AgentTranscriptRole.PROCESS, "conversation", "turn", 3L,
                "connector-task:remote-task"),
            entry("assistant", AgentTranscriptRole.ASSISTANT, "conversation", "turn", 4L)
        )

        val visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

        assertEquals(listOf("user", "tool", "assistant"), visible.map(AgentTranscriptEntry::text))
    }

    @Test
    fun hidesInternalPhoneLinuxHandoffNarration() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "conversation", "turn", 1L),
            entry("\u624b\u673a\u672c\u5730 Linux \u00b7 \u6267\u884c\u5e76\u9a8c\u8bc1", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 2L, "pending:plan:runtime"),
            entry("implementation", AgentTranscriptRole.PROCESS, "conversation", "turn", 3L,
                "pending:plan:summary"),
            entry("assistant", AgentTranscriptRole.ASSISTANT, "conversation", "turn", 4L)
        )

        val visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

        assertEquals(listOf("user", "implementation", "assistant"), visible.map(AgentTranscriptEntry::text))
    }

    @Test
    fun hidesRawOnDeviceLinuxSandboxHandoffButKeepsModelNarration() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "conversation", "turn", 1L),
            entry("Execute in the on-device Linux sandbox", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 2L, "pending:plan:runtime"),
            entry("Implement a small Python program", AgentTranscriptRole.PROCESS,
                "conversation", "turn", 3L, "pending:plan:summary"),
            entry("assistant", AgentTranscriptRole.ASSISTANT, "conversation", "turn", 4L)
        )

        val visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

        assertEquals(
            listOf("user", "Implement a small Python program", "assistant"),
            visible.map(AgentTranscriptEntry::text)
        )
    }

    @Test
    fun hidesLegacyLocalAgentRuntimeAuditRows() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "conversation", "turn", 1L),
            entry("Codex completed", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L,
                "audit:2:TOOL_COMPLETED:codex"),
            entry("Running local-agent-runtime", AgentTranscriptRole.PROCESS, "conversation", "turn", 3L,
                "audit:3:TOOL_STARTED:runtime"),
            entry("local-agent-runtime completed", AgentTranscriptRole.PROCESS, "conversation", "turn", 4L,
                "audit:4:TOOL_COMPLETED:runtime"),
            entry("assistant", AgentTranscriptRole.ASSISTANT, "conversation", "turn", 5L)
        )

        val visible = AgentTranscriptPresentationPolicy.collapseProcessGroups(entries)

        assertEquals(listOf("user", "Codex completed", "assistant"), visible.map(AgentTranscriptEntry::text))
    }

    @Test
    fun recoversAStaleConnectorTurnWithoutAnAssistantReply() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "conversation", "turn", 1L),
            entry("remote", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L, "connector-task:task")
        )
        val task = AgentTaskRecord(
            taskId = "task",
            sessionId = "conversation",
            goal = "goal",
            phase = AgentPhase.COMPLETED,
            routeKind = AgentRouteKind.DESKTOP_AGENT,
            targetTitle = "Codex",
            risk = AgentRisk.LOW,
            blocked = false,
            result = "Recovered result",
            createdAtMillis = 1L,
            updatedAtMillis = 2L
        )

        val recovered = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
            entries = entries,
            tasks = listOf(task),
            activeTaskIds = emptySet(),
            nowMillis = 5L * 60L * 1_000L + 3L
        )

        assertEquals(1, recovered.size)
        assertEquals("Recovered result", recovered.single().result)
        assertEquals("turn", recovered.single().turnId)
    }

    @Test
    fun doesNotRecoverAnActiveOrAlreadyAnsweredConnectorTurn() {
        val entries = listOf(
            entry("user", AgentTranscriptRole.USER, "conversation", "turn", 1L),
            entry("remote", AgentTranscriptRole.PROCESS, "conversation", "turn", 2L, "connector-task:task"),
            entry("assistant", AgentTranscriptRole.ASSISTANT, "conversation", "turn", 3L)
        )
        val task = AgentTaskRecord(
            taskId = "task",
            sessionId = "conversation",
            goal = "goal",
            phase = AgentPhase.EXECUTING,
            routeKind = AgentRouteKind.DESKTOP_AGENT,
            targetTitle = "Codex",
            risk = AgentRisk.LOW,
            blocked = false,
            updatedAtMillis = 2L
        )

        val answered = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
            entries,
            listOf(task),
            emptySet(),
            10L * 60L * 1_000L
        )
        val active = AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
            entries.dropLast(1),
            listOf(task),
            setOf("task"),
            10L * 60L * 1_000L
        )

        assertTrue(answered.isEmpty())
        assertTrue(active.isEmpty())
    }

    @Test
    fun stopsProcessClockForUserControlledAndTerminalWorkspaceStates() {
        val stopped = setOf(
            AgentWorkspaceStatus.WAITING_CONFIRMATION,
            AgentWorkspaceStatus.PAUSED,
            AgentWorkspaceStatus.BLOCKED,
            AgentWorkspaceStatus.COMPLETED,
            AgentWorkspaceStatus.FAILED,
            AgentWorkspaceStatus.CANCELLED
        )

        AgentWorkspaceStatus.entries.forEach { status ->
            assertEquals(
                status in stopped,
                AgentTranscriptPresentationPolicy.processClockStopsFor(status)
            )
        }
    }

    private fun entry(
        id: String,
        role: AgentTranscriptRole,
        conversationId: String,
        turnId: String,
        timestamp: Long,
        dedupeKey: String = ""
    ) = AgentTranscriptEntry(
        id = id,
        role = role,
        text = id,
        timestampMillis = timestamp,
        conversationId = conversationId,
        turnId = turnId,
        dedupeKey = dedupeKey,
        taskId = "task"
    )
}
