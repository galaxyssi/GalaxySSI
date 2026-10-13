package com.galaxyssi.chat

import android.os.Process
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Two-process encrypted ownership/control persistence, not a real-provider or website login test. */
@RunWith(AndroidJUnit4::class)
class AgentManagedBrowserControlRestartDeviceTest {
    @Test fun checkpointPhase() = runBlocking {
        val arguments = InstrumentationRegistry.getArguments()
        val phase = arguments.getString("managedBrowserPhase").orEmpty()
        assumeTrue(phase in setOf("seed", "recover"))
        val token = arguments.getString("managedBrowserToken").orEmpty()
        require(token.matches(Regex("[a-f0-9]{32}")))
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val markers = AgentEncryptedDatabase(app, "public_managed_browser_restart_fixtures_v1")
        val run = "public-managed-browser-restart-$token"
        if (phase == "seed") {
            check(!markers.contains(token))
            val f = AgentManagedBrowserRecoveryDeviceTest().Fixture(run = run)
            LocalModelLoopContinuationStore(f.journal).prepare(f.id, f.request.goal, "public-scripted-profile", false,
                f.id.sourceMessageId, "a".repeat(64), "Public framework system")
            f.returned()
            f.controls.set(run, AgentTeamUserControl.STOP)
            assertFalse(AgentManagedBrowserControlEvents.reconcile(app, run, {}) { error("Public unavailable host") })
            // Keep startup recovery paused until the second test process verifies the persisted fixture.
            f.controls.set(run, AgentTeamUserControl.PAUSE)
            markers.writeString(token, JSONObject().put("pid", Process.myPid()).put("first", f.record.generation)
                .put("second", f.records[1].generation).toString())
            f.events.close()
            // Deliberately retain only this UUID-scoped fixture for a separate process.
        } else {
            val marker = JSONObject(markers.readString(token, ""))
            assertNotEquals(marker.getInt("pid"), Process.myPid())
            AgentManagedBrowserRecoveryDeviceTest().Fixture(run = run, reopen = true).use { f ->
                assertEquals(marker.getString("first"), f.record.generation)
                assertEquals(marker.getString("second"), f.records[1].generation)
                assertEquals(AgentTeamUserControl.PAUSE, f.controls.get(run))
                assertTrue(run in AgentManagedBrowserWakeIndex(app).pendingRuns())
                val saved = LocalModelLoopContinuationStore(f.journal).restore(f.id, "a".repeat(64))
                assertEquals(f.request.goal, saved.prompt)
                f.controls.set(run, AgentTeamUserControl.STOP)
                val wakes = mutableListOf<AgentBrowserUserRequest>()
                assertTrue(AgentManagedBrowserControlEvents.reconcile(app, run, wakes::add) {})
                assertEquals(2, wakes.size)
                for (record in wakes) {
                    assertTrue(AgentLocalBrowserRecovery.recover(app, record.key, record.generation) { _, _ -> error("No stopped inference") })
                    assertEquals("cancelled", f.ledger.findOwner(record.managedOwnerRunId)?.response?.taskStatus)
                    assertFalse(f.browsers.load(record.key)!!.pendingRunWake)
                }
                assertTrue(AgentManagedBrowserWakeIndex(app).records(run).none())
            }
            markers.remove(token)
        }
    }
}
