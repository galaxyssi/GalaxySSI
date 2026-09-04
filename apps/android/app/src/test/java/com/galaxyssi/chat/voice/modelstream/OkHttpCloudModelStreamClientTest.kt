package com.galaxyssi.chat.voice.modelstream

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class OkHttpCloudModelStreamClientTest {
    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `openai sse emits utf8 deltas immediately and completes after done`() = runBlocking {
        val body = buildString {
            append("data: {\"choices\":[{\"delta\":{\"content\":\"Hello \"}}]}\n\n")
            append("data: {\"choices\":[{\"delta\":{\"content\":\"\u4e16\u754c\"}}]}\n\n")
            append("data: {\"choices\":[],\"usage\":{\"prompt_tokens\":4,\"completion_tokens\":2}}\n\n")
            append("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n")
            append("data: [DONE]\n\n")
        }
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "text/event-stream")
                .setChunkedBody(body, 1)
        )

        val events = client().stream(request()).toList()
        val text = events.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text }

        assertEquals("Hello \u4e16\u754c", text)
        assertTrue(events.first() is ModelStreamEvent.Connected)
        assertEquals(1, events.count { it is ModelStreamEvent.Completed })
        assertEquals(1, events.count { it is ModelStreamEvent.Usage })
        assertFalse(events.any { it is ModelStreamEvent.Failed })
    }

    @Test
    fun `character and word events retain exact order`() = runBlocking {
        val body = buildString {
            append("data: {\"choices\":[{\"delta\":{\"content\":\"A\"}}]}\n\n")
            append("data: {\"choices\":[{\"delta\":{\"content\":\" quick\"}}]}\n\n")
            append("data: {\"choices\":[{\"delta\":{\"content\":\" reply\"}}]}\n\n")
            append("data: [DONE]\n\n")
        }
        server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream").setBody(body))

        val events = client().stream(request()).toList()

        assertEquals(
            listOf("A", " quick", " reply"),
            events.filterIsInstance<ModelStreamEvent.TextDelta>().map { it.text }
        )
    }

    @Test
    fun `first delta carries its actual arrival time`() = runBlocking {
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "text/event-stream")
                .setBody("data: {\"choices\":[{\"delta\":{\"content\":\"first\"}}]}\n\ndata: [DONE]\n\n")
        )
        var now = 40L
        val events = OkHttpCloudModelStreamClient(elapsedRealtimeMs = { now++ })
            .stream(request())
            .toList()

        assertEquals(40L, events.filterIsInstance<ModelStreamEvent.Connected>().single().connectedAtElapsedMs)
        assertEquals(41L, events.filterIsInstance<ModelStreamEvent.TextDelta>().single().receivedAtElapsedMs)
    }

    @Test
    fun `tool arguments split across frames assemble once and duplicate provider sequence is ignored`() = runBlocking {
        val body = buildString {
            append("data: {\"sequence\":1,\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"name\":\"web_search\",\"arguments\":\"{\\\"q\\\":\"}}]}}]}\n\n")
            append("data: {\"sequence\":1,\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"name\":\"web_search\",\"arguments\":\"{\\\"q\\\":\"}}]}}]}\n\n")
            append("data: {\"sequence\":2,\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"news\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n")
            append("data: [DONE]\n\n")
        }
        server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream").setBody(body))

        val events = client().stream(request()).toList()
        val assembler = ToolCallDeltaAssembler()
        events.filterIsInstance<ModelStreamEvent.ToolCallDelta>().forEach { assembler.accept(it.payload) }

        assertEquals(2, events.count { it is ModelStreamEvent.ToolCallDelta })
        val call = assembler.completedCalls().single()
        assertEquals("call-1", call.callId)
        assertEquals("web_search", call.name)
        assertEquals("{\"q\":\"news\"}", call.argumentsJson)
    }

    @Test
    fun `anthropic empty initial tool input joins partial json without corruption`() = runBlocking {
        val body = buildString {
            append("event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tool-1\",\"name\":\"web_search\",\"input\":{}}}\n\n")
            append("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"q\\\":\\\"news\\\"}\"}}\n\n")
            append("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
        }
        server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream").setBody(body))

        val events = client().stream(request(provider = ModelStreamProvider.ANTHROPIC)).toList()
        val assembler = ToolCallDeltaAssembler()
        events.filterIsInstance<ModelStreamEvent.ToolCallDelta>().forEach { assembler.accept(it.payload) }

        assertEquals("{\"q\":\"news\"}", assembler.completedCalls().single().argumentsJson)
    }

    @Test
    fun `repeated append-only argument characters are preserved`() {
        val assembler = ToolCallDeltaAssembler()
        listOf(
            "{\"query\":\"he",
            "l",
            "l",
            "o\",\"filters\":{\"recent\":true",
            "}",
            "}"
        ).forEach { delta ->
            assembler.accept(ToolCallPayload("call-repeat", 0, "web_search", delta))
        }

        assertEquals(
            "{\"query\":\"hello\",\"filters\":{\"recent\":true}}",
            assembler.completedCalls().single().argumentsJson
        )
    }

    @Test
    fun `snapshot tool arguments replace the prior snapshot`() {
        val assembler = ToolCallDeltaAssembler()
        assembler.accept(
            ToolCallPayload(
                "gemini-0",
                0,
                "web_search",
                "{\"query\":\"old\"}",
                ToolCallArgumentsMode.SNAPSHOT
            )
        )
        assembler.accept(
            ToolCallPayload(
                "gemini-0",
                0,
                "web_search",
                "{\"query\":\"new\"}",
                ToolCallArgumentsMode.SNAPSHOT
            )
        )

        assertEquals("{\"query\":\"new\"}", assembler.completedCalls().single().argumentsJson)
    }

    @Test
    fun `partial stream ending without terminal is marked interrupted`() = runBlocking {
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "text/event-stream")
                .setBody("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n")
        )

        val events = client().stream(request()).toList()
        val failure = events.filterIsInstance<ModelStreamEvent.Failed>().single()

        assertEquals("STREAM_INTERRUPTED", failure.error.code)
        assertTrue(failure.error.partialResponse)
        assertFalse(events.any { it is ModelStreamEvent.Completed })
    }

    @Test
    fun `http error body is preserved as a structured failure`() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(429)
                .setBody("{\"error\":{\"message\":\"rate limited\"}}")
        )

        val failure = client().stream(request()).toList()
            .filterIsInstance<ModelStreamEvent.Failed>()
            .single()

        assertEquals(429, failure.error.httpStatus)
        assertEquals("rate limited", failure.error.message)
        assertTrue(failure.error.retryable)
    }

    @Test
    fun `server error is retryable and a new request id starts cleanly`() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(503).setBody("{\"error\":{\"message\":\"temporarily unavailable\"}}"))
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "text/event-stream")
                .setBody("data: {\"choices\":[{\"delta\":{\"content\":\"recovered\"}}]}\n\ndata: [DONE]\n\n")
        )

        val first = client().stream(request(requestId = "request-1")).toList()
        val retry = client().stream(request(requestId = "request-2")).toList()

        val failure = first.filterIsInstance<ModelStreamEvent.Failed>().single()
        assertEquals(503, failure.error.httpStatus)
        assertTrue(failure.error.retryable)
        assertEquals("request-2", retry.filterIsInstance<ModelStreamEvent.TextDelta>().single().requestId)
        assertEquals("recovered", retry.filterIsInstance<ModelStreamEvent.TextDelta>().single().text)
    }

    @Test
    fun `complete json transport keeps non streaming providers usable`() = runBlocking {
        server.enqueue(
            MockResponse().setBody(
                "{\"choices\":[{\"message\":{\"content\":\"complete reply\"},\"finish_reason\":\"stop\"}]}"
            )
        )

        val events = client().stream(request(transport = ModelStreamTransport.COMPLETE_JSON)).toList()

        assertEquals(
            "complete reply",
            events.filterIsInstance<ModelStreamEvent.TextDelta>().single().text
        )
        assertTrue(events.any { it is ModelStreamEvent.Completed })
    }

    @Test
    fun `anthropic and gemini provider events normalize to the same text protocol`() = runBlocking {
        val anthropic = buildString {
            append("event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":3}}}\n\n")
            append("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Claude\"}}\n\n")
            append("event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":1}}\n\n")
            append("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n")
        }
        val gemini = buildString {
            append("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Gemini\"}]}}]}\n\n")
            append("data: {\"candidates\":[{\"content\":{\"parts\":[]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":2,\"candidatesTokenCount\":1}}\n\n")
        }
        server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream").setBody(anthropic))
        server.enqueue(MockResponse().setHeader("Content-Type", "text/event-stream").setBody(gemini))
        val anthropicEvents = client().stream(request(provider = ModelStreamProvider.ANTHROPIC)).toList()
        val geminiEvents = client().stream(request(provider = ModelStreamProvider.GEMINI)).toList()

        assertEquals("Claude", anthropicEvents.filterIsInstance<ModelStreamEvent.TextDelta>().single().text)
        assertEquals("Gemini", geminiEvents.filterIsInstance<ModelStreamEvent.TextDelta>().single().text)
        assertTrue(anthropicEvents.any { it is ModelStreamEvent.Completed })
        assertTrue(geminiEvents.any { it is ModelStreamEvent.Completed })
    }

    @Test
    fun `active request can be cancelled without being marked complete`() = runBlocking {
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "text/event-stream")
                .setBodyDelay(1, TimeUnit.SECONDS)
                .setBody("data: [DONE]\n\n")
        )
        val connected = CompletableDeferred<Unit>()
        val client = client()
        val collection = async {
            client.stream(request()).onEach {
                if (it is ModelStreamEvent.Connected) connected.complete(Unit)
            }.toList()
        }
        connected.await()
        client.cancel("request-1", ModelStreamCancelReason.USER_STOP)
        val events = collection.await()

        assertEquals("CANCELLED", events.filterIsInstance<ModelStreamEvent.Failed>().single().error.code)
        assertFalse(events.any { it is ModelStreamEvent.Completed })
    }

    @Test
    fun `cancelling after partial text never emits completed`() = runBlocking {
        server.enqueue(
            MockResponse()
                .setHeader("Content-Type", "text/event-stream")
                .setBody(
                    "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n" +
                        "data: [DONE]\n\n"
                )
                .throttleBody(1, 20, TimeUnit.MILLISECONDS)
        )
        val partial = CompletableDeferred<Unit>()
        val client = client()
        val collection = async {
            client.stream(request()).onEach {
                if (it is ModelStreamEvent.TextDelta) partial.complete(Unit)
            }.toList()
        }
        partial.await()
        client.cancel("request-1", ModelStreamCancelReason.USER_STOP)
        val events = collection.await()

        val failure = events.filterIsInstance<ModelStreamEvent.Failed>().single()
        assertEquals("CANCELLED", failure.error.code)
        assertTrue(failure.error.partialResponse)
        assertFalse(events.any { it is ModelStreamEvent.Completed })
    }

    private fun client() = OkHttpCloudModelStreamClient()

    private fun request(
        requestId: String = "request-1",
        provider: ModelStreamProvider = ModelStreamProvider.OPENAI_COMPATIBLE,
        transport: ModelStreamTransport = ModelStreamTransport.SSE
    ) = ModelStreamRequest(
        requestId = requestId,
        provider = provider,
        endpoint = server.url("/model").toString(),
        headers = emptyMap(),
        bodyJson = "{}",
        transport = transport
    )
}
