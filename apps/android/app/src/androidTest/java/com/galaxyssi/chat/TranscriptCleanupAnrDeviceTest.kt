package com.galaxyssi.chat

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TranscriptCleanupAnrDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun processCleanupAndNewConversationDoNotWaitForLearning() {
        val key = "cleanup-anr-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val conversation = store.createConversation(key, privateMode = true)
        val ids = mutableListOf(conversation.id)
        val executor = Executors.newSingleThreadExecutor()
        try {
            repeat(3) { store.append(AgentTranscriptRole.PROCESS, "$key-$it", "cleanup-$it", conversationId = conversation.id) }
            // The public state exercises PROCESS filtering, not the private-session early return.
            store.setPrivateMode(conversation.id, false)
            val entries = store.list(conversation.id).associateBy { it.dedupeKey }
            withBlocked(repositoryLock()) {
                val started = SystemClock.elapsedRealtime()
                val cleanup = executor.submit<Boolean> {
                    store.deleteEntry(entries.getValue("cleanup-0").id) &&
                        store.deleteByDedupeKey(conversation.id, "cleanup-1") &&
                        store.removeExactText("$key-2") == 1
                }
                assertTrue("Cleanup must not wait for the global repository", cleanup.get(2, TimeUnit.SECONDS))
                val created = CountDownLatch(1)
                Handler(Looper.getMainLooper()).post {
                    try { ids += store.createConversation(key, privateMode = true).id }
                    finally { created.countDown() }
                }
                assertTrue("New conversation must remain responsive", created.await(2, TimeUnit.SECONDS))
                report("cleanup_and_new_conversation_ms=${SystemClock.elapsedRealtime() - started}")
            }
            assertTrue(store.list(conversation.id).isEmpty())
        } finally {
            executor.shutdownNow()
            executor.awaitTermination(5, TimeUnit.SECONDS)
            ids.forEach { store.setPrivateMode(it, true); store.deleteConversation(it) }
        }
    }

    @Test fun processDeletionNeverPublishesLearningRetraction() {
        withBlocked(repositoryLock()) {
            val entry = AgentTranscriptEntry(id = "synthetic", role = AgentTranscriptRole.PROCESS,
                text = "progress", conversationId = "synthetic", timestampMillis = 1L)
            val executor = Executors.newSingleThreadExecutor()
            try {
                assertFalse(executor.submit<Boolean> { GlobalConversationEventBus.publishTranscriptEntryDeleted(
                    context, AgentConversation(id = "synthetic", title = "Test", createdAt = 1L, updatedAt = 1L), entry)
                }.get(1, TimeUnit.SECONDS))
            } finally { executor.shutdownNow() }
        }
    }

    @Test fun completedLedgerMigrationDoesNotWaitForWriterMonitor() {
        val store = AgentRunEventStore(context)
        val ledger = requireNotNull(AgentRunEventStore::class.java.getDeclaredField("ledger").apply {
            isAccessible = true
        }.get(store))
        withBlocked(ledger) {
            val executor = Executors.newSingleThreadExecutor()
            try {
                assertNotNull(executor.submit<AgentRunEventStore> { AgentRunEventStore(context) }.get(1, TimeUnit.SECONDS))
            } finally { executor.shutdownNow() }
        }
    }

    private fun repositoryLock(): Any = requireNotNull(GlobalAgentRepository::class.java.getDeclaredField("STORE_LOCK")
        .apply { isAccessible = true }.get(null))

    private fun withBlocked(lock: Any, block: () -> Unit) {
        val acquired = CountDownLatch(1)
        val release = CountDownLatch(1)
        val holder = thread(name = "synthetic-storage-stall") {
            synchronized(lock) { acquired.countDown(); release.await(8, TimeUnit.SECONDS) }
        }
        try { assertTrue(acquired.await(2, TimeUnit.SECONDS)); block() }
        finally { release.countDown(); holder.join(10_000) }
    }

    private fun report(value: String) = instrumentation.sendStatus(0, Bundle().apply { putString("stream", "$value\n") })
}
