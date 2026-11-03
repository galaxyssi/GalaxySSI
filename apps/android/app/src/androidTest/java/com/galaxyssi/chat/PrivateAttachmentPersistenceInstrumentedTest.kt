package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.provider.MediaStore
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PrivateAttachmentPersistenceInstrumentedTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun selectedImagesAndFilesSurviveDeletionOfExternalSource() {
        for ((name, mime) in listOf("photo.png" to "image/png", "document.pdf" to "application/pdf")) {
            val external = File.createTempFile("attachment-test-", ".tmp", context.externalCacheDir)
            val bytes = if (mime == "image/png") imageBytes() else "%PDF-1.4 fixture".toByteArray()
            external.writeBytes(bytes)
            var privateFile: File? = null
            try {
                val original = AgentInputAttachment(UUID.randomUUID().toString(), Uri.fromFile(external), name, mime, bytes.size.toLong())
                val retained = ComposerAttachmentImport.retain(context, original)
                privateFile = LocalAttachmentUris.resolve(context, retained.uri)!!
                assertTrue(privateFile.canonicalPath.startsWith(context.filesDir.canonicalPath + "/"))
                assertTrue(external.delete())
                assertArrayEquals(bytes, context.contentResolver.openInputStream(retained.uri)!!.use { it.readBytes() })
                assertEquals(retained.uri, ComposerAttachmentImport.retain(context, retained).uri)
                assertEquals(original.id, retained.id)
                assertEquals(name, retained.displayName)
            } finally { external.delete(); privateFile?.delete() }
        }
    }

    @Test fun agentMarkdownImageRemainsPrivateAndDoesNotNeedNetworkAfterCacheRemoval() {
        val source = "https://127.0.0.1/private-image-${UUID.randomUUID()}.png"
        val bytes = imageBytes()
        val file = AgentMarkdownImageStore.cache(context, source, bytes)
        try {
            assertTrue(file.canonicalPath.startsWith(context.filesDir.canonicalPath + "/"))
            val key = file.name
            File(context.cacheDir, "markdown-images/$key").delete()
            assertArrayEquals(bytes, AgentMarkdownImageStore.load(context, source).readBytes())
        } finally { file.delete() }
    }

    @Test fun existingMarkdownCacheIsMigratedToPrivatePersistentStorage() {
        val source = "https://127.0.0.1/legacy-image-${UUID.randomUUID()}.png"
        val destination = AgentMarkdownImageStore.cacheFile(context, source)
        val legacy = File(context.cacheDir, "markdown-images/${destination.name}")
        val bytes = imageBytes()
        legacy.parentFile!!.mkdirs()
        legacy.writeBytes(bytes)
        try {
            assertEquals(destination, AgentMarkdownImageStore.load(context, source))
            assertArrayEquals(bytes, destination.readBytes())
            assertFalse(legacy.exists())
        } finally { legacy.delete(); destination.delete() }
    }

    @Test fun privateAgentFileExportsOnlyOnSaveAndSurvivesDeletionOfPublicCopy() {
        val name = "private-agent-${UUID.randomUUID()}.pdf"
        val source = File.createTempFile("private-agent-test-", ".pdf", context.cacheDir)
        val bytes = "%PDF-1.4 private Agent result".toByteArray()
        source.writeBytes(bytes)
        var retainedFile: File? = null
        var exported: Uri? = null
        try {
            val retained = ComposerAttachmentImport.retain(context,
                AgentInputAttachment(name, Uri.fromFile(source), name, "application/pdf", bytes.size.toLong()))
            retainedFile = LocalAttachmentUris.resolve(context, retained.uri)!!
            val block = AgentRichBlock(id = name, type = AgentRichBlockType.FILE, title = name,
                uri = retained.uri.toString(), mimeType = "application/pdf")
            assertTrue(AgentPrivateAttachmentExport.canSave(context, block))
            assertFalse(AgentPrivateAttachmentExport.canSave(context,
                block.copy(uri = "https://example.com/file.pdf")))
            assertFalse(AgentPrivateAttachmentExport.canSave(context,
                block.copy(uri = "content://downloads/my_downloads/42")))
            assertTrue(source.delete())
            assertNull(findExport(name))
            AgentPrivateAttachmentExport.save(context, block).getOrThrow()
            exported = findExport(name)!!
            assertArrayEquals(bytes, context.contentResolver.openInputStream(exported)!!.use { it.readBytes() })
            context.contentResolver.delete(exported, null, null)
            exported = null
            assertArrayEquals(bytes, context.contentResolver.openInputStream(retained.uri)!!.use { it.readBytes() })
        } finally {
            exported?.let { context.contentResolver.delete(it, null, null) }
            source.delete()
            retainedFile?.delete()
        }
    }

    @Test fun stagedWebAttachmentsArePrivateAndNotEvictedAfterThirtyTwoDocuments() {
        val preparations = mutableListOf<AgentPhonePublicHtmlPreparation>()
        try {
            repeat(40) { index ->
                val id = UUID.randomUUID().toString()
                preparations += AgentPhonePublicHtmlAttachment.stageDocument(context, "private-$id",
                    AgentPhonePublicHtmlDocument("https://example.com/$id", "private-$index", "test article"))
            }
            preparations.forEach { prepared ->
                assertFalse(prepared.savedToDownloads)
                assertNull(findExport(prepared.attachment.displayName))
                assertTrue(context.contentResolver.openInputStream(prepared.attachment.uri)!!.use { it.readBytes() }.isNotEmpty())
            }
        } finally {
            preparations.forEach { prepared ->
                val id = prepared.attachment.id.removePrefix("phone-web-")
                File(context.filesDir, "agent-public-html/$id.html").delete()
            }
        }
    }

    private fun findExport(name: String): Uri? = context.contentResolver.query(
        MediaStore.Downloads.EXTERNAL_CONTENT_URI, arrayOf(MediaStore.Downloads._ID),
        "${MediaStore.Downloads.DISPLAY_NAME} = ?", arrayOf(name), null
    )!!.use { cursor ->
        if (cursor.moveToFirst()) android.content.ContentUris.withAppendedId(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(0)) else null
    }

    @Test fun completedDownloadRecordKeepsPrivateAttachmentIdentityAfterPendingRecordRemoval() {
        val id = -System.nanoTime()
        val store = AgentAndroidDownloadStore(context)
        val source = File.createTempFile("private-download-test-", ".tmp", context.cacheDir)
        source.writeText("private download fixture")
        var retained: AgentInputAttachment? = null
        try {
            retained = ComposerAttachmentImport.retain(context, AgentInputAttachment(
                "download:$id", Uri.fromFile(source), "download.txt", "text/plain", source.length()))
            store.writeCompleted(id, retained)
            store.remove(id)
            source.delete()
            val completed = store.completed(id)!!
            assertEquals(retained, completed)
            assertEquals("private download fixture", context.contentResolver.openInputStream(completed.uri)!!.use {
                it.reader().readText()
            })
            store.removeCompleted(id)
            assertNull(store.completed(id))
        } finally {
            store.remove(id)
            store.removeCompleted(id)
            retained?.let { LocalAttachmentUris.resolve(context, it.uri)?.delete() }
            source.delete()
        }
    }

    @Test fun receivedContactImagesAndFilesStayPrivateUntilExplicitSave() {
        GalaxySSICrypto.initialize(context)
        val sourceId = "galaxyssi:privacy-test-${UUID.randomUUID()}"
        val routes = GalaxySSILinkProtocol.Routes(GalaxySSILinkProtocol.newRouteId(),
            GalaxySSILinkProtocol.newLinkSecret(), "1".repeat(64), "2".repeat(64))
        for ((extension, mime) in listOf("png" to "image/png", "pdf" to "application/pdf")) {
            val name = "privacy-test-${UUID.randomUUID()}.$extension"
            val bytes = if (extension == "png") imageBytes() else "%PDF-1.4 private fixture".toByteArray()
            val digest = hash(bytes)
            val id = hash(UUID.randomUUID().toString().toByteArray())
            val directory = File(context.filesDir, "peer-incoming-attachments-v2/$id")
            var exported: Uri? = null
            try {
                val manifest = JSONObject().put("type", "input_attachment_manifest").put("transfer_id", id)
                    .put("attachment_id", id).put("name", name).put("mime_type", mime)
                    .put("size_bytes", bytes.size).put("sha256", digest).put("chunk_count", 1)
                    .put("chunk_size_bytes", 256 * 1024).put("contact_id", GalaxySSICrypto.localGalaxySSIId())
                    .put("client_route_id", routes.clientRouteId).put("conversation_id", "privacy-test")
                    .put("task_id", "privacy-test-task").put("turn_id", "privacy-test-turn")
                    .put("client_message_id", 1L).put("eager_chunks", true)
                assertNotNull(PeerIncomingAttachmentStore.ingest(context, manifest, sourceId, routes))
                val chunk = JSONObject(manifest.toString()).put("type", "input_attachment_chunk")
                    .put("chunk_index", 0).put("chunk_size", bytes.size).put("chunk_sha256", digest)
                    .put("data_b64", Base64.encodeToString(bytes, Base64.NO_WRAP))
                assertEquals("stored", PeerIncomingAttachmentStore.ingest(context, chunk, sourceId, routes)?.receipt?.optString("status"))
                val message = JSONObject().put("attachments", JSONArray().put(manifest))
                val attachment = PeerChatAttachment.fromJson(
                    PeerIncomingAttachmentStore.resolveMessageAttachments(context, sourceId, message)!!.getJSONObject(0))
                val local = attachment.resolvedUri(context)!!
                assertNotNull(LocalAttachmentUris.resolve(context, local))
                context.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Downloads._ID), "${MediaStore.Downloads.DISPLAY_NAME} = ?", arrayOf(name), null)!!.use {
                    assertEquals(0, it.count)
                }
                assertArrayEquals(bytes, context.contentResolver.openInputStream(local)!!.use { it.readBytes() })
                exported = Uri.parse(PeerIncomingAttachmentStore.saveToDownloads(context, attachment).getOrThrow())
                context.contentResolver.query(exported, arrayOf(MediaStore.Downloads.RELATIVE_PATH), null, null, null)!!.use {
                    assertTrue(it.moveToFirst())
                    assertEquals("Download/GalaxySSI", it.getString(0).trimEnd('/'))
                }
                assertArrayEquals(bytes, context.contentResolver.openInputStream(exported)!!.use { it.readBytes() })
                context.contentResolver.delete(exported, null, null)
                exported = null
                assertArrayEquals(bytes, context.contentResolver.openInputStream(local)!!.use { it.readBytes() })
            } finally {
                exported?.let { context.contentResolver.delete(it, null, null) }
                directory.deleteRecursively()
            }
        }
    }

    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it) }

    private fun imageBytes(): ByteArray {
        val bitmap = Bitmap.createBitmap(40, 50, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.GREEN) }
        return try { ByteArrayOutputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it); it.toByteArray() } }
        finally { bitmap.recycle() }
    }
}
