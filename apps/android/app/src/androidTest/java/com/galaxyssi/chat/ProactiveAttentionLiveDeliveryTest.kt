package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in observation of the user's enabled public attention; never inserts a synthetic finding. */
@RunWith(AndroidJUnit4::class)
class ProactiveAttentionLiveDeliveryTest {
    @Test fun enabledAttentionDeliversARealFinding() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_live_delivery") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = ProactiveAttentionStore(context).preferences()
        assumeTrue(preferences.configured && preferences.enabled && preferences.allowPairedModel)
        val repository = GlobalAgentRepository(context)
        val started = System.currentTimeMillis()
        ActivityScenario.launch(MainActivity::class.java).use {
            ProactiveAttentionCoordinator(context).reconcile()
            if (InstrumentationRegistry.getArguments().getString("attention_retry_source_reads") == "true") {
                repository.researchTasks().filter { ProactiveAttentionPolicy.isAttention(it) &&
                    it.status == GlobalResearchTaskStatus.WAITING_FOR_RESOURCE &&
                    it.lastError == "attention_source_read_unavailable" }.forEach { task ->
                    repository.updateResearchTask(task.id) { it.copy(nextAttemptAtMillis = 0L) }
                }
            }
            AndroidCognitionScheduler.requestAttention(context)
            val deadline = SystemClock.elapsedRealtime() + 600_000L
            while (SystemClock.elapsedRealtime() < deadline) {
                ProactiveAttentionDiagnosticsTest().inspectLiveAttentionState()
                if (repository.proactiveMessages().any { message -> ProactiveAttentionPolicy.isAttention(message) &&
                    message.createdAtMillis >= started && message.status == GlobalProactiveMessageStatus.DELIVERED }) return
                SystemClock.sleep(10_000L)
            }
            assertTrue("No real finding delivered in the observation window; inspect exported diagnostics", false)
        }
    }
}
