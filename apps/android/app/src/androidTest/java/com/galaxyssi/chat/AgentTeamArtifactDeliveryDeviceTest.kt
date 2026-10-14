package com.galaxyssi.chat

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentTeamArtifactDeliveryDeviceTest {
    @Test fun imageAndFileSurviveTeamPersistenceAndResolveToReceivedPrivateFiles() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val id = "artifact-test-${UUID.randomUUID()}"
        val namespace = "test-$id"
        val database = AgentEncryptedDatabase(context, namespace)
        val store = EncryptedAgentTeamExecutionStore(database)
        val runtime = AgentTeamExecutionRuntime(store)
        val files = mutableListOf<File>()
        try {
            val bitmap = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(android.graphics.Color.GREEN)
            val png = ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                output.toByteArray()
            }
            bitmap.recycle()
            val blocks = listOf("result.png" to png, "report.md" to "Public test report".toByteArray()).map { (name, bytes) ->
                val uri = "galaxyssi-artifact://$id/outputs/$name"
                val digest = hash(bytes)
                val artifactId = hash(uri.toByteArray())
                val mime = if (name.endsWith("png")) "image/png" else "text/markdown"
                val payload = JSONObject().put("type", "artifact_chunk").put("artifact_id", artifactId)
                    .put("artifact_uri", uri).put("task_id", id).put("name", name).put("mime_type", mime)
                    .put("size_bytes", bytes.size).put("sha256", digest).put("chunk_index", 0)
                    .put("chunk_count", 1).put("chunk_size_bytes", bytes.size).put("chunk_sha256", digest)
                    .put("data_b64", Base64.encodeToString(bytes, Base64.NO_WRAP))
                assertTrue(AgentDesktopArtifactStore.ingest(context, payload).completed)
                files += File(context.filesDir, "desktop-artifacts-v2/files/$artifactId.sasie")
                files += File(context.filesDir, "desktop-artifacts-v2/metadata/${hash(uri.toByteArray())}.json")
                AgentRichBlock(name, if (mime == "image/png") AgentRichBlockType.IMAGE else AgentRichBlockType.FILE,
                    title = name, uri = uri, mimeType = mime, metadata = mapOf("artifact_id" to artifactId, "sha256" to digest))
            }
            val rich = AgentRichContentCodec.encode(blocks)
            val definition = AgentTeamDefinition(id, "primary", listOf(AgentTeamMember("primary", AgentDeliveryMode.RESPOND, role = "writer")))
            val request = AgentRunRequest(conversationId = id, messageId = "turn", taskId = "task",
                runId = id, goal = "Public artifact delivery test", idempotencyKey = id)
            val result = runtime.start(definition, request) { AgentSubagentOutput("", richOutputJson = rich) }.await()
            assertEquals(rich, result.snapshot.finalRichOutputJson)
            val reopened = EncryptedAgentTeamExecutionStore(AgentEncryptedDatabase(context, namespace))
            val restored = requireNotNull(reopened.snapshot(id))
            val rendered = AgentRichContentCodec.decode(restored.finalRichOutputJson)
            assertEquals(listOf(AgentRichBlockType.IMAGE, AgentRichBlockType.FILE), rendered.map { it.type })
            rendered.forEach { block ->
                val resolved = AgentDesktopArtifactStore.resolveBlock(context, block)
                assertTrue(resolved.uri, resolved.uri.startsWith("content://"))
                context.contentResolver.openInputStream(android.net.Uri.parse(resolved.uri)).use { stream ->
                    assertNotNull(stream)
                    if (block.type == AgentRichBlockType.IMAGE) {
                        val decoded = BitmapFactory.decodeStream(stream)
                        assertNotNull(decoded)
                        assertEquals(16, decoded.width)
                        decoded.recycle()
                    } else assertEquals("Public test report", stream!!.bufferedReader().readText())
                }
            }
        } finally {
            runtime.close()
            database.clear()
            files.forEach { it.delete() }
        }
    }

    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
