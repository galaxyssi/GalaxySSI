package com.signalasi.chat

import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CancellableOkHttpCallTest {
    @Test
    fun returnsResponseWhenRequestCompletes() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("complete"))
            val request = Request.Builder().url(server.url("/model")).build()

            val body = OkHttpClient().newCall(request).executeCancellable(
                AgentNativeToolCancellationToken.NONE
            ) { response ->
                response.body?.string().orEmpty()
            }

            assertEquals("complete", body)
        }
    }

    @Test
    fun cancellationInterruptsBlockedRequest() = runBlocking {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
            val cancellation = AgentNativeToolCancellationSource()
            val request = Request.Builder().url(server.url("/blocked-model")).build()
            val pending = async(Dispatchers.IO) {
                OkHttpClient().newCall(request).executeCancellable(cancellation.token) { response ->
                    response.body?.string().orEmpty()
                }
            }

            assertNotNull(server.takeRequest(2, TimeUnit.SECONDS))
            val startedAt = System.nanoTime()
            cancellation.cancel()
            val error = try {
                withTimeout(2_000L) { pending.await() }
                null
            } catch (caught: CancellationException) {
                caught
            }

            assertTrue(error is CancellationException)
            assertTrue(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt) < 2_000L)
        }
    }

    @Test
    fun preCancelledRequestDoesNotReachServer() {
        MockWebServer().use { server ->
            val cancellation = AgentNativeToolCancellationSource().apply { cancel() }
            val request = Request.Builder().url(server.url("/never-started")).build()
            val error = runCatching {
                OkHttpClient().newCall(request).executeCancellable(cancellation.token) { response ->
                    response.body?.string().orEmpty()
                }
            }.exceptionOrNull()

            assertTrue(error is CancellationException)
            assertEquals(0, server.requestCount)
        }
    }
}
