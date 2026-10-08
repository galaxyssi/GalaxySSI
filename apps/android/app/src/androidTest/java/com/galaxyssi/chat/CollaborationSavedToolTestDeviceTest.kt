package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real encrypted persistence and native availability; no model calls or user task execution. */
@RunWith(AndroidJUnit4::class)
class CollaborationSavedToolTestDeviceTest {
    private fun withJournal(block: (CollaborationResearchWorkspace, CollaborationWorkspaceAccess) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "saved-tool-test-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf(CollaborationMember("worker", "Fixture", "fixture", "Fixture")), coordinatorId = "worker") }
        try { block(CollaborationResearchWorkspace(context), CollaborationWorkspaceAccess(group, "run", "turn", 1, "node", "worker")) }
        finally { groups.remove(group) }
    }

    private fun input() = JSONObject().put("mode", "start").put("execution_id", "fixture-test")
        .put("tool_test_plan", JSONObject().put("object_id", "a".repeat(64)).put("revision", 1).put("sha256", "b".repeat(64)))
        .put("timeout_ms", 1_000)

    @Test fun encryptedJournalRestoresFailedReceiptWithoutRunningAnything() = withJournal { workspace, access ->
        val first = workspace.savedToolTests(access, "before")
        assertTrue(first.start(input()).launch)
        assertTrue(first.running("fixture-test"))
        first.finish("fixture-test", JSONObject().put("passed", false).put("fixture", true))
        val restored = CollaborationResearchWorkspace(InstrumentationRegistry.getInstrumentation().targetContext).savedToolTests(access, "after")
        assertFalse(restored.start(input()).launch)
        assertFalse(restored.read("fixture-test")!!.getJSONObject("result").getBoolean("passed"))
    }

    @Test fun restartDoesNotTurnUncertainExecutionIntoRetry() = withJournal { workspace, access ->
        val first = workspace.savedToolTests(access, "before")
        first.start(input()); first.running("fixture-test")
        val after = CollaborationResearchWorkspace(InstrumentationRegistry.getInstrumentation().targetContext).savedToolTests(access, "after")
        assertEquals("interrupted", after.read("fixture-test")!!.getString("state"))
        assertFalse(after.start(input()).launch)
        assertFalse(after.running("fixture-test"))
        assertTrue(after.describe(after.read("fixture-test")).getString("reason").contains("Recover original evidence"))
    }

    @Test fun cancellationBeforeAdmissionToExecutorRemainsCancelled() = withJournal { workspace, access ->
        val journal = workspace.savedToolTests(access, "process")
        journal.start(input()); journal.cancel("fixture-test")
        val reopened = CollaborationResearchWorkspace(InstrumentationRegistry.getInstrumentation().targetContext).savedToolTests(access, "process")
        assertFalse(reopened.running("fixture-test"))
        assertEquals("cancelled", reopened.describe(reopened.read("fixture-test")).getString("status"))
    }

    @Test fun nativeRuntimeAvailabilityProbeDoesNotDownloadOrStartGuest() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val status = AgentOnDeviceRuntimeManager(context).cachedStatus()
        val available = AgentOnDeviceRuntimeTools.executionAvailability(status)
        assertEquals(status.backend != AgentOnDeviceRuntimeBackend.NONE, available.status == AgentNativeToolAvailabilityStatus.AVAILABLE)
        android.util.Log.i("GalaxySSITest", "saved_tool_runtime backend=${status.backend} ready=${status.backendReady} availability=${available.status}")
    }
}
