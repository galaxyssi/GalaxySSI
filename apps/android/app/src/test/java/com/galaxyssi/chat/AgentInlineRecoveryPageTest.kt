package com.galaxyssi.chat

import com.galaxyssi.chat.metrics.AgentRecoveryTiming
import java.util.Base64
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentInlineRecoveryPageTest {
    private fun fields() = JSONObject().put("client_route_id", "route").put("conversation_id", "conversation")
        .put("task_id", "task").put("turn_id", "turn").put("contact_id", "contact")
        .put("source_message_id", "42").put("agent_id", "codex").put("execution_generation", 2)
        .put("expected_status", "completed")
    private fun body(text: String = "\u6062\u590d\u7b54\u6848") = fields().put("type", "text")
        .put("task_status", "completed").put("content", text)
    private fun page(request: JSONObject, answer: JSONObject): JSONObject {
        val raw = answer.toString().toByteArray(Charsets.UTF_8)
        val index = request.getInt("page_index")
        val start = index * AgentResultRecoveryClient.PAGE_BYTES
        val bytes = raw.copyOfRange(start, minOf(raw.size, start + AgentResultRecoveryClient.PAGE_BYTES))
        return JSONObject(request.toString()).put("type", "agent_task_result_page").put("status", "ready")
            .put("sha256", AgentResultRecoveryClient.sha256(raw)).put("total_bytes", raw.size)
            .put("page_count", (raw.size + AgentResultRecoveryClient.PAGE_BYTES - 1) / AgentResultRecoveryClient.PAGE_BYTES)
            .put("page_sha256", AgentResultRecoveryClient.sha256(bytes))
            .put("data_b64", Base64.getEncoder().encodeToString(bytes))
    }
    private fun seed(answer: JSONObject = body()) = page(fields().put("request_id", "query").put("page_index", 0), answer)
        .put("desktop_id", "desktop")

    private class Checkpoint : AgentResultPageCheckpoint {
        var saved: AgentResultPageManifest? = null
        val chunks = mutableMapOf<Int, ByteArray>()
        val cleared = mutableListOf<String>()
        override fun manifest() = saved
        override fun read(manifest: AgentResultPageManifest, page: Int) =
            if (saved == manifest) chunks[page]?.copyOf() else null
        override fun write(manifest: AgentResultPageManifest, page: Int, bytes: ByteArray): Boolean {
            if (saved != null && saved != manifest) return false
            saved = manifest; chunks[page] = bytes.copyOf(); return true
        }
        override fun clear(digest: String) {
            cleared += digest
            if (saved?.digest == digest) { chunks.values.forEach { it.fill(0) }; chunks.clear(); saved = null }
        }
    }

    @Test fun authenticatedQueryAndSmallReplyNeedNoPagePublish(): Unit = runBlocking {
        val query = AgentRemoteRecoveryClient()
        val answer = body().put("rich_output", JSONObject().put("blocks", JSONArray()))
        val observations = query.query("desktop", "route", listOf(fields()), includeResultPage = true) { request ->
            assertTrue(request.getBoolean("include_result_page"))
            val nonce = request.getString("request_id")
            val observation = fields().put("status", "completed").put("result_page",
                page(fields().put("request_id", nonce).put("page_index", 0), answer))
            val response = JSONObject().put("request_id", nonce).put("client_route_id", "route")
                .put("items", JSONArray().put(observation))
            assertFalse(query.receive(response, "other-desktop"))
            query.receive(response, "desktop")
        }
        val result = AgentResultRecoveryClient().fetch("desktop", fields(),
            firstPage = observations.single().getJSONObject("result_page")) { error("No page request expected") }
        assertEquals(answer.getString("content"), result!!.getString("content"))
        assertEquals(answer.getJSONObject("rich_output").toString(), result.getJSONObject("rich_output").toString())
    }

    @Test fun metadataOnlyInspectionDropsUnsolicitedPages(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        val result = client.query("desktop", "route", listOf(fields())) { request ->
            assertFalse(request.has("include_result_page"))
            client.receive(JSONObject().put("request_id", request.getString("request_id")).put("client_route_id", "route")
                .put("items", JSONArray().put(fields().put("status", "completed").put("result_page", seed()))), "desktop")
        }
        assertFalse(result.single().has("result_page"))
    }

    @Test fun nestedQueryNonceIdentityDeviceAndGenerationAreBound() {
        val original = seed()
        for ((name, value) in (AgentResultRecoveryClient.FIELDS + listOf("type", "request_id", "desktop_id"))
                .map { it to "wrong" } + listOf("execution_generation" to 3, "page_index" to 1, "page_index" to false)) {
            val observation = fields().put("status", "completed")
                .put("result_page", JSONObject(original.toString()).put(name, value))
            assertNull(name, AgentResultRecoveryPageCodec.bindInline(observation, "desktop", "query"))
        }
        assertNull(AgentResultRecoveryPageCodec.bindInline(fields().put("status", "running")
            .put("result_page", original), "desktop", "query"))
        assertNull(AgentResultRecoveryPageCodec.bindInline(fields().put("status", "completed")
            .put("execution_generation", "invalid").put("result_page", seed().put("execution_generation", "invalid")),
            "desktop", "query"))
    }

    @Test fun multiplePagesReuseInlineFirstPageAndSaveCheckpoints(): Unit = runBlocking {
        val client = AgentResultRecoveryClient()
        val checkpoint = Checkpoint()
        val answer = body("\u4e2d\u6587".repeat(10000))
        val requested = mutableListOf<Int>()
        val result = client.fetch("desktop", fields(), checkpoint = checkpoint, firstPage = seed(answer)) { request ->
            requested += request.getInt("page_index")
            client.receive(page(request, answer), "desktop")
        }
        assertEquals((1 until checkpoint.saved!!.pages).toList(), requested)
        assertEquals(answer.getString("content"), result!!.getString("content"))
        assertEquals(checkpoint.saved!!.pages, checkpoint.chunks.size)
    }

    @Test fun malformedOptionalPagesFallBackBeforeCheckpointWrite(): Unit = runBlocking {
        for ((name, value) in listOf("data_b64" to "!!!", "data_b64" to "a".repeat(30000),
                "sha256" to "0".repeat(64), "page_sha256" to "0".repeat(64), "total_bytes" to 0,
                "page_count" to 2, "total_bytes" to "300", "desktop_id" to "other", "execution_generation" to true)) {
            val client = AgentResultRecoveryClient()
            val checkpoint = Checkpoint()
            var requests = 0
            val result = client.fetch("desktop", fields(), checkpoint = checkpoint, firstPage = seed().put(name, value)) {
                assertTrue(name, checkpoint.chunks.isEmpty())
                assertEquals(0, it.getInt("page_index")); requests++
                client.receive(page(it, body()), "desktop")
            }
            assertNotNull(name, result)
            assertEquals(name, 1, requests)
        }
    }

    @Test fun invalidMultiPageSeedManifestCannotPoisonFutureRecovery(): Unit = runBlocking {
        val client = AgentResultRecoveryClient()
        val checkpoint = Checkpoint()
        val answer = body("a".repeat(20000))
        val badDigest = "0".repeat(64)
        val requested = mutableListOf<Int>()
        val result = client.fetch("desktop", fields(), checkpoint = checkpoint,
            firstPage = seed(answer).put("sha256", badDigest)) { request ->
            requested += request.getInt("page_index")
            val response = if (request.optString("sha256") == badDigest)
                JSONObject(request.toString()).put("type", "agent_task_result_page").put("status", "unavailable")
            else page(request, answer)
            client.receive(response, "desktop")
        }
        assertEquals(listOf(1, 0, 1), requested)
        assertTrue(checkpoint.cleared.contains(badDigest))
        assertEquals(answer.getString("content"), result!!.getString("content"))
        assertNotEquals(badDigest, checkpoint.saved!!.digest)
    }

    @Test fun timeoutPreservesFirstPageForNextRecoveryAttempt(): Unit = runBlocking {
        val client = AgentResultRecoveryClient()
        val checkpoint = Checkpoint()
        val answer = body("a".repeat(20000))
        assertNull(client.fetch("desktop", fields(), checkpoint = checkpoint, firstPage = seed(answer), timeoutMillis = 5) { true })
        assertEquals(setOf(0), checkpoint.chunks.keys)
        assertTrue(checkpoint.cleared.isEmpty())
        val result = client.fetch("desktop", fields(), checkpoint = checkpoint) { request ->
            assertEquals(1, request.getInt("page_index"))
            client.receive(page(request, answer), "desktop")
        }
        assertEquals(answer.getString("content"), result!!.getString("content"))
    }

    @Test fun wrongInnerIdentityFallsBackWithoutPublishingForgedReply(): Unit = runBlocking {
        val client = AgentResultRecoveryClient()
        val checkpoint = Checkpoint()
        val forged = body().put("conversation_id", "other")
        var requests = 0
        val result = client.fetch("desktop", fields(), checkpoint = checkpoint, firstPage = seed(forged)) {
            requests++; client.receive(page(it, body()), "desktop")
        }
        assertEquals(1, requests)
        assertEquals("conversation", result!!.getString("conversation_id"))
        assertFalse(checkpoint.cleared.isEmpty())
    }

    @Test fun existingManifestIsNeverReplacedByDifferentInlineDigest(): Unit = runBlocking {
        val client = AgentResultRecoveryClient()
        val checkpoint = Checkpoint()
        val original = body()
        checkpoint.saved = AgentResultPageManifest.from(seed(original))
        var requests = 0
        val result = client.fetch("desktop", fields(), checkpoint = checkpoint, firstPage = seed(body("different"))) {
            assertEquals(checkpoint.saved!!.digest, it.getString("sha256"))
            requests++; client.receive(page(it, original), "desktop")
        }
        assertEquals(1, requests)
        assertEquals(original.getString("content"), result!!.getString("content"))
    }

    @Test fun localCancellationAndPrivateContextStopInlineConsumption(): Unit = runBlocking {
        for (privateContext in listOf(false, true)) {
            val fields = if (privateContext) fields().put("conversation_id", "global-cognition:local") else fields()
            val checkpoint = Checkpoint()
            assertNull(AgentResultRecoveryClient().fetch("desktop", fields, firstPage = seed(), checkpoint = checkpoint,
                stillPending = { privateContext }) { error("Must not publish") })
            assertTrue(checkpoint.chunks.isEmpty())
        }
    }

    @Test fun inlineConsumptionDoesNotManufactureNetworkPageTiming(): Unit = runBlocking {
        val stages = mutableListOf<String>()
        val timing = AgentRecoveryTiming({ _, stage, _, _, _ -> stages += stage })
        assertNotNull(AgentResultRecoveryClient().fetch("desktop", fields(), firstPage = seed(),
            checkpoint = Checkpoint(), timing = timing) { error("No network page call") })
        assertTrue(stages.contains("phone_recovery_body_finished"))
        assertTrue(stages.contains("phone_recovery_checkpoint_finished"))
        assertFalse(stages.any { it.startsWith("phone_recovery_page_") })
    }

    @Test fun decodedBuffersAreWipedOnClose() {
        val decoded = requireNotNull(AgentResultRecoveryPageCodec.decode(seed(), 0))
        assertTrue(decoded.bytes.any { it != 0.toByte() })
        decoded.close()
        assertTrue(decoded.bytes.all { it == 0.toByte() })
    }
}
