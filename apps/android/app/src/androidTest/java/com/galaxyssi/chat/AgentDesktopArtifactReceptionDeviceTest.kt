package com.galaxyssi.chat

import android.content.ContextWrapper
import android.util.Base64
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executor
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Real file/inbox persistence with isolated roots; never publishes to a user peer. */
class AgentDesktopArtifactReceptionDeviceTest {
    @Test fun rejectedReceiptRetainsFinalChunkAndReplaysWithoutRewritingFile() = fixture { f ->
        val body = f.payload("final", "receipt replay".toByteArray())
        val accepted = f.store(body)
        f.process(accepted.payload, receipt = { false })
        assertEquals(1, f.failures)
        assertTrue(f.inbox.isPending(accepted.payload))
        val file = File(f.files, "desktop-artifacts-v2/files/${body.getString("artifact_id")}.sasie")
        assertTrue(file.isFile)
        val hash = digest(file.readBytes())
        val modified = file.lastModified()

        val reopened = GalaxySSILinkInbox(f.database)
        val pending = JSONObject(reopened.pending().single().payload)
        var receipts = 0
        f.process(pending, receipt = {
            receipts++
            assertEquals(body.getString("sha256"), it.sha256)
            true
        })
        assertEquals(1, receipts)
        assertEquals(1, f.completions)
        assertTrue(reopened.pending().isEmpty())
        assertEquals(hash, digest(file.readBytes()))
        assertEquals(modified, file.lastModified())
    }

    @Test fun filesystemFailureDoesNotRetireChunkAndCanRecover() = fixture { f ->
        val body = f.payload("disk", "disk replay".toByteArray())
        val accepted = f.store(body)
        val blocker = File(f.files, "desktop-artifacts-v2").apply { writeText("not a directory") }
        var receipts = 0
        f.process(accepted.payload, receipt = { receipts++; true })
        assertEquals(0, receipts)
        assertEquals(1, f.failures)
        assertEquals(0, f.completions)
        assertTrue(f.inbox.isPending(accepted.payload))
        assertTrue(blocker.delete())
        f.process(JSONObject(GalaxySSILinkInbox(f.database).pending().single().payload),
            receipt = { receipts++; true })
        assertEquals(1, receipts)
        assertEquals(1, f.completions)
        assertTrue(f.inbox.pending().isEmpty())
    }

    @Test fun partialChunkCommitsWithoutClaimingWholeArtifactStored() = fixture { f ->
        val bytes = ByteArray(300_000) { (it % 251).toByte() }
        val first = f.payload("part-0", bytes, 0)
        val second = f.payload("part-1", bytes, 1)
        var receipts = 0
        f.process(f.store(first).payload, receipt = { receipts++; true })
        assertEquals(0, receipts)
        assertEquals(1, f.completions)
        assertTrue(f.inbox.pending().isEmpty())
        val final = f.store(second)
        f.process(final.payload, receipt = { false })
        assertTrue(f.inbox.isPending(final.payload))
        f.process(final.payload, receipt = { receipts++; true })
        assertEquals(1, receipts)
        assertEquals(2, f.completions)
        assertTrue(f.inbox.pending().isEmpty())
        val stored = File(f.files, "desktop-artifacts-v2/files/${first.getString("artifact_id")}.sasie")
        assertEquals(digest(bytes), digest(AttachmentLocalStore.openInput(stored).use { it.readBytes() }))
    }

    private fun fixture(test: (Fixture) -> Unit) {
        val f = Fixture()
        try { test(f) } finally {
            f.inbox.clear()
            f.database.clear()
            f.files.deleteRecursively()
        }
    }

    private class Fixture {
        private val target = InstrumentationRegistry.getInstrumentation().targetContext
        private val id = UUID.randomUUID().toString()
        val files = File(target.cacheDir, "artifact-reception-$id").apply { check(mkdirs()) }
        val context = object : ContextWrapper(target) {
            override fun getFilesDir(): File = files
            override fun getApplicationContext(): android.content.Context = this
        }
        val database = AgentEncryptedDatabase(target, "test_artifact_reception_$id")
        val inbox = GalaxySSILinkInbox(database)
        var completions = 0
        var failures = 0

        fun store(body: JSONObject): GalaxySSILinkInbox.Accepted = inbox.accept(
            GalaxySSILinkInbox.Peer("isolated-$id", "desktop-test", false),
            body.getString("message_id"), MqttImmutableContent.hash(body), body)

        fun process(body: JSONObject, receipt: (AgentDesktopArtifactIngestResult) -> Boolean) {
            AttachmentControlInbox(Executor(Runnable::run)).enqueue(
                body.getString(MqttImmutableContent.RECORD_KEY),
                { AgentDesktopArtifactReception.accept(context, body, receipt) },
                { assertTrue(inbox.complete(body)); completions++ },
                { failures++ })
        }

        fun payload(messageId: String, bytes: ByteArray, index: Int = 0): JSONObject {
            val size = 256 * 1024
            val chunk = bytes.copyOfRange(index * size, minOf(bytes.size, (index + 1) * size))
            val sha = digest(bytes)
            val uri = "galaxyssi-artifact://test-$id/outputs/result.bin"
            return JSONObject().put("type", "artifact_chunk").put("message_id", messageId)
                .put("artifact_id", digest("$uri\u0000$sha".toByteArray()))
                .put("artifact_uri", uri).put("task_id", "test-$id")
                .put("name", "result.bin").put("mime_type", "application/octet-stream")
                .put("size_bytes", bytes.size).put("sha256", sha)
                .put("chunk_index", index).put("chunk_count", (bytes.size + size - 1) / size)
                .put("chunk_size_bytes", chunk.size).put("chunk_sha256", digest(chunk))
                .put("data_b64", Base64.encodeToString(chunk, Base64.NO_WRAP))
        }
    }

    companion object {
        private fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(bytes).joinToString("") { "%02x".format(it) }
    }
}
