package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Runtime wiring checks, not evidence of real-model autonomous website completion. */
@RunWith(AndroidJUnit4::class)
class AgentInteractiveBrowserDeviceTest {
    @Test fun observedWakeCannotBeAcknowledgedBeforeTheBoundJournalObservationIsCommitted() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scope = AgentNativeJsonCodec.sha256(UUID.randomUUID().toString())
        val key = AgentBrowserUserRequest.key(scope, "public-observation-fixture")
        val record = AgentBrowserUserRequest(key, "first", scope, "public-runtime", "public-conversation", "public-turn",
            "public-caller", "public-files", "public-observation-fixture", "public-page", "public-handoff", "returned",
            taskId = "public-turn", modelLoopId = "public-loop", runWorkspaceId = "public-run",
            runSessionId = "public-owner", runPlanningBinding = "public-planning")
        val store = AgentBrowserUserRequestStore(context)
        val file = File(context.filesDir, "browser-user-requests/$key.enc")
        try {
            store.save(record)
            assertFalse(store.acknowledgeObservedRunWake(record))
            assertTrue(store.current(key, "first").pendingRunWake)
            store.markObservationCommitted(record)
            val reloaded = AgentBrowserUserRequestStore(context)
            assertTrue(reloaded.current(key, "first").modelObservationCommitted)
            assertTrue(reloaded.current(key, "first").pendingRunWake)
            assertTrue(reloaded.acknowledgeObservedRunWake(record))
            assertFalse(reloaded.current(key, "first").pendingRunWake)
            assertThrows(IllegalArgumentException::class.java) {
                reloaded.save(record.copy(generation = "second", modelObservationCommitted = true), replaceSettled = true)
            }
            val next = record.copy(generation = "second")
            reloaded.save(next, replaceSettled = true)
            reloaded.markObservationCommitted(record)
            assertFalse(reloaded.acknowledgeObservedRunWake(record))
            assertTrue(reloaded.current(key, "second").pendingRunWake)
            assertFalse(reloaded.current(key, "second").modelObservationCommitted)
        } finally { android.util.AtomicFile(file).delete() }
    }

    @Test fun durableReturnWorkerAcknowledgesADeletedRunWithoutCreatingAnotherTask() {
        acknowledgesDeletedRun("returned")
    }

    @Test fun durableInterruptionWorkerAcknowledgesADeletedRunWithoutCreatingAnotherTask() {
        acknowledgesDeletedRun("interrupted")
    }

    private fun acknowledgesDeletedRun(state: String) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scope = AgentNativeJsonCodec.sha256(UUID.randomUUID().toString())
        val key = AgentBrowserUserRequest.key(scope, "public-deleted-run")
        val record = AgentBrowserUserRequest(key, UUID.randomUUID().toString(), scope,
            "public-runtime", "public-conversation", "public-turn", "public-caller", "public-files",
            "public-deleted-run", "public-page", "public-handoff", state, taskId = "public-turn",
            modelLoopId = "public-loop", runWorkspaceId = "public-deleted-${UUID.randomUUID()}",
            runSessionId = "public-owner", runPlanningBinding = "public-planning",
            interruptionCode = if (state == "interrupted") "browser_host_restarted" else "")
        val store = AgentBrowserUserRequestStore(context)
        val file = File(context.filesDir, "browser-user-requests/$key.enc")
        try {
            store.save(record)
            AgentLongTaskRecoveryScheduler.enqueueBrowserEvent(context, record)!!.result.get(15, java.util.concurrent.TimeUnit.SECONDS)
            val deadline = android.os.SystemClock.elapsedRealtime() + 15_000
            while (!store.current(key, record.generation).runWakeAcknowledged &&
                android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(100)
            assertTrue(store.current(key, record.generation).runWakeAcknowledged)
            assertNull(AgentTaskRuntime.supervisor(context).findWorkspace(record.runWorkspaceId))
        } finally {
            androidx.work.WorkManager.getInstance(context).cancelUniqueWork(
                AgentLongTaskRecoveryScheduler.browserEventWorkName(record)).result.get(15, java.util.concurrent.TimeUnit.SECONDS)
            android.util.AtomicFile(file).delete()
        }
    }

    @Test fun returnedRunWakeSurvivesStoreReloadAndAnOldAcknowledgementCannotConsumeANewGeneration() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scope = AgentNativeJsonCodec.sha256(UUID.randomUUID().toString())
        val key = AgentBrowserUserRequest.key(scope, "public-return-fixture")
        val returned = AgentBrowserUserRequest(key, "first", scope, "public-runtime", "public-conversation",
            "public-turn", "public-caller", "public-files", "public-return-fixture", "public-page", "public-handoff",
            "returned", taskId = "public-turn", modelLoopId = "public-loop",
            runWorkspaceId = "public-supervised-run", runSessionId = "public-run-owner",
            runPlanningBinding = "public-planning-binding")
        val file = File(context.filesDir, "browser-user-requests/$key.enc")
        try {
            AgentBrowserUserRequestStore(context).save(returned)
            val reloaded = AgentBrowserUserRequestStore(context)
            assertTrue(reloaded.pendingWakes().any { it == returned })
            assertFalse(file.readBytes().toString(Charsets.UTF_8).contains("public-supervised-run"))
            reloaded.acknowledgeRunWake(returned)
            assertFalse(reloaded.pendingWakes().any { it.key == key })
            assertTrue(reloaded.current(key, "first").runWakeAcknowledged)
            val next = returned.copy(generation = "second")
            reloaded.save(next, replaceSettled = true)
            reloaded.acknowledgeRunWake(returned)
            assertTrue(AgentBrowserUserRequestStore(context).current(key, "second").pendingRunWake)
        } finally { android.util.AtomicFile(file).delete() }
    }

    @Test fun userControlAuthorityAndOriginalRunBindingSurviveReloadWithoutPlaintextFiles() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scope = AgentNativeJsonCodec.sha256(mapOf("public_fixture" to UUID.randomUUID().toString()))
        val key = AgentBrowserUserRequest.key(scope, "public-browser-fixture")
        val record = AgentBrowserUserRequest(key, "first", scope, "public-agent", "public-conversation", "public-turn",
            "public-caller", "public-workspace", "public-browser-fixture", "public-page", "public-handoff", "active",
            taskId = "public-task", modelLoopId = "public-loop")
        val file = File(context.filesDir, "browser-user-requests/$key.enc")
        try {
            val capability = AgentBrowserHostAuthority.token(context, scope)
            assertEquals(capability, AgentBrowserHostAuthority.token(context, scope))
            assertNotEquals(capability, AgentBrowserHostAuthority.token(context, "0".repeat(64)))
            AgentBrowserUserRequestStore(context).save(record)
            val reloaded = AgentBrowserUserRequestStore(context)
            assertEquals(record, reloaded.current(key, "first"))
            assertFalse(file.readBytes().toString(Charsets.UTF_8).contains("public-conversation"))
            assertFalse(file.readBytes().toString(Charsets.UTF_8).contains(capability))
            val changed = assertThrows(AgentBrowserControlFailure::class.java) { reloaded.save(record.copy(taskId = "another-task")) }
            assertEquals("browser_user_request_binding_changed", changed.code)
            assertEquals(record, reloaded.current(key, "first"))
            val stale = assertThrows(AgentBrowserControlFailure::class.java) { reloaded.current(key, "older-generation") }
            assertEquals("browser_user_request_stale", stale.code)
            assertEquals(false, stale.details["executed"])
            assertThrows(IllegalStateException::class.java) { reloaded.save(record.copy(generation = "second"), replaceSettled = true) }
            reloaded.save(record.copy(state = "returned"))
            reloaded.save(record.copy(generation = "second"), replaceSettled = true)
            assertThrows(AgentBrowserControlFailure::class.java) { reloaded.current(key, "first") }
            assertThrows(IllegalStateException::class.java) { reloaded.save(record.copy(state = "returned")) }
            val info = context.packageManager.getActivityInfo(
                android.content.ComponentName(context, AgentBrowserUserControlActivity::class.java), 0)
            assertFalse(info.exported)
            val defaults = context.getSharedPreferences("browser_host_authority", android.content.Context.MODE_PRIVATE)
            assertFalse(defaults.getString("master", "").orEmpty().contains(capability))
        } finally {
            android.util.AtomicFile(file).delete()
        }
    }

    @Test fun apkContainsTheExactInteractiveDriverEntrypoints() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val engine = context.assets.open("interactive-browser/browser-session-engine.cjs").bufferedReader().use { it.readText() }
        val cli = context.assets.open("interactive-browser/browser-session-cli.cjs").bufferedReader().use { it.readText() }
        val userControl = context.assets.open("interactive-browser/browser-user-control.cjs").bufferedReader().use { it.readText() }
        val supervisor = context.assets.open("interactive-browser/browser-service-supervisor.cjs").bufferedReader().use { it.readText() }
        val receipts = context.assets.open("interactive-browser/browser-operation-receipts.cjs").bufferedReader().use { it.readText() }
        assertTrue(engine.contains("class BrowserSessions"))
        assertTrue(engine.contains("page_observation_stale"))
        assertTrue(engine.contains("beginHumanControl"))
        assertTrue(engine.contains("browser_user_control_active"))
        assertTrue(engine.contains("authentication_verified: false"))
        assertTrue(cli.contains("consumeRequestEnvironment"))
        assertTrue(cli.contains("browser_host_control_required"))
        assertTrue(cli.contains("browser_driver_changed"))
        assertTrue(userControl.contains("class BrowserUserControl"))
        assertTrue(supervisor.contains("class BrowserServiceExitMonitor"))
        assertTrue(supervisor.contains("child.once('exit'"))
        assertTrue(cli.contains("'supervise'"))
        assertTrue(cli.contains("receipts.status(request.input.request_id)"))
        assertTrue(receipts.contains("class BrowserOperationReceipts"))
        assertEquals(5, AgentInteractiveBrowserTools.stageHelpers(context).size)
    }

    @Test fun lostBrowserResponseExposesTheSameOperationIdUsedByTheRuntime() {
        val scope = AgentNativeToolInvocationContext(sessionId = "public-receipt-agent",
            conversationId = "public-receipt-conversation", invocationId = UUID.randomUUID().toString(),
            idempotencyKey = "public-receipt-${UUID.randomUUID()}")
        var request: AgentRuntimeExecutionRequest? = null
        val registry = AgentNativeToolRegistry().registerAll(AgentInteractiveBrowserTools.definitions({
            request = it
            AgentRuntimeExecutionResponse(1, "", "private-fixture-diagnostic", 1)
        }))
        val result = registry.invoke(AgentInteractiveBrowserTools.ACT, mapOf("operation" to "click"), scope)
        assertEquals("browser_result_unobserved", result.error?.code)
        assertEquals(true, result.error?.details?.get("outcome_unknown"))
        assertEquals(request!!.secretEnvironment["GALAXYSSI_BROWSER_OPERATION_ID"], result.error?.details?.get("request_id"))
        assertEquals("operation_status", result.error?.details?.get("reconciliation_operation"))
        assertFalse(result.toJson().contains("private-fixture-diagnostic"))
        assertEquals(AgentInteractiveBrowserTools.operationId(scope), result.error?.details?.get("request_id"))
    }

    @Test fun publicMissingSessionProbeRunsThroughThePhoneRuntimeAndReturnsRecoveryEvidence() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("browser_runtime_probe") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val registry = AgentNativeToolRegistry().registerAll(AgentInteractiveBrowserTools.definitions(context))
        val result = registry.invoke(AgentInteractiveBrowserTools.OBSERVE,
            mapOf("operation" to "observe", "session_id" to "public-not-created", "page_id" to "public-not-created"),
            AgentNativeToolInvocationContext(conversationId = "public-browser-runtime-probe",
                sessionId = "public-browser-runtime-probe", turnId = "public-browser-runtime-probe",
                attributes = mapOf("workspace_id" to "public-browser-runtime-probe", "permission_mode" to "full_access")))
        println("PUBLIC_BROWSER_RUNTIME_PROBE status=${result.status} code=${result.error?.code}")
        assertFalse(result.isSuccess)
        assertTrue("Unexpected runtime blocker: ${result.error?.code}",
            result.error?.code in setOf("browser_runtime_missing", "session_lost"))
        assertEquals(false, result.error?.details?.get("goal_terminal"))
    }
}
