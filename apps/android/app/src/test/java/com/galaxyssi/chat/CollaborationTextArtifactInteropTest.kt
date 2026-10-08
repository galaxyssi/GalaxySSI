package com.galaxyssi.chat

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationTextArtifactInteropTest {
    private class Rows : CollaborationWorkspaceRows {
        val values = sortedMapOf<String, String>()
        override fun read(key: String) = values[key]
        override fun page(prefix: String, after: String, limit: Int) =
            values.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { this.values.putAll(values) }
    }

    private fun python(vararg arguments: String): JSONObject {
        val root = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .first { File(it, "apps/desktop/core/galaxyssi-link/backend").isDirectory }
        val fixture = File(root, "apps/desktop/core/galaxyssi-link/backend/tests/collaboration_text_artifact_fixture.py")
        val outputFile = Files.createTempFile("galaxyssi-interop-output", ".json").toFile()
        try {
            val executable: String = System.getenv("GALAXYSSI_TEST_PYTHON") ?: "python"
            val process = ProcessBuilder(listOf(executable, fixture.path) + arguments)
                .redirectErrorStream(true).redirectOutput(outputFile).start()
            val finished = process.waitFor(30, TimeUnit.SECONDS)
            if (!finished) process.destroyForcibly().waitFor()
            assertTrue("Python contract fixture timed out", finished)
            val output = outputFile.readText(Charsets.UTF_8)
            assertEquals(output, 0, process.exitValue())
            return JSONObject(output)
        } finally {
            outputFile.delete()
        }
    }

    @Test fun desktopSnapshotSurvivesHostPublicationReopenAndExactPeerRead() {
        val directory = Files.createTempDirectory("galaxyssi-text-interop").toFile()
        try {
            val authorRoot = File(directory, "author").apply { mkdirs() }
            val peerRoot = File(directory, "peer").apply { mkdirs() }
            val text = "\uFEFFdef predict(x):\r\n    return x * 2\r\n" + "# \u4E2D\u6587 \uD83D\uDD2C original\r\n".repeat(700)
            val bytes = text.toByteArray(Charsets.UTF_8)
            File(authorRoot, "outputs").mkdirs()
            val source = File(authorRoot, "outputs/candidate.py").apply { writeBytes(bytes) }
            val request = python("publish", authorRoot.path).getJSONObject("captured_request")
            CollaborationMilestoneTool.validate(request)
            val rows = Rows()
            val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "author-node", "author")
            val workspace = CollaborationResearchWorkspace(rows)
            workspace.enrollPublication(author, CollaborationResearchStage.EXECUTE)
            val receipt = CollaborationMilestoneTool.execute(workspace, author, request) {}
            assertTrue(receipt.toString(), receipt.getBoolean("success"))
            val ref = receipt.getJSONArray("revisions").getJSONObject(0)
            val id = ref.getString("object_id")
            val original = workspace.read(author, id, 1)!!
            assertEquals("member_reported_not_verified", original.getString("evidence_state"))
            assertEquals(0, original.getJSONArray("host_observations").length())
            assertEquals("galaxyssi.text-artifact/1", original.getJSONObject("body").getString("format"))

            source.writeText("author changed its working copy")
            val reopened = CollaborationResearchWorkspace(rows)
            val query = JSONObject().put("mode", "receipt").put("milestone_id", request.getString("milestone_id"))
                .put("artifact_sha256", AgentResultRecoveryClient.sha256(request.getString("artifact").toByteArray(Charsets.UTF_8)))
            val committed = rows.values.toMap()
            val recovered = CollaborationMilestoneTool.execute(reopened, author, query) {}
            assertTrue(recovered.toString(), recovered.getBoolean("success"))
            assertEquals(receipt.getJSONArray("revisions").toString(), recovered.getJSONArray("revisions").toString())
            val receiptFile = File(directory, "receipt.json").apply { writeText(recovered.toString(), Charsets.UTF_8) }
            assertTrue(python("confirm", authorRoot.path, receiptFile.path).getBoolean("success"))
            assertEquals(committed, rows.values)
            val peer = author.copy(nodeId = "peer-node", personId = "peer")
            assertNull(reopened.read(peer, id, 1))
            val granted = peer.copy(pinnedReads = setOf(CollaborationMilestoneDispatch.grant(original)!!))
            val saved = reopened.read(granted, id, 1)!!
            assertNull(reopened.read(granted.copy(groupId = "other-group"), id, 1))
            val document = saved.toString()
            val pages = JSONObject()
            var offset = 0
            while (offset < document.length) {
                val end = minOf(document.length, offset + 8000)
                pages.put(offset.toString(), JSONObject().put("success", true).put("content", document.substring(offset, end))
                    .put("total_characters", document.length).put("next_offset", if (end < document.length) end else JSONObject.NULL))
                offset = end
            }
            assertTrue(pages.length() > 1)
            val input = File(directory, "pages.json").apply { writeText(JSONObject()
                .put("arguments", JSONObject().put("mode", "materialize").put("object_id", id).put("revision", 1)
                    .put("sha256", ref.getString("sha256"))).put("pages", pages).toString(), Charsets.UTF_8) }
            val result = python("materialize", peerRoot.path, input.path)
            assertTrue(result.getBoolean("success"))
            assertFalse(result.getBoolean("executed"))
            assertFalse(result.getBoolean("verified_claim"))
            assertArrayEquals(bytes, File(result.getString("path")).readBytes())
            val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            assertEquals(hash, result.getString("file_sha256"))
        } finally {
            directory.deleteRecursively()
        }
    }
}
