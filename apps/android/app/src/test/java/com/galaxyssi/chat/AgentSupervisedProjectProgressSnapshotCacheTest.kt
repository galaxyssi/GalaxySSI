package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

class AgentSupervisedProjectProgressSnapshotCacheTest {
    @Test fun latestObservationIsTheWholeLastHostEntryIncludingFailureAndFieldIndex() {
        val first = action("first").copy(evidence = "OLD_SUCCESS", result = "OLD_SUCCESS")
        val latest = action("latest").copy(status = AgentActionStatus.FAILED, evidence = "READBACK_FAILED")
        val snapshot = AgentSupervisedProjectProgressSnapshotCache.compile(listOf(first, latest))
        assertTrue(requireNotNull(snapshot.promptLedger).endsWith(snapshot.latestObservation))
        assertTrue(snapshot.latestObservation.contains("status=FAILED"))
        assertTrue(snapshot.latestObservation.contains("READBACK_FAILED"))
        assertFalse(snapshot.latestObservation.contains("OLD_SUCCESS"))
        val observed = action("native").copy(evidence = """{"file":{"path":"outputs/a.txt","readable":true}}""")
        val withFields = AgentSupervisedProjectProgressSnapshotCache.compile(listOf(observed))
        assertTrue(withFields.latestObservation.contains("/file/readable"))
        assertTrue(withFields.promptLedger!!.endsWith(withFields.latestObservation))
    }

    @Test fun historyWithNoActualReceiptDoesNotInventPinnedEvidence() {
        val snapshot = AgentSupervisedProjectProgressSnapshotCache.compile(listOf(action("pending").copy(
            status = AgentActionStatus.RUNNING)))
        assertEquals("", snapshot.latestObservation)
        assertEquals(null, snapshot.promptLedger)
    }

    @Test
    fun sameImmutableHistoryCompilesProgressOnce() {
        val history = listOf(action("observe"))
        var compilations = 0

        val first = compile(history) { compilations += 1 }
        val second = compile(history) { compilations += 1 }

        assertSame(first, second)
        assertEquals(1, compilations)
    }

    @Test
    fun newHistoryObjectCannotReuseAnOlderProjectSnapshot() {
        val firstHistory = listOf(action("observe"))
        val nextHistory = firstHistory + action("edit")
        var compilations = 0

        val first = compile(firstHistory) { compilations += 1 }
        val next = compile(nextHistory) { compilations += 1 }

        assertNotSame(first, next)
        assertEquals(2, compilations)
        assertEquals("ledger-1", first.promptLedger)
        assertEquals("ledger-2", next.promptLedger)
    }

    private fun compile(
        history: List<AgentAction>,
        onCompile: () -> Unit
    ): AgentSupervisedProjectProgressSnapshot =
        AgentSupervisedProjectProgressSnapshotCache.compile(history) { actions ->
            onCompile()
            AgentSupervisedProjectProgressSnapshot(
                temporarilyBlockedToolIds = setOf("blocked-${actions.size}"),
                detailedToolIds = setOf("detailed-${actions.size}"),
                promptLedger = "ledger-${actions.size}"
            )
        }

    private fun action(id: String) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_NATIVE_TOOL,
        target = AgentMobileProjectNativeTools.OBSERVE,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.COMPLETED,
        description = id,
        parameters = mapOf("tool_id" to AgentMobileProjectNativeTools.OBSERVE),
        requiresConfirmation = false
    )
}
