package com.galaxyssi.chat

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationLiveEvidenceSyncTest {
    private fun request(mode: String = "evidence") = JSONObject().put("phase", "read")
        .put("arguments", JSONObject().put("mode", mode)).put("expires_at", 21_000L)

    @Test fun refreshOnlyStartsOnCurrentEvidenceOrProblemBrowse() {
        assertTrue(CollaborationLiveEvidenceSync.needed(request()))
        assertTrue(CollaborationLiveEvidenceSync.needed(request("problems")))
        for (mode in listOf("workspace", "archive", "goal_contract", "capabilities", "numeric_cases"))
            assertFalse(mode, CollaborationLiveEvidenceSync.needed(request(mode)))
        assertFalse(CollaborationLiveEvidenceSync.needed(request().put("phase", "confirm")))
        for (selector in listOf("evidence_id", "cursor")) {
            val value = request().apply { getJSONObject("arguments").put(selector, "existing-page") }
            assertFalse(CollaborationLiveEvidenceSync.needed(value))
        }
    }

    @Test fun readDeadlineLeavesRoomForReplyAndDoesNotLimitTaskLifetime() {
        assertEquals(10_000L, CollaborationLiveEvidenceSync.budget(request(), 1_000))
        assertEquals(1_500L, CollaborationLiveEvidenceSync.budget(request(), 18_000))
        assertEquals(0L, CollaborationLiveEvidenceSync.budget(request(), 20_000))
        assertEquals(0L, CollaborationLiveEvidenceSync.budget(request(), 22_000))
    }

    @Test fun syncReportCannotClaimCompleteProviderHistoryOrVerifiedMeaning() {
        val report = CollaborationLiveEvidenceSync.report(JSONObject().put("status", "snapshot_imported")
            .put("cursor", 7).put("imported", 5).put("skipped_large", 2).put("archive_final", false))
        assertEquals(7L, report.getLong("synced_through_sequence"))
        assertEquals(2L, report.getLong("large_originals_not_imported"))
        assertFalse(report.getBoolean("archive_final"))
        assertFalse(report.getBoolean("provider_history_complete"))
        assertEquals("current_assignment_only", report.getString("scope"))
        assertTrue(report.getString("guidance").contains("Missing observations are not verified"))
        val unavailable = CollaborationLiveEvidenceSync.report(null, "unsupported")
        assertEquals("unsupported", unavailable.getString("status"))
        assertFalse(unavailable.getBoolean("archive_final"))
    }

    @Test fun unrelatedJobsDoNotWaitForAnOfflineReader(): Unit = runBlocking {
        val gate = CollaborationEvidenceImportGate()
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        val offline = async(start = CoroutineStart.UNDISPATCHED) {
            gate.withJob("offline") { entered.complete(Unit); release.await() }
        }
        entered.await()
        assertEquals("available", withTimeout(1_000) { gate.withJob("live") { "available" } })
        release.complete(Unit); offline.await()
        assertEquals(0, gate.size)
    }

    @Test fun cancelledWaiterAndOwnerReleaseRegistryWithoutBreakingMutualExclusion(): Unit = runBlocking {
        val gate = CollaborationEvidenceImportGate()
        val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
        val owner = async(start = CoroutineStart.UNDISPATCHED) {
            gate.withJob("same") { entered.complete(Unit); release.await() }
        }
        entered.await()
        val waiter = async(start = CoroutineStart.UNDISPATCHED) {
            gate.withJob("same") { error("Must remain behind the owner") }
        }
        waiter.cancel(); waiter.join()
        assertEquals(1, gate.size)
        owner.cancel(); owner.join()
        assertEquals(0, gate.size)
        assertEquals("recovered", gate.withJob("same") { "recovered" })
        assertEquals(0, gate.size)
    }
}
