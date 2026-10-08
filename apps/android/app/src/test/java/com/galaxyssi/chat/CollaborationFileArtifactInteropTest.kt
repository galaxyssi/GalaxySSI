package com.galaxyssi.chat

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationFileArtifactInteropTest {
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
        val fixture = File(root, "apps/desktop/core/galaxyssi-link/backend/tests/collaboration_file_artifact_fixture.py")
        val outputFile = Files.createTempFile("galaxyssi-file-interop-output", ".json").toFile()
        try {
            val executable = System.getenv("GALAXYSSI_TEST_PYTHON") ?: "python"
            val process = ProcessBuilder(listOf(executable, fixture.path) + arguments)
                .redirectErrorStream(true).redirectOutput(outputFile).start()
            val finished = process.waitFor(30, TimeUnit.SECONDS)
            if (!finished) process.destroyForcibly().waitFor()
            assertTrue("Python file contract fixture timed out", finished)
            val output = outputFile.readText(Charsets.UTF_8)
            assertEquals(output, 0, process.exitValue())
            return JSONObject(output)
        } finally { outputFile.delete() }
    }

    @Test fun fullFileIsAuthorizedByPhoneVersionAndRecoveredAfterProducerProcessEnds() {
        val directory = Files.createTempDirectory("galaxyssi-file-interop").toFile()
        try {
            File(directory, "author/outputs").mkdirs()
            File(directory, "peer").mkdirs()
            val bytes = ByteArray(2 * 1024 * 1024) { (it % 256).toByte() }
            val source = File(directory, "author/outputs/evidence.bin").apply { writeBytes(bytes) }
            val request = python("publish", directory.path).getJSONObject("captured_request")
            assertTrue(request.toString().toByteArray(Charsets.UTF_8).size < 2048)
            CollaborationMilestoneTool.validate(request)
            val rows = Rows()
            val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "author-node", "author")
            val workspace = CollaborationResearchWorkspace(rows)
            workspace.enrollPublication(author, CollaborationResearchStage.EXECUTE)
            val receipt = CollaborationMilestoneTool.execute(workspace, author, request) {}
            assertTrue(receipt.toString(), receipt.getBoolean("success"))
            assertFalse(receipt.getBoolean("assignment_completed"))
            val ref = receipt.getJSONArray("revisions").getJSONObject(0)
            val id = ref.getString("object_id")
            val original = workspace.read(author, id, 1)!!
            assertEquals("galaxyssi.file-artifact/1", original.getJSONObject("body").getString("format"))
            assertFalse(original.getJSONObject("body").has("content"))
            assertEquals("member_reported_not_verified", original.getString("evidence_state"))
            assertEquals(0, original.getJSONArray("host_observations").length())
            val receiptQuery = JSONObject().put("mode", "receipt").put("milestone_id", request.getString("milestone_id"))
                .put("artifact_sha256", AgentResultRecoveryClient.sha256(request.getString("artifact").toByteArray(Charsets.UTF_8)))
            val committed = rows.values.toMap()
            val recoveredReceipt = CollaborationMilestoneTool.execute(CollaborationResearchWorkspace(rows), author, receiptQuery) {}
            assertTrue(recoveredReceipt.toString(), recoveredReceipt.getBoolean("success"))
            assertEquals(receipt.getJSONArray("revisions").toString(), recoveredReceipt.getJSONArray("revisions").toString())
            assertEquals(committed, rows.values)
            val receiptFile = File(directory, "receipt.json").apply { writeText(recoveredReceipt.toString(), Charsets.UTF_8) }
            source.writeText("producer moved on to another version")
            assertTrue(python("confirm", directory.path, receiptFile.path).getBoolean("success"))
            source.delete()
            val reopened = CollaborationResearchWorkspace(rows)
            assertEquals(recoveredReceipt.toString(), CollaborationMilestoneTool.execute(reopened, author, receiptQuery) {}.toString())
            assertEquals(committed, rows.values)
            val peer = author.copy(nodeId = "peer-node", personId = "peer")
            assertNull(reopened.read(peer, id, 1))
            val granted = peer.copy(pinnedReads = setOf(CollaborationMilestoneDispatch.grant(original)!!))
            val saved = reopened.read(granted, id, 1)!!
            assertNull(reopened.read(granted.copy(groupId = "other-group"), id, 1))
            assertNull(reopened.read(granted.copy(pinnedReads = emptySet()), id, 1))
            val document = saved.toString()
            val pages = JSONObject()
            var offset = 0
            while (offset < document.length) {
                val end = minOf(document.length, offset + 500)
                pages.put(offset.toString(), JSONObject().put("success", true).put("content", document.substring(offset, end))
                    .put("total_characters", document.length).put("next_offset", if (end < document.length) end else JSONObject.NULL))
                offset = end
            }
            val input = File(directory, "pages.json").apply { writeText(JSONObject().put("pages", pages)
                .put("arguments", JSONObject().put("mode", "materialize").put("object_id", id).put("revision", 1)
                    .put("sha256", ref.getString("sha256"))).toString(), Charsets.UTF_8) }
            val result = python("materialize", directory.path, input.path)
            assertTrue(result.getBoolean("success"))
            assertFalse(result.getBoolean("executed"))
            assertFalse(result.getBoolean("verified_claim"))
            assertArrayEquals(bytes, File(result.getString("path")).readBytes())
            assertEquals(MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) },
                result.getString("file_sha256"))
        } finally { directory.deleteRecursively() }
    }
}
