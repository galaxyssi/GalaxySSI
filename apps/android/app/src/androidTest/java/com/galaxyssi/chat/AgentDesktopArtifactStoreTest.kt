package com.galaxyssi.chat

import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.security.MessageDigest

@RunWith(AndroidJUnit4::class)
class AgentDesktopArtifactStoreTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @After
    fun cleanUp() {
        AgentDesktopArtifactStore.clear(context)
    }

    @Test
    fun reassemblesAndVerifiesArtifactBeforeExposingContentUri() {
        val bytes = ByteArray(300_000) { index -> (index % 251).toByte() }
        val fullDigest = sha256(bytes)
        val artifactUri = "galaxyssi-artifact://task/outputs/result.bin"
        val artifactId = sha256("$artifactUri\u0000$fullDigest".toByteArray())
        val first = bytes.copyOfRange(0, 256 * 1024)
        val second = bytes.copyOfRange(first.size, bytes.size)

        val pending = AgentDesktopArtifactStore.ingest(
            context,
            payload(artifactId, artifactUri, fullDigest, bytes.size, 0, 2, first, 500_000)
        )
        assertFalse(pending.completed)
        val complete = AgentDesktopArtifactStore.ingest(
            context,
            payload(artifactId, artifactUri, fullDigest, bytes.size, 1, 2, second, 500_000)
        )
        assertTrue(complete.completed)

        val resolved = AgentDesktopArtifactStore.resolveBlock(
            context,
            AgentRichBlock(
                id = "artifact",
                type = AgentRichBlockType.FILE,
                title = "result.bin",
                text = "outputs \u00b7 488.3 KB",
                uri = artifactUri,
                mimeType = "application/octet-stream",
                metadata = mapOf(
                    "transport" to "encrypted-fragmented",
                    "category" to "outputs",
                    "size" to "488.3 KB",
                    "size_bytes" to "500000"
                )
            )
        )
        assertEquals("content", android.net.Uri.parse(resolved.uri).scheme)
        assertEquals("outputs \u00b7 293.0 KB", resolved.text)
        assertEquals("300000", resolved.metadata["size_bytes"])
        assertEquals("500000", resolved.metadata["original_size_bytes"])
        val restored = context.contentResolver.openInputStream(android.net.Uri.parse(resolved.uri))
            ?.use { it.readBytes() }
        assertTrue(bytes.contentEquals(restored))
    }

    private fun payload(
        artifactId: String,
        artifactUri: String,
        fullDigest: String,
        fullSize: Int,
        index: Int,
        count: Int,
        chunk: ByteArray,
        originalSize: Int = fullSize
    ): JSONObject = JSONObject()
        .put("type", "artifact_chunk")
        .put("artifact_id", artifactId)
        .put("artifact_uri", artifactUri)
        .put("task_id", "task")
        .put("name", "result.bin")
        .put("mime_type", "application/octet-stream")
        .put("size_bytes", fullSize)
        .put("sha256", fullDigest)
        .put("original_size_bytes", originalSize)
        .put("original_sha256", fullDigest)
        .put("chunk_index", index)
        .put("chunk_count", count)
        .put("chunk_size_bytes", chunk.size)
        .put("chunk_sha256", sha256(chunk))
        .put("data_b64", Base64.encodeToString(chunk, Base64.NO_WRAP))

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
}
