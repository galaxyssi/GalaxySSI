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
    private val fixtures = mutableMapOf<String, String>()
    private val recoveryConversations = mutableListOf<String>()

    @After
    fun cleanUp() {
        recoveryConversations.forEach { AgentTranscriptStore(context).deleteConversation(it) }
        val root = java.io.File(context.filesDir, "desktop-artifacts-v2")
        fixtures.forEach { (uri, id) ->
            java.io.File(root, "metadata/${sha256(uri.toByteArray())}.json").delete()
            java.io.File(root, "files/$id.sasie").delete()
            java.io.File(root, "incoming/$id").deleteRecursively()
        }
    }

    @Test
    fun reassemblesAndVerifiesArtifactBeforeExposingContentUri() {
        val bytes = ByteArray(300_000) { index -> (index % 251).toByte() }
        val fullDigest = sha256(bytes)
        val artifactUri = "galaxyssi-artifact://test-${java.util.UUID.randomUUID()}/outputs/result.bin"
        val artifactId = sha256("$artifactUri\u0000$fullDigest".toByteArray())
        fixtures[artifactUri] = artifactId
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
                    "sha256" to fullDigest,
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

    @Test
    fun compressedSourceIdentityResolvesAndSavesButMixedVersionsAreRejected() {
        val bytes = ByteArray(128) { it.toByte() }
        val digest = sha256(bytes)
        val originalDigest = sha256("original image".toByteArray())
        val uri = "galaxyssi-artifact://test-${java.util.UUID.randomUUID()}/outputs/compressed-regression.jpg"
        val id = sha256("$uri\u0000$digest".toByteArray())
        fixtures[uri] = id
        AgentDesktopArtifactStore.ingest(context,
            payload(id, uri, digest, bytes.size, 0, 1, bytes, 500)
                .put("original_sha256", originalDigest))
        val block = AgentRichBlock(id = "compressed", type = AgentRichBlockType.IMAGE,
            uri = uri, mimeType = "image/jpeg", metadata = mapOf(
                "artifact_id" to id, "sha256" to originalDigest, "size_bytes" to "500"))
        val resolved = AgentDesktopArtifactStore.resolveBlock(context, block)
        assertEquals("content", android.net.Uri.parse(resolved.uri).scheme)
        assertEquals(digest, resolved.metadata["sha256"])
        assertEquals("128", resolved.metadata["size_bytes"])
        assertEquals(resolved.uri, AgentDesktopArtifactStore.resolveBlock(context, resolved).uri)
        for (metadata in listOf(
            block.metadata + ("sha256" to sha256("wrong".toByteArray())),
            block.metadata + ("size_bytes" to "128"),
            block.metadata + ("artifact_id" to sha256("other".toByteArray())),
            block.metadata + ("blob_turn_id" to "another-turn")
        )) {
            val invalid = block.copy(metadata = metadata)
            assertEquals(uri, AgentDesktopArtifactStore.resolveBlock(context, invalid).uri)
            assertTrue(AgentDesktopArtifactStore.saveToDownloads(context, invalid).isFailure)
        }
        val saved = AgentDesktopArtifactStore.saveToDownloads(context, block)
        assertTrue(saved.toString(), saved.isSuccess)
        val metadata = java.io.File(context.filesDir,
            "desktop-artifacts-v2/metadata/${sha256(uri.toByteArray())}.json")
        val destination = android.net.Uri.parse(JSONObject(metadata.readText()).getString("saved_uri"))
        try {
            val copied = context.contentResolver.openInputStream(destination)!!.use { it.readBytes() }
            assertEquals(digest, sha256(copied))
        } finally {
            context.contentResolver.delete(destination, null, null)
        }
    }

    @Test
    fun repeatedDownloadReturnsActualSystemRenamedFile() {
        val name = "download-regression-${java.util.UUID.randomUUID()}.bin"
        val bytes = "same filename does not mean same download".toByteArray()
        val digest = sha256(bytes)
        val uri = "galaxyssi-artifact://test-${java.util.UUID.randomUUID()}/outputs/$name"
        val id = sha256("$uri\u0000$digest".toByteArray())
        fixtures[uri] = id
        AgentDesktopArtifactStore.ingest(context,
            payload(id, uri, digest, bytes.size, 0, 1, bytes).put("name", name))
        val block = AgentRichBlock(id = "duplicate-save", type = AgentRichBlockType.FILE,
            uri = uri, mimeType = "application/octet-stream",
            metadata = mapOf("artifact_id" to id, "sha256" to digest))
        val destinations = mutableListOf<android.net.Uri>()
        val names = mutableListOf<String>()
        try {
            repeat(2) {
                val reported = AgentDesktopArtifactStore.saveToDownloads(context, block).getOrThrow()
                val metadata = java.io.File(context.filesDir,
                    "desktop-artifacts-v2/metadata/${sha256(uri.toByteArray())}.json")
                val destination = android.net.Uri.parse(JSONObject(metadata.readText()).getString("saved_uri"))
                destinations += destination
                val actual = context.contentResolver.query(destination,
                    arrayOf(android.provider.MediaStore.Downloads.DISPLAY_NAME), null, null, null)!!.use {
                    assertTrue(it.moveToFirst())
                    it.getString(0)
                }
                names += actual
                assertEquals(actual, reported.substringAfterLast('/'))
                assertEquals(digest, context.contentResolver.openInputStream(destination)!!.use { sha256(it.readBytes()) })
            }
            assertEquals(2, destinations.distinct().size)
            assertEquals(2, names.distinct().size)
        } finally {
            destinations.forEach { context.contentResolver.delete(it, null, null) }
        }
    }

    @Test
    fun deliveredArtifactCanBeRecoveredOnlyFromItsConversation() {
        val suffix = java.util.UUID.randomUUID().toString()
        val store = AgentTranscriptStore(context, "artifact-recovery-$suffix")
        val conversation = store.createConversation("Artifact recovery fixture").id
        recoveryConversations += conversation
        val bytes = "verified Office output $suffix".toByteArray()
        val digest = sha256(bytes)
        val uri = "galaxyssi-artifact://test-$suffix/outputs/report-v02.bin"
        val id = sha256("$uri\u0000$digest".toByteArray())
        fixtures[uri] = id
        AgentDesktopArtifactStore.ingest(context,
            payload(id, uri, digest, bytes.size, 0, 1, bytes).put("name", "report-v02.bin"))
        val block = AgentRichBlock(id = "artifact-${digest.take(24)}", type = AgentRichBlockType.FILE,
            title = "Friendly caption", uri = uri, mimeType = "application/octet-stream",
            metadata = mapOf("artifact_id" to id, "sha256" to digest))
        store.upsert(AgentTranscriptRole.ASSISTANT, "Completed", "recovery-$suffix",
            conversationId = conversation, richOutputJson = AgentRichContentCodec.encode(listOf(block)))
        // Exercise a later page without modifying any user conversations.
        repeat(105) { index -> store.upsert(AgentTranscriptRole.PROCESS, "Fixture $index",
            "recovery-$suffix-$index", conversationId = conversation) }
        val restored = AgentDeliveredAttachmentRecovery.restore(context, conversation, listOf(block.id))
        assertEquals(1, restored.size)
        assertEquals("report-v02.bin", restored.single().displayName)
        assertEquals(digest, context.contentResolver.openInputStream(restored.single().uri)!!.use { sha256(it.readBytes()) })
        assertTrue(AgentDeliveredAttachmentRecovery.restore(context, "other-$suffix", listOf(block.id)).isEmpty())
        assertTrue(AgentDeliveredAttachmentRecovery.restore(context, conversation, listOf("missing-$suffix")).isEmpty())
    }

    @Test
    fun deliveredRecoveryRejectsUserBlocksAndMismatchedVersions() {
        val suffix = java.util.UUID.randomUUID().toString()
        val store = AgentTranscriptStore(context, "artifact-recovery-$suffix")
        val conversation = store.createConversation("Artifact recovery rejection fixture").id
        recoveryConversations += conversation
        val bytes = "verified bytes".toByteArray()
        val digest = sha256(bytes)
        val uri = "galaxyssi-artifact://test-$suffix/outputs/report.bin"
        val id = sha256("$uri\u0000$digest".toByteArray())
        fixtures[uri] = id
        AgentDesktopArtifactStore.ingest(context, payload(id, uri, digest, bytes.size, 0, 1, bytes))
        val block = AgentRichBlock(id = "artifact-${digest.take(24)}", type = AgentRichBlockType.FILE,
            uri = uri, metadata = mapOf("artifact_id" to id, "sha256" to digest))
        store.upsert(AgentTranscriptRole.USER, "Input", "user-$suffix", conversationId = conversation,
            richOutputJson = AgentRichContentCodec.encode(listOf(block)))
        assertTrue(AgentDeliveredAttachmentRecovery.restore(context, conversation, listOf(block.id)).isEmpty())
        val invalid = block.copy(metadata = block.metadata + ("sha256" to sha256("different version".toByteArray())))
        store.upsert(AgentTranscriptRole.ASSISTANT, "Invalid", "invalid-$suffix", conversationId = conversation,
            richOutputJson = AgentRichContentCodec.encode(listOf(invalid)))
        assertTrue(AgentDeliveredAttachmentRecovery.restore(context, conversation, listOf(block.id)).isEmpty())
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
