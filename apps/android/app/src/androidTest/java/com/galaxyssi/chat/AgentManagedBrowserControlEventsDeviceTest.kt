package com.galaxyssi.chat

import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Public host-control fixtures only; no model goal, provider call or real authentication. */
@RunWith(AndroidJUnit4::class)
class AgentManagedBrowserControlEventsDeviceTest {
    private val app get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture() = AgentManagedBrowserRecoveryDeviceTest().Fixture()

    @Test fun resumeEmitsAnImmediateExactRunWakeButPauseDoesNotPollOrWakeAnActiveHandoff() {
        fixture().use { f ->
            val changes = mutableListOf<String>()
            val controls = AgentTeamDurableControl(app, changes::add)
            controls.set(f.run, AgentTeamUserControl.PAUSE)
            f.returned()
            val wakes = mutableListOf<AgentBrowserUserRequest>()
            assertTrue(AgentManagedBrowserControlEvents.reconcile(app, f.run, wakes::add) { error("Paused release") })
            assertTrue(wakes.isEmpty())
            assertTrue(changes.isEmpty())
            controls.set(f.run, AgentTeamUserControl.RUN)
            assertEquals(listOf(f.run), changes)
            assertTrue(AgentManagedBrowserControlEvents.reconcile(app, f.run, wakes::add) { error("RUN release") })
            assertEquals(listOf(f.browsers.load(f.record.key)), wakes)
            assertTrue(f.browsers.load(f.record.key)!!.pendingRunWake)
            assertEquals("active", f.browsers.load(f.records[1].key)?.state)
        }
    }

    @Test fun stoppingActiveHandoffsSettlesCancellationAndRetriesHostCleanupWithoutTouchingAnotherRun() = runBlocking {
        fixture().use { f -> fixture().use { other ->
            f.controls.set(f.run, AgentTeamUserControl.STOP)
            val wakes = mutableListOf<AgentBrowserUserRequest>()
            assertFalse(AgentManagedBrowserControlEvents.reconcile(app, f.run, wakes::add) { error("Public host unavailable") })
            assertEquals(2, wakes.size)
            assertTrue(wakes.all { it.state == "interrupted" && it.interruptionCode == "browser_owner_stopped" })
            assertEquals("active", other.browsers.load(other.record.key)?.state)
            assertThrows(AgentBrowserControlFailure::class.java) {
                AgentBrowserUserControl(app, execute = { error("Retired UI must not reach the host") }).snapshot(f.record, 320, 600)
            }
            // A later parent control write cannot resurrect this stopped browser generation.
            f.controls.set(f.run, AgentTeamUserControl.RUN)
            for (record in wakes) {
                assertTrue(AgentLocalBrowserRecovery.recover(app, record.key, record.generation) { _, _ -> error("Stopped inference") })
                assertEquals("cancelled", f.ledger.findOwner(record.managedOwnerRunId)?.response?.taskStatus)
                assertFalse(f.browsers.load(record.key)!!.pendingRunWake)
            }
            assertEquals(2, AgentManagedBrowserWakeIndex(app).records(f.run).count())
            var released = 0
            assertTrue(AgentManagedBrowserControlEvents.reconcile(app, f.run, { error("Already acknowledged") }) { released++ })
            assertEquals(2, released)
            assertTrue(AgentManagedBrowserWakeIndex(app).records(f.run).none())
        } }
    }

    @Test fun startupBackfillDoesNotReintroduceAnAcknowledgedReturnedWake() {
        fixture().use { f ->
            val returned = f.returned()
            f.browsers.acknowledgeRunWake(returned)
            assertFalse(AgentManagedBrowserWakeIndex(app).records(f.run).any { it.key == returned.key })
            val directory = File(app.cacheDir, "public-browser-index-${UUID.randomUUID()}")
            val isolated = AgentBrowserUserRequestStore(app, directory)
            try {
                isolated.save(checkNotNull(f.browsers.load(returned.key)))
                isolated.pendingWakes().toList()
                assertFalse(AgentManagedBrowserWakeIndex(app).records(f.run).any { it.key == returned.key })
            } finally {
                AtomicFile(File(directory, "${returned.key}.enc")).delete()
                directory.delete()
            }
        }
    }

    @Test fun aFreshControlEventReplacesAnOldDelayedObserverInsteadOfWaitingBehindIt() {
        fixture().use { f ->
            f.controls.set(f.run, AgentTeamUserControl.PAUSE)
            val manager = WorkManager.getInstance(app)
            val name = AgentManagedBrowserControlEvents.workName(f.run)
            val delayed = OneTimeWorkRequestBuilder<AgentManagedBrowserControlWorker>()
                .setInputData(workDataOf("run" to f.run)).setInitialDelay(1, TimeUnit.DAYS).build()
            try {
                manager.enqueueUniqueWork(name, ExistingWorkPolicy.KEEP, delayed).result.get(10, TimeUnit.SECONDS)
                AgentManagedBrowserControlEvents.enqueue(app, f.run).result.get(10, TimeUnit.SECONDS)
                val infos = manager.getWorkInfosForUniqueWork(name).get(10, TimeUnit.SECONDS)
                assertTrue(infos.none { it.id == delayed.id && !it.state.isFinished })
                val previous = manager.getWorkInfoById(delayed.id).get(10, TimeUnit.SECONDS)
                assertTrue(previous == null || previous.state == WorkInfo.State.CANCELLED)
                assertTrue(infos.any { it.id != delayed.id && it.state != WorkInfo.State.CANCELLED })
            } finally { manager.cancelUniqueWork(name).result.get(10, TimeUnit.SECONDS) }
        }
    }

    @Test fun stoppedHostReleaseNeverBecomesAReturnedControlOrBusinessSuccessEvent() {
        fixture().use { f ->
            f.controls.set(f.run, AgentTeamUserControl.STOP)
            val stopped = checkNotNull(f.browsers.interruptOwner(f.record))
            var calls = 0
            val host = AgentBrowserUserControl(app, execute = {
                calls++
                AgentRuntimeExecutionResponse(0, """{"ok":true,"result":{"control_owner":"agent"}}""", "", 1)
            }, enqueue = { error("Cleanup must not be a returned-control wake") })
            host.releaseStopped(stopped)
            assertEquals(1, calls)
            assertEquals(stopped, f.browsers.load(stopped.key))
            assertFalse(stopped.modelObservationCommitted)
            assertTrue(stopped.pendingRunWake)
            for (result in listOf("""{"control_owner":"user"}""", "{}")) {
                val unconfirmed = AgentBrowserUserControl(app, execute = {
                    AgentRuntimeExecutionResponse(0, """{"ok":true,"result":$result}""", "", 1)
                })
                val failure = assertThrows(AgentBrowserControlFailure::class.java) { unconfirmed.releaseStopped(stopped) }
                assertEquals("browser_control_release_unconfirmed", failure.code)
                assertEquals(stopped, f.browsers.load(stopped.key))
                assertTrue(AgentManagedBrowserWakeIndex(app).records(f.run).any { it.key == stopped.key })
            }
        }
    }

    @Test fun anOldGenerationCleanupCannotRemoveOrTargetAReplacementBrowserRequest() {
        fixture().use { f ->
            f.returned()
            val replacement = f.record.copy(generation = UUID.randomUUID().toString())
            f.browsers.save(replacement, replaceSettled = true)
            AgentManagedBrowserWakeIndex(app).released(f.record)
            assertEquals(replacement, AgentManagedBrowserWakeIndex(app).records(f.run).first { it.key == replacement.key })
            f.controls.set(f.run, AgentTeamUserControl.STOP)
            val wakes = mutableListOf<AgentBrowserUserRequest>()
            assertTrue(AgentManagedBrowserControlEvents.reconcile(app, f.run, wakes::add) {})
            assertEquals(replacement.generation, wakes.single { it.key == replacement.key }.generation)
        }
    }

    @Test fun failedControlEnqueuePreservesIntentAndExactPendingWakeForAnotherAttempt() {
        fixture().use { f ->
            f.controls.set(f.run, AgentTeamUserControl.PAUSE)
            f.returned()
            AgentTeamDurableControl(app) { error("Public enqueue unavailable") }.set(f.run, AgentTeamUserControl.RUN)
            assertEquals(AgentTeamUserControl.RUN, f.controls.get(f.run))
            assertThrows(IllegalStateException::class.java) {
                AgentManagedBrowserControlEvents.reconcile(app, f.run, { error("Public enqueue unavailable") }) {}
            }
            assertTrue(f.browsers.load(f.record.key)!!.pendingRunWake)
            val wakes = mutableListOf<AgentBrowserUserRequest>()
            assertTrue(AgentManagedBrowserControlEvents.reconcile(app, f.run, wakes::add) {})
            assertEquals(listOf(f.record.generation), wakes.map { it.generation })
        }
    }

    @Test fun aForeignIndexHintCannotAuthorizeAnotherRunOrReplaceAnEncryptedBrowserOwner() {
        fixture().use { f ->
            val rows = AgentEncryptedDatabase(app, "managed_browser_control_wakes_v1")
            val key = "run:${AgentNativeJsonCodec.sha256(f.run)}:${f.record.key}"
            rows.writeString(key, JSONObject().put("run", "foreign-run").put("key", f.record.key)
                .put("generation", f.record.generation).put("released", false).toString())
            try {
                assertThrows(IllegalStateException::class.java) {
                    AgentManagedBrowserControlEvents.reconcile(app, f.run, { error("Foreign wake") }) { error("Foreign release") }
                }
                assertEquals(f.record, f.browsers.load(f.record.key))
            } finally { rows.remove(key); AgentManagedBrowserWakeIndex(app).track(f.record) }
        }
    }

    @Test fun aRunWithMoreThanOneIndexPageRetiresEveryOriginalHandoffWithoutLoadingOtherRuns() {
        fixture().use { f ->
            val extra = (0 until 65).map { index ->
                val browser = "public-browser-$index"
                f.record.copy(key = AgentBrowserUserRequest.key(f.record.scope, browser), browserSessionId = browser,
                    generation = UUID.randomUUID().toString()).also(f.browsers::save)
            }
            try {
                assertEquals(67, AgentManagedBrowserWakeIndex(app).records(f.run).count())
                f.controls.set(f.run, AgentTeamUserControl.STOP)
                val wakes = mutableListOf<AgentBrowserUserRequest>()
                assertTrue(AgentManagedBrowserControlEvents.reconcile(app, f.run, wakes::add) {})
                assertEquals(67, wakes.map { it.key }.toSet().size)
                assertTrue(wakes.all { it.interruptionCode == "browser_owner_stopped" })
            } finally {
                extra.forEach {
                    AgentManagedBrowserWakeIndex(app).remove(it)
                    AtomicFile(File(app.filesDir, "browser-user-requests/${it.key}.enc")).delete()
                }
            }
        }
    }
}
