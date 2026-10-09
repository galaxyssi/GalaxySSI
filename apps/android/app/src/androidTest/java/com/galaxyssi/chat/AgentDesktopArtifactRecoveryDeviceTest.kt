package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.util.Base64
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/** Isolated file roots and preferences; never sends to a real Desktop. */
class AgentDesktopArtifactRecoveryDeviceTest {
    @Test fun missingFirstChunkRecoversOriginalAndStopsAfterCompletion() = fixture { f ->
        f.ingest(1); f.ingest(2)
        val before = f.chunk(1).readBytes()
        assertEquals(1, f.recover())
        assertEquals("[0]", f.requests.single().getJSONArray("missing_chunks").toString())
        assertEquals(0, f.recover())
        val result = f.ingest(0)
        assertTrue(result.completed)
        assertArrayEquals(before, f.bytes.copyOfRange(262144, 524288))
        assertArrayEquals(f.bytes, AttachmentLocalStore.openInput(File(f.files,
            "desktop-artifacts-v2/files/${f.id}.sasie")).use { it.readBytes() })
        assertEquals(0, f.recover(f.now + 600_000))
    }

    @Test fun offlineAndRevokedPairDoNotCreateRecoveryTraffic() = fixture { f ->
        f.ingest(1)
        assertEquals(0, f.recover(ready = false))
        assertEquals(0, f.recover(links = listOf(f.link.copy(paired = false))))
        assertTrue(f.requests.isEmpty())
        assertEquals(1, f.recover())
    }

    @Test fun retryStateSurvivesReopeningAndBacksOffWithoutAttemptCutoff() = fixture { f ->
        f.ingest(1)
        assertEquals(1, f.recover())
        assertEquals(0, f.recover(f.now + 29_000))
        assertEquals(1, f.recover(f.now + 30_000))
        assertEquals(0, f.recover(f.now + 89_000))
        assertEquals(1, f.recover(f.now + 90_000))
        assertEquals(300_000L, AgentDesktopArtifactRecovery.retryDelay(82))
        assertEquals(30_000L, AgentDesktopArtifactRecovery.retryDelay(1))
    }

    @Test fun taskIdentityMismatchCannotFetchFilesFromOtherConversation() = fixture { f ->
        f.ingest(1)
        AgentTaskIdentityStore.register(f.context, "desktop-test", 123,
            AgentTaskIdentity(f.link.routes.clientRouteId, "another-conversation", f.task, "another-turn"))
        assertEquals(0, f.recover())
        assertTrue(f.requests.isEmpty())
    }

    @Test fun existingPartialFilesRecoverOnlyWithUniqueRegisteredIdentity() = fixture { f ->
        AgentDesktopArtifactStore.ingest(f.context, f.payload(1))
        assertEquals(1, f.recover())
        val pending = f.requests.single()
        assertEquals(f.id, pending.getString("artifact_id"))
        assertEquals("[0,2]", pending.getJSONArray("missing_chunks").toString())
    }

    private fun fixture(block: (Fixture) -> Unit) {
        val f = Fixture()
        try { block(f) } finally { f.files.deleteRecursively(); f.preferences.forEach { it.edit().clear().commit() } }
    }

    private class Fixture {
        val target = InstrumentationRegistry.getInstrumentation().targetContext
        val suffix = UUID.randomUUID().toString()
        val files = File(target.cacheDir, "artifact-recovery-$suffix").apply { check(mkdirs()) }
        val preferences = mutableListOf<SharedPreferences>()
        val context = object : ContextWrapper(target) {
            override fun getFilesDir() = files
            override fun getApplicationContext(): Context = this
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
                target.getSharedPreferences("test-$suffix-$name", mode).also { preferences.add(it) }
        }
        val link = GalaxySSILinkProtocol.ServerLink("desktop-test", "Test", "remote", "desktop-test",
            GalaxySSILinkProtocol.Routes(GalaxySSILinkProtocol.newRouteId(), GalaxySSILinkProtocol.newLinkSecret(), "local", "remote"), true)
        val task = "artifact-test-$suffix"
        val bytes = ByteArray(534189) { (it % 251).toByte() }
        val uri = "galaxyssi-artifact://$task/outputs/result.bin"
        val id = hash("$uri\u0000${hash(bytes)}".toByteArray())
        val now = System.currentTimeMillis() + 20_000
        val requests = mutableListOf<JSONObject>()
        init { AgentTaskIdentityStore.register(context, "desktop-test", 123,
            AgentTaskIdentity(link.routes.clientRouteId, "conversation", task, "turn")) }
        fun chunk(index: Int) = File(files, "desktop-artifacts-v2/incoming/$id/$index.chunk.sasie")
        fun ingest(index: Int): AgentDesktopArtifactIngestResult {
            val payload = payload(index)
            return AgentDesktopArtifactStore.ingest(context, payload).also {
                if (!it.completed) AgentDesktopArtifactRecovery.remember(context, payload, link.desktopId)
            }
        }
        fun recover(at: Long = now, ready: Boolean = true, links: List<GalaxySSILinkProtocol.ServerLink> = listOf(link)) =
            AgentDesktopArtifactRecovery.recover(context, at, { ready }, links) { desktop, route, request ->
                assertEquals(link.desktopId, desktop); assertEquals(link.routes.clientRouteId, route)
                requests.add(JSONObject(request.toString())); true
            }
        fun payload(index: Int): JSONObject {
            val part = bytes.copyOfRange(index * 262144, minOf(bytes.size, (index + 1) * 262144))
            return JSONObject().put("type", "artifact_chunk").put("artifact_id", id).put("artifact_uri", uri)
                .put("task_id", task).put("name", "result.bin").put("mime_type", "application/octet-stream")
                .put("size_bytes", bytes.size).put("sha256", hash(bytes)).put("chunk_index", index)
                .put("chunk_count", 3).put("chunk_size_bytes", part.size).put("chunk_sha256", hash(part))
                .put("data_b64", Base64.encodeToString(part, Base64.NO_WRAP))
                .put("client_route_id", link.routes.clientRouteId).put("conversation_id", "conversation")
                .put("turn_id", "turn").put("contact_id", "desktop-test").put("source_message_id", "123")
        }
    }

    companion object {
        private fun hash(value: ByteArray) = MessageDigest.getInstance("SHA-256").digest(value).joinToString("") { "%02x".format(it) }
    }
}
