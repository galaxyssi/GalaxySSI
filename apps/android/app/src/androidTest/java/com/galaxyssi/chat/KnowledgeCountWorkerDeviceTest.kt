package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.WorkInfo
import androidx.work.WorkManager
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeCountWorkerDeviceTest {
    @Test fun durableMaintenanceCompletesWithoutInstallingOrEnablingAnEncoder() {
        val f = KnowledgeCountTestFixture(spec = KnowledgeEmbeddingModel.spec)
        val namespace = f.name.removeSuffix(".db")
        val controller = KnowledgeSemanticController(f.context, namespace, f.name, f.legacy)
        KnowledgeSemanticRuntime.registerTest(controller)
        try {
            controller.awaitReady()
            f.seed(131); f.index(); f.downgrade()
            controller.refreshCounts(schedule = false)
            assertTrue(controller.state.countsPending)
            assertFalse(controller.state.installed); assertFalse(controller.state.enabled)
            repeat(50) { controller.requestCounts() }
            val manager = WorkManager.getInstance(f.context)
            await {
                val work = manager.getWorkInfosForUniqueWork(KnowledgeCountWork.name(namespace)).get()
                assertTrue(work.count { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED } <= 1)
                !controller.state.countsPending && controller.state.indexedChunks == 131L && controller.runningWork.get() == 0 &&
                    work.isNotEmpty() && work.all { it.state.isFinished }
            }
            f.verify()
            assertFalse(controller.state.installed); assertFalse(controller.state.enabled)
            assertNull(controller.searchSession()); assertFalse(controller.modelFile.exists())
            assertEquals("", controller.state.countsError)
        } finally {
            KnowledgeSemanticRuntime.removeTest(namespace)
            await { controller.runningWork.get() == 0 && WorkManager.getInstance(f.context)
                .getWorkInfosForUniqueWork(KnowledgeCountWork.name(namespace)).get().all { it.state.isFinished } }
            f.close()
            AgentEncryptedPreferences(f.context, "knowledge-model-$namespace").clear()
        }
    }
    private fun await(condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 60_000
        while (SystemClock.elapsedRealtime() < until) { if (condition()) return; SystemClock.sleep(25) }
        fail("Isolated count worker did not settle")
    }
}
