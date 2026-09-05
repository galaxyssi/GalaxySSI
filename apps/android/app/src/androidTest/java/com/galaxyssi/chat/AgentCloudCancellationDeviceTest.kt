package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Real device sockets and encrypted storage, no changes to user contacts or credentials. */
@RunWith(AndroidJUnit4::class)
class AgentCloudCancellationDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun request(server: MockWebServer, id: String) = ModelStreamRequest(id,
        ModelStreamProvider.OPENAI_COMPATIBLE, server.url("/").toString(), emptyMap(), "{\"messages\":[{\"role\":\"user\",\"content\":\"\u6d4b\u8bd5\u53d6\u6d88\u8bf7\u6c42\"}]}")

    @Test fun cancelledDispatchClosesSocketAndNeverPublishesOrRetries(): Unit = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            val id = AgentCloudDispatchIdentity(98765, "test-cloud", "test-conversation", "test-turn", "test-task", "test-action")
            val lease = AgentCloudDispatchRegistry.register(id)
            val client = OkHttpCloudModelStreamClient()
            var completed = false
            val worker = thread {
                try {
                    lease.runRequest { client.stream(request(server, "old")).collect() }
                    completed = lease.claimCompletion()
                } catch (_: CancellationException) { }
                finally { AgentCloudDispatchRegistry.release(id, lease) }
            }
            try {
                assertNotNull(withContext(Dispatchers.IO) { server.takeRequest(3, TimeUnit.SECONDS) })
                val start = SystemClock.elapsedRealtime()
                assertTrue(AgentCloudDispatchRegistry.cancel(AgentActionResult(id.actionId, true, "", mapOf(
                    "resource_location" to "cloud", "source_message_id" to id.sourceMessageId.toString(),
                    "contact_id" to id.contactId, "conversation_id" to id.conversationId,
                    "turn_id" to id.turnId, "task_id" to id.taskId))))
                withContext(Dispatchers.IO) { worker.join(2_000) }
                assertFalse(worker.isAlive)
                assertFalse(completed)
                assertEquals(1, server.requestCount)
                assertTrue(client.activeRequestIds().isEmpty())
                Log.i("GalaxySSICancelTest", "dispatch_cancel_ms=${SystemClock.elapsedRealtime() - start}")
            } finally { lease.cancel(); withContext(Dispatchers.IO) { worker.join(2_000) } }
        }
    }

    @Test fun bodyReadCancellationKeepsSecondRequestWorking(): Unit = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("data: [DONE]\n\n").setBodyDelay(3, TimeUnit.SECONDS))
            val client = OkHttpCloudModelStreamClient()
            val connected = CompletableDeferred<Unit>()
            val old = launch { client.stream(request(server, "old")).onEach {
                if (it is ModelStreamEvent.Connected) connected.complete(Unit)
            }.collect() }
            withTimeout(3_000) { connected.await() }
            server.enqueue(MockResponse().setBody("data: [DONE]\n\n"))
            val other = async { client.stream(request(server, "other")).toList() }
            val start = SystemClock.elapsedRealtime()
            withTimeout(2_000) { old.cancelAndJoin() }
            Log.i("GalaxySSICancelTest", "body_cancel_ms=${SystemClock.elapsedRealtime() - start}")
            assertTrue(withTimeout(3_000) { other.await() }.any { it is ModelStreamEvent.Completed })
            assertTrue(client.activeRequestIds().isEmpty())
        }
    }

    @Test fun cancelledAttemptRemainsCancelledAfterEncryptedDatabaseReopen() {
        val name = "cloud-cancel-test-${UUID.randomUUID()}.db"
        val identity = AgentProviderAttemptReport(901, "test-conversation", "test-turn", "test-task", "test-action")
        try {
            withStore(name) { store ->
                val journal = AgentProviderAttemptJournal(store, "test-phone", identity)
                val tracker = AgentProviderAttemptTracker(identity, journal::checkpoint)
                tracker.start("request", "test-cloud", "provider", "model", 100)
                tracker.progress("connected", 10)
                tracker.cancel(200)
                journal.finish(tracker.report, cancelled = true)
            }
            withStore(name) { store ->
                val journal = AgentProviderAttemptJournal(store, "test-phone", identity)
                assertEquals("cancelled", journal.restore()!!.attempts.single().state)
                assertEquals(AgentRunControlState.CANCELLED, store.snapshot(journal.runId)?.state)
            }
        } finally { context.deleteDatabase(name) }
    }

    @Test fun compatibilityTransportCancellationStopsHttp(): Unit = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            val call = okhttp3.OkHttpClient().newCall(okhttp3.Request.Builder().url(server.url("/")).build())
            val owner = launch { CloudBlockingRequestCancellation.run {
                call.executeCancellable(CloudBlockingRequestCancellation.token()) { it.body?.string() }
            } }
            assertNotNull(withContext(Dispatchers.IO) { server.takeRequest(3, TimeUnit.SECONDS) })
            val start = SystemClock.elapsedRealtime()
            withTimeout(2_000) { owner.cancelAndJoin() }
            assertTrue(call.isCanceled())
            Log.i("GalaxySSICancelTest", "compatibility_cancel_ms=${SystemClock.elapsedRealtime() - start}")
        }
    }

    private fun withStore(name: String, block: (AgentRunEventStore) -> Unit) {
        val store = AgentRunEventStore(context, name)
        try { block(store) } finally { store.close() }
    }
}
