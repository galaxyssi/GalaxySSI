package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTranscriptRenderPolicyTest {
    @Test
    fun changedEntryWithStableIdIsReplacedInPlace() {
        val previous = entry("process-1", "Accepted")
        val current = entry("process-1", "Running")

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(previous.id),
            renderedSignatures = mapOf(previous.id to AgentTranscriptRenderPolicy.signature(previous)),
            incoming = listOf(current)
        )

        assertFalse(diff.reset)
        assertEquals(listOf(0), diff.replacementIndices)
        assertEquals(1, diff.appendFromIndex)
    }

    @Test
    fun unchangedPrefixOnlyAppendsNewRows() {
        val first = entry("user-1", "Run this")
        val second = entry("process-1", "Running")

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(first.id),
            renderedSignatures = mapOf(first.id to AgentTranscriptRenderPolicy.signature(first)),
            incoming = listOf(first, second)
        )

        assertFalse(diff.reset)
        assertTrue(diff.replacementIndices.isEmpty())
        assertEquals(1, diff.appendFromIndex)
    }

    @Test
    fun removedOrReorderedRowsRequireReset() {
        val first = entry("user-1", "Run this")
        val second = entry("process-1", "Running")

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(first.id, second.id),
            renderedSignatures = mapOf(
                first.id to AgentTranscriptRenderPolicy.signature(first),
                second.id to AgentTranscriptRenderPolicy.signature(second)
            ),
            incoming = listOf(second)
        )

        assertTrue(diff.reset)
        assertTrue(diff.replacementIndices.isEmpty())
        assertEquals(0, diff.appendFromIndex)
    }

    @Test
    fun richOutputChangeAlsoRefreshesStableAssistantRow() {
        val previous = entry("assistant-1", "Done", richOutputJson = "{\"type\":\"text\"}")
        val current = entry("assistant-1", "Done", richOutputJson = "{\"type\":\"table\"}")

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(previous.id),
            renderedSignatures = mapOf(previous.id to AgentTranscriptRenderPolicy.signature(previous)),
            incoming = listOf(current)
        )

        assertEquals(listOf(0), diff.replacementIndices)
    }

    @Test
    fun expandedChunkedOutputRefreshesOnlyItsStableRow() {
        val preview = entry("assistant-1", "preview").copy(
            role = AgentTranscriptRole.ASSISTANT,
            textChunkCount = 3,
            textLength = 20_000,
            textSha256 = "stable-output-digest"
        )
        val expanded = preview.copy(text = "full output ".repeat(1_800))

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(preview.id),
            renderedSignatures = mapOf(
                preview.id to AgentTranscriptRenderPolicy.signature(preview)
            ),
            incoming = listOf(expanded)
        )

        assertFalse(diff.reset)
        assertEquals(listOf(0), diff.replacementIndices)
    }

    @Test
    fun appendedAssistantRefreshesItsProcessHeader() {
        val user = entry(
            id = "user-1",
            text = "Run this",
            role = AgentTranscriptRole.USER,
            conversationId = "conversation",
            turnId = "turn"
        )
        val process = entry(
            id = "process-1",
            text = "Processing",
            role = AgentTranscriptRole.PROCESS,
            conversationId = "conversation",
            turnId = "turn"
        )
        val assistant = entry(
            id = "assistant-1",
            text = "Done",
            role = AgentTranscriptRole.ASSISTANT,
            conversationId = "conversation",
            turnId = "turn"
        )

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(user.id, process.id),
            renderedSignatures = mapOf(
                user.id to AgentTranscriptRenderPolicy.signature(user),
                process.id to AgentTranscriptRenderPolicy.signature(process)
            ),
            incoming = listOf(user, process, assistant)
        )

        assertFalse(diff.reset)
        assertEquals(listOf(1), diff.replacementIndices)
        assertEquals(2, diff.appendFromIndex)
    }

    @Test
    fun streamedAssistantBecomesFinalWithoutResettingTheTranscript() {
        val stream = entry("stream-1", "Part").copy(
            role = AgentTranscriptRole.ASSISTANT,
            dedupeKey = "assistant-final:turn:turn-1"
        )
        val final = stream.copy(id = "persisted-1", text = "Complete")
        val identity = AgentTranscriptRenderPolicy.identity(stream)

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(identity),
            renderedSignatures = mapOf(identity to AgentTranscriptRenderPolicy.signature(stream)),
            incoming = listOf(final)
        )

        assertFalse(diff.reset)
        assertEquals(listOf(0), diff.replacementIndices)
        assertEquals(1, diff.appendFromIndex)
    }

    @Test
    fun completedStreamWithIdenticalVisibleContentDoesNotRebind() {
        val stream = entry("stream-1", "Complete").copy(
            role = AgentTranscriptRole.ASSISTANT,
            timestampMillis = 10L,
            dedupeKey = "assistant-final:turn:turn-1"
        )
        val final = stream.copy(id = "persisted-1", timestampMillis = 20L)
        val identity = AgentTranscriptRenderPolicy.identity(stream)

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(identity),
            renderedSignatures = mapOf(identity to AgentTranscriptRenderPolicy.signature(stream)),
            incoming = listOf(final)
        )

        assertFalse(diff.reset)
        assertTrue(diff.replacementIndices.isEmpty())
        assertEquals(1, diff.appendFromIndex)
    }

    @Test
    fun unchangedImageMessageStaysBoundWhileProgressRowsRefresh() {
        val image = entry(
            id = "user-image",
            text = "What is this?",
            richOutputJson = "{\"type\":\"image\",\"attachmentId\":\"photo-1\"}",
            role = AgentTranscriptRole.USER
        )
        val progress = entry(
            id = "process-1",
            text = "Inspecting image",
            role = AgentTranscriptRole.PROCESS
        )

        assertTrue(AgentTranscriptRenderPolicy.sameContent(image, image.copy()))
        assertTrue(AgentTranscriptRenderPolicy.sameContent(progress, progress.copy()))
    }

    @Test
    fun growingLiveReplyDoesNotRefreshItsStableProcessHeader() {
        val process = entry(
            id = "process-1",
            text = "Working",
            role = AgentTranscriptRole.PROCESS,
            conversationId = "conversation",
            turnId = "turn"
        )
        val stream = entry(
            id = "agent-stream-1",
            text = "First",
            role = AgentTranscriptRole.ASSISTANT,
            conversationId = "conversation",
            turnId = "turn"
        ).copy(dedupeKey = "assistant-final:turn:turn")
        val next = stream.copy(text = "First second")

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(process.id, AgentTranscriptRenderPolicy.identity(stream)),
            renderedSignatures = mapOf(
                process.id to AgentTranscriptRenderPolicy.signature(process),
                AgentTranscriptRenderPolicy.identity(stream) to
                    AgentTranscriptRenderPolicy.signature(stream)
            ),
            incoming = listOf(process, next)
        )

        assertEquals(listOf(1), diff.replacementIndices)
    }

    @Test
    fun firstLiveReplyRefreshesItsProcessHeaderOnce() {
        val process = entry(
            id = "process-1",
            text = "Working",
            role = AgentTranscriptRole.PROCESS,
            conversationId = "conversation",
            turnId = "turn"
        )
        val stream = entry(
            id = "agent-stream-1",
            text = "First",
            role = AgentTranscriptRole.ASSISTANT,
            conversationId = "conversation",
            turnId = "turn"
        ).copy(dedupeKey = "assistant-final:turn:turn")

        val diff = AgentTranscriptRenderPolicy.diff(
            renderedIds = listOf(process.id),
            renderedSignatures = mapOf(
                process.id to AgentTranscriptRenderPolicy.signature(process)
            ),
            incoming = listOf(process, stream)
        )

        assertEquals(listOf(0), diff.replacementIndices)
        assertEquals(1, diff.appendFromIndex)
    }

    @Test
    fun processGroupSignatureChangesOnlyWhenItsNarrationChanges() {
        val first = entry(
            id = "process-1",
            text = "Inspecting",
            role = AgentTranscriptRole.PROCESS,
            conversationId = "conversation",
            turnId = "turn"
        ).copy(dedupeKey = "pending:plan:first")
        val second = first.copy(
            id = "process-2",
            text = "Testing",
            timestampMillis = 2L,
            dedupeKey = "pending:plan:second"
        )

        val before = AgentTranscriptRenderPolicy.processGroupSignatures(listOf(first))
        val unchanged = AgentTranscriptRenderPolicy.processGroupSignatures(listOf(first.copy()))
        val after = AgentTranscriptRenderPolicy.processGroupSignatures(listOf(first, second))

        assertEquals(before, unchanged)
        assertFalse(before == after)
    }

    @Test
    fun repeatedHiddenStatusEventsDoNotChangeProcessGroupSignature() {
        val narration = entry(
            id = "process-plan",
            text = "Inspecting the repository",
            role = AgentTranscriptRole.PROCESS,
            conversationId = "conversation",
            turnId = "turn"
        ).copy(dedupeKey = "pending:plan:first")
        val running = entry(
            id = "process-running-1",
            text = "working",
            role = AgentTranscriptRole.PROCESS,
            conversationId = "conversation",
            turnId = "turn"
        ).copy(dedupeKey = "connector-event:one")
        val repeatedRunning = running.copy(
            id = "process-running-2",
            timestampMillis = 2L,
            dedupeKey = "connector-event:two"
        )

        val before = AgentTranscriptRenderPolicy.processGroupSignatures(
            listOf(narration, running)
        )
        val after = AgentTranscriptRenderPolicy.processGroupSignatures(
            listOf(narration, running, repeatedRunning)
        )

        assertEquals(before, after)
    }

    @Test
    fun equivalentReasoningPrefixDoesNotChangeProcessGroupSignature() {
        val narration = entry(
            id = "process-plan",
            text = "Inspecting the repository",
            role = AgentTranscriptRole.PROCESS,
            conversationId = "conversation",
            turnId = "turn"
        ).copy(dedupeKey = "pending:plan:first")
        val repeated = narration.copy(
            id = "process-plan-duplicate",
            text = "Reasoning · Inspecting the repository",
            timestampMillis = 2L,
            dedupeKey = "pending:plan:duplicate"
        )

        assertEquals(
            AgentTranscriptRenderPolicy.processGroupSignatures(listOf(narration)),
            AgentTranscriptRenderPolicy.processGroupSignatures(listOf(narration, repeated))
        )
    }

    private fun entry(
        id: String,
        text: String,
        richOutputJson: String = "",
        role: AgentTranscriptRole = AgentTranscriptRole.PROCESS,
        conversationId: String = "",
        turnId: String = ""
    ) = AgentTranscriptEntry(
        id = id,
        role = role,
        text = text,
        timestampMillis = 1L,
        richOutputJson = richOutputJson,
        conversationId = conversationId,
        turnId = turnId
    )
}
