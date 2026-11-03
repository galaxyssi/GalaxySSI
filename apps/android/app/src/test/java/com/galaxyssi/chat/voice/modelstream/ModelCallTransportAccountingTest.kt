package com.galaxyssi.chat.voice.modelstream

import kotlinx.coroutines.*
import kotlinx.coroutines.flow.toList
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit

class ModelCallTransportAccountingTest {
    private fun request(server: MockWebServer, sink: ModelCallAuditSink) = ModelStreamRequest("round-0",
        ModelStreamProvider.OPENAI_COMPATIBLE, server.url("/chat/completions").toString(), emptyMap(),
        """{"model":"requested","messages":[]}""", auditSink = sink)
    private fun response() = MockResponse().setHeader("Content-Type", "text/event-stream").setBody(
        "data: {\"id\":\"response-one\",\"model\":\"reported\",\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\n" +
            "data: {\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":3,\"total_tokens\":13}}\n\n" +
            "data: [DONE]\n\n")
    private fun client() = OkHttpCloudModelStreamClient(onTiming = {})
    private fun strictSink(rows: MutableList<JSONObject>) = object : ModelCallAuditSink {
        override fun singleHttpRequest() = true
        override fun write(receipt: JSONObject) { rows += JSONObject(receipt.toString()) }
    }

    @Test fun trialTransportDoesNotFollowRedirects() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", server.url("/final")))
            server.enqueue(response())
            val rows = CopyOnWriteArrayList<JSONObject>()
            val events = client().stream(request(server, strictSink(rows))).toList()
            assertTrue(events.any { it is ModelStreamEvent.Failed })
            assertEquals(1, server.requestCount)
            assertTrue(rows.first().getBoolean("single_http_request"))
            assertEquals(1L, rows.last().getLong("http_request_attempts"))
        }
    }

    @Test fun trialTransportBlocksAutomatic503FollowUpBeforeSecondHttpRequest() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setResponseCode(503).setHeader("Retry-After", "0"))
            server.enqueue(response())
            val rows = CopyOnWriteArrayList<JSONObject>()
            val events = client().stream(request(server, strictSink(rows))).toList()
            assertTrue(events.any { it is ModelStreamEvent.Failed })
            assertEquals(1, server.requestCount)
            assertEquals("failed", rows.last().getString("status"))
            assertEquals(1L, rows.last().getLong("http_request_attempts"))
        }
    }

    @Test fun trialDenialAndUnreadablePolicyFailBeforeNetwork() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val denied = client().stream(request(server, ModelCallAuditSink {
                throw ModelCallAdmissionDenied("request_admissions_exhausted")
            })).toList().filterIsInstance<ModelStreamEvent.Failed>().single().error
            assertEquals(ModelCallAdmissionDenied.CODE, denied.code)
            assertFalse(denied.retryable)
            val broken = object : ModelCallAuditSink {
                override fun singleHttpRequest(): Boolean = error("corrupt policy")
                override fun write(receipt: JSONObject) = error("must not admit")
            }
            assertEquals("ACCOUNTING_UNAVAILABLE", client().stream(request(server, broken)).toList()
                .filterIsInstance<ModelStreamEvent.Failed>().single().error.code)
            assertEquals(0, server.requestCount)
        }
    }

    @Test fun transportRecordsAdmissionBeforeIoAndSettlesExactlyOnce() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(response())
            val rows = CopyOnWriteArrayList<JSONObject>()
            val events = client().stream(request(server, ModelCallAuditSink {
                if (it.getString("status") == "started") assertEquals(0, server.requestCount)
                rows += JSONObject(it.toString())
            })).toList()
            assertEquals("hello", events.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text })
            assertEquals(2, rows.size)
            assertTrue(rows.last().getBoolean("tokens_complete"))
            assertEquals(200, rows.last().getInt("http_status"))
            assertEquals("reported", rows.last().getString("reported_model"))
        }
    }

    @Test fun httpFailuresAreRetainedAndNotMeasuredAsZero() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setResponseCode(503).setBody("unavailable"))
            val rows = CopyOnWriteArrayList<JSONObject>()
            val events = client().stream(request(server, ModelCallAuditSink(rows::add))).toList()
            assertTrue(events.any { it is ModelStreamEvent.Failed })
            assertEquals("failed", rows.last().getString("status"))
            assertEquals(503, rows.last().getInt("http_status"))
            assertFalse(rows.last().getBoolean("tokens_complete"))
            assertTrue(rows.last().isNull("cost_micros"))
        }
    }

    @Test fun localAdmissionFailureDoesNotSpendAndSettlementFailureDoesNotRetry() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(response())
            val blocked = client().stream(request(server, ModelCallAuditSink { error("storage unavailable") })).toList()
            assertEquals("ACCOUNTING_UNAVAILABLE", blocked.filterIsInstance<ModelStreamEvent.Failed>().single().error.code)
            assertEquals(0, server.requestCount)
            val completed = client().stream(request(server, ModelCallAuditSink {
                if (it.getString("status") != "started") error("final receipt write failed")
            })).toList()
            assertEquals(1, completed.count { it is ModelStreamEvent.Completed })
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun retryOfSameLogicalRoundHasDistinctCallIdentity() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            repeat(2) { server.enqueue(response()) }
            val rows = CopyOnWriteArrayList<JSONObject>()
            val transport = client()
            repeat(2) { transport.stream(request(server, ModelCallAuditSink(rows::add))).toList() }
            val starts = rows.filter { it.getString("status") == "started" }
            assertEquals(2, starts.map { it.getString("call_id") }.distinct().size)
            assertEquals(1, starts.map { it.getString("request_id") }.distinct().size)
        }
    }

    @Test fun collectorCancellationRetainsOneIncompleteTerminalReceipt() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(response().setBodyDelay(1, TimeUnit.SECONDS))
            val rows = CopyOnWriteArrayList<JSONObject>()
            val job = launch { client().stream(request(server, ModelCallAuditSink(rows::add))).toList() }
            withTimeout(5_000) { while (server.requestCount == 0) delay(10) }
            job.cancelAndJoin()
            assertEquals(2, rows.size)
            assertEquals("cancelled", rows.last().getString("status"))
            assertFalse(rows.last().getBoolean("tokens_complete"))
        }
    }

    @Test fun redirectsDoNotMakeOnlyTheLastHttpResponseLookLikeCompleteAccounting() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", server.url("/final")))
            server.enqueue(response())
            val rows = CopyOnWriteArrayList<JSONObject>()
            val events = client().stream(request(server, ModelCallAuditSink(rows::add))).toList()
            assertTrue(events.any { it is ModelStreamEvent.Completed })
            assertEquals(2L, rows.last().getLong("http_request_attempts"))
            assertFalse(rows.last().getBoolean("tokens_complete"))
            assertEquals(13L, rows.last().getJSONObject("usage").getLong("total_tokens"))
        }
    }

    @Test fun duplicateProviderSequenceCannotPoisonAcceptedUsage() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream").setBody(
                "data: {\"sequence\":1,\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":1}}\n\n" +
                    "data: {\"sequence\":1,\"usage\":{\"prompt_tokens\":-1,\"completion_tokens\":999}}\n\n" +
                    "data: [DONE]\n\n"))
            val rows = CopyOnWriteArrayList<JSONObject>()
            client().stream(request(server, ModelCallAuditSink(rows::add))).toList()
            assertTrue(rows.last().getBoolean("tokens_complete"))
            assertEquals(3L, rows.last().getJSONObject("usage").getLong("total_tokens"))
        }
    }
}
