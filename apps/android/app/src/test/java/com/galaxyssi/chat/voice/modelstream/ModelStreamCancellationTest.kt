package com.galaxyssi.chat.voice.modelstream

import com.galaxyssi.chat.CloudBlockingRequestCancellation
import com.galaxyssi.chat.executeCancellable
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class ModelStreamCancellationTest {
    private lateinit var server: MockWebServer
    private val client = OkHttpCloudModelStreamClient()
    @Before fun setup() { server = MockWebServer(); server.start() }
    @After fun close() { server.shutdown() }
    private fun request(id: String = "request", transport: ModelStreamTransport = ModelStreamTransport.SSE) =
        ModelStreamRequest(id, ModelStreamProvider.OPENAI_COMPATIBLE, server.url("/").toString(), emptyMap(), "{}", transport)
    private suspend fun received() {
        assertNotNull(withContext(Dispatchers.IO) { server.takeRequest(2, TimeUnit.SECONDS) })
    }
    private fun done() = MockResponse().setBody("data: [DONE]\n\n")

    @Test fun collectorCancellationClosesConnectionWaitingForHeaders() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val reader = launch { client.stream(request()).collect() }
        received()
        withTimeout(1_500) { reader.cancelAndJoin() }
        assertTrue(client.activeRequestIds().isEmpty())
    }

    @Test fun collectorCancellationClosesBlockedBodyRead() = runBlocking {
        server.enqueue(done().setBodyDelay(3, TimeUnit.SECONDS))
        val connected = CompletableDeferred<Unit>()
        val reader = launch { client.stream(request()).onEach { if (it is ModelStreamEvent.Connected) connected.complete(Unit) }.collect() }
        withTimeout(2_000) { connected.await() }
        withTimeout(1_500) { reader.cancelAndJoin() }
        assertTrue(client.activeRequestIds().isEmpty())
    }

    @Test fun explicitCancellationIsTerminalNotRetryableAndDoesNotComplete() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val events = async { client.stream(request()).toList() }
        received()
        client.cancel("request", ModelStreamCancelReason.USER_STOP)
        val result = withTimeout(1_500) { events.await() }
        val error = result.filterIsInstance<ModelStreamEvent.Failed>().single().error
        assertEquals("CANCELLED", error.code)
        assertEquals("USER_STOP", error.message)
        assertFalse(error.retryable)
        assertFalse(result.any { it is ModelStreamEvent.Completed })
    }

    @Test fun cancellingOneSocketLeavesAnotherRequestUsable() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val old = launch { client.stream(request("old")).collect() }
        received()
        server.enqueue(done())
        val next = async { client.stream(request("other")).toList() }
        withTimeout(1_500) { old.cancelAndJoin() }
        assertEquals(1, withTimeout(2_000) { next.await() }.count { it is ModelStreamEvent.Completed })
    }

    @Test fun duplicateActiveIdIsRejectedWithoutInterruptingOriginal() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val old = launch { client.stream(request()).collect() }
        received()
        val duplicate = client.stream(request()).toList().filterIsInstance<ModelStreamEvent.Failed>().single()
        assertEquals("DUPLICATE_REQUEST_ID", duplicate.error.code)
        assertTrue(old.isActive)
        withTimeout(1_500) { old.cancelAndJoin() }
        server.enqueue(done())
        assertTrue(client.stream(request()).toList().any { it is ModelStreamEvent.Completed })
    }

    @Test fun firstEventConsumerReleasesReaderInsteadOfLeavingSocketOpen() = runBlocking {
        server.enqueue(done().setBodyDelay(3, TimeUnit.SECONDS))
        val event = withTimeout(1_500) { client.stream(request()).first() }
        assertTrue(event is ModelStreamEvent.Connected)
        assertTrue(client.activeRequestIds().isEmpty())
    }

    @Test fun nonStreamingJsonReadAlsoHonoursCollectorCancellation() = runBlocking {
        server.enqueue(MockResponse().setBody("{}").setBodyDelay(3, TimeUnit.SECONDS))
        val connected = CompletableDeferred<Unit>()
        val reader = launch { client.stream(request(transport = ModelStreamTransport.COMPLETE_JSON))
            .onEach { if (it is ModelStreamEvent.Connected) connected.complete(Unit) }.collect() }
        withTimeout(2_000) { connected.await() }
        withTimeout(1_500) { reader.cancelAndJoin() }
        assertTrue(client.activeRequestIds().isEmpty())
    }

    @Test fun compatibilityClientCancellationClosesBlockingExecute() = runBlocking {
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        val call = OkHttpClient().newCall(Request.Builder().url(server.url("/")).build())
        val request = launch { CloudBlockingRequestCancellation.run {
            call.executeCancellable(CloudBlockingRequestCancellation.token()) { it.body?.string() }
        } }
        received()
        withTimeout(1_500) { request.cancelAndJoin() }
        assertTrue(call.isCanceled())
        assertFalse(CloudBlockingRequestCancellation.token().isCancellationRequested)
    }

    @Test fun compatibilityTokenIsClearedAfterSuccessAndFailure() = runBlocking {
        assertEquals("ok", CloudBlockingRequestCancellation.run { "ok" })
        try { CloudBlockingRequestCancellation.run { error("expected") } } catch (_: IllegalStateException) { }
        assertFalse(CloudBlockingRequestCancellation.run { CloudBlockingRequestCancellation.token().isCancellationRequested })
    }

    @Test fun requestPreparationDoesNotRunOnCollectorThread() = runBlocking {
        server.enqueue(done())
        val collectorThread = Thread.currentThread()
        var setupThread: Thread? = null
        val observedHeaders = object : AbstractMap<String, String>() {
            override val entries: Set<Map.Entry<String, String>>
                get() { setupThread = Thread.currentThread(); return emptySet() }
        }
        client.stream(request().copy(headers = observedHeaders)).collect()
        assertNotNull(setupThread)
        assertNotEquals(collectorThread, setupThread)
    }
}
