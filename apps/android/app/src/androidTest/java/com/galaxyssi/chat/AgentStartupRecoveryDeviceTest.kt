package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkManager
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentStartupRecoveryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun encryptedWorkspaceAndPlanReconcileOnceAcrossReopen() {
        val id = "startup-test-${UUID.randomUUID()}"
        val database = "startup-workspaces-$id"
        val scope = "task:$id"
        val store = EncryptedAgentWorkspaceStore(context, database)
        val session = SharedPreferencesAgentSessionStore(context, scope)
        val journal = EncryptedAgentPlanNodeJournal(context)
        try {
            val screen = ScreenContext(foregroundApp = "Test", pageTitle = "Test")
            val actions = (0 until 2048).map { index -> AgentAction(
                id = "node-$index", kind = AgentActionKind.CALL_NATIVE_TOOL,
                target = "test.read", risk = AgentRisk.LOW,
                status = if (index == 2047) AgentActionStatus.PROPOSED else AgentActionStatus.COMPLETED,
                description = "\u8bfb\u53d6\u8282\u70b9 $index",
                parameters = mapOf("depends_on" to if (index > 0) "node-${index - 1}" else ""),
                requiresConfirmation = false) }
            session.save(AgentSessionSnapshot(id, AgentPhase.EXECUTING, "\u7ee7\u7eed\u4efb\u52a1", screen,
                AgentPlan("\u7ee7\u7eed\u4efb\u52a1", screen, emptyList(), actions, planId = id),
                emptyList(), null, processInstanceId = "old-process", updatedAtMillis = 1L))
            store.upsert(AgentWorkspace(id, id, id, id, status = AgentWorkspaceStatus.RUNNING))
            fun reconcile() = AgentColdBootRecoveryCoordinator.pauseInterruptedTasks(
                EncryptedAgentWorkspaceStore(context, database),
                { SharedPreferencesAgentSessionStore(context, "task:$it") },
                InMemoryAgentSessionStore(), journal, { emptySet() },
                AgentProcessIdentity.instanceId, System.currentTimeMillis(), "\u91cd\u542f\u540e\u6062\u590d")
            assertEquals(1, reconcile())
            val recovered = SharedPreferencesAgentSessionStore(context, scope).load()!!
            assertEquals(actions, recovered.currentPlan!!.actions)
            assertEquals("node-2047", recovered.currentPlan.runnableActions().single().id)
            assertNotNull(AgentLongTaskRecoveryPolicy.decide(store.find(id)!!, recovered))
            assertEquals(0, reconcile())
            assertEquals(recovered, session.load())
            assertEquals(1, store.find(id)!!.eventJournal.size)
        } finally {
            session.clear()
            store.clear()
        }
    }

    @Test fun productionStartupWorkerCompletesItsDurableRequest() {
        AgentStartupRecovery.enqueue(context).result.get(30, TimeUnit.SECONDS)
        awaitStartupCompletion()
    }

    @Test fun bootBroadcastCompletedRecoveryWithoutAnExplicitTestEnqueue() {
        org.junit.Assume.assumeTrue(
            InstrumentationRegistry.getArguments().getString("verify_startup_boot") == "true")
        awaitStartupCompletion()
    }

    private fun awaitStartupCompletion() {
        val manager = WorkManager.getInstance(context)
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(90)
        while (System.nanoTime() < deadline) {
            val work = manager.getWorkInfosForUniqueWork("galaxyssi-startup-recovery-v1")
                .get(10, TimeUnit.SECONDS)
            assertTrue(work.count { !it.state.isFinished } <= 1)
            val bootCount = android.provider.Settings.Global.getInt(context.contentResolver,
                android.provider.Settings.Global.BOOT_COUNT, -1)
            assertTrue(bootCount >= 0)
            // Android can still be delivering boot broadcasts while old work is already finished.
            if (work.any { it.state == androidx.work.WorkInfo.State.SUCCEEDED &&
                    it.outputData.getInt("boot_count", -2) == bootCount }) {
                return
            }
            Thread.sleep(100)
        }
        fail("Startup work did not finish; inspect WorkManager and recovery logs")
    }
}
