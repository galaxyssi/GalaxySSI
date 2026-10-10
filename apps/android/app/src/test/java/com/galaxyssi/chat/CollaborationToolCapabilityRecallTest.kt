package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import com.galaxyssi.chat.CollaborationExecutableTool.RELEASE

class CollaborationToolCapabilityRecallTest {
    private fun results(page: JSONObject) = page.getJSONArray("records").let { a ->
        (0 until a.length()).map(a::getJSONObject)
    }

    @Test fun futureTaskFindsReleasedToolByItsOriginalNamePurposeAndEnvironment() {
        val f = CollaborationExecutableToolTest.Fixture()
        val release = f.ref(f.release())
        val future = f.access().copy(runId = "future", turnId = "future", round = 0)
        val reopened = f.reopen()
        for (query in listOf("stable", "sort", "arrays", "standard-library")) {
            val found = results(reopened.searchCapabilities(future, query))
                .singleOrNull { it.getString("object_id") == release.getString("object_id") }
            assertNotNull("Released tool missing for query: $query", found)
        }
        val found = results(reopened.searchCapabilities(future, "stable"))
            .single { it.getString("object_id") == release.getString("object_id") }
        assertEquals("eligible_for_scoped_tool_execution", found.getString("reported_state"))
        val source = found.getJSONArray("linked_sources").getJSONObject(0)
        assertEquals(f.tool.getString("sha256"), source.getJSONObject("source").getString("sha256"))
        assertFalse(source.getBoolean("complete_read"))
        assertFalse(found.getBoolean("grants_permissions"))
        assertTrue(found.getBoolean("requires_scope_and_lineage_check"))
        assertEquals("Integer lists", found.getJSONObject("excerpts").getString("applies_when"))
        assertEquals("Stable integer sort", found.getJSONObject("excerpts").getString("tool_name"))
        val prepared = f.prepare(JSONObject().put("mode", "run").put(RELEASE, found)
            .put("parameters", JSONObject().put("values", JSONArray("[9,4]"))), access = future)
        assertEquals(f.tool.getString("sha256"), prepared.identity.getJSONObject(TOOL).getString("sha256"))
        assertEquals("future", prepared.identity.getString("run_id"))
    }

    @Test fun visibilityOfReleaseDoesNotExposeAnIsolatedToolDefinition() {
        val f = CollaborationExecutableToolTest.Fixture()
        val release = f.ref(f.release())
        val blind = f.access("peer", 1).copy(dependencyNodes = setOf("release"))
        assertNotNull(f.workspace.read(blind, release.getString("object_id"), 1))
        assertNull(f.workspace.read(blind, f.tool.getString("object_id"), 1))
        assertTrue(results(f.workspace.searchCapabilities(blind, "stable")).isEmpty())
        val own = results(f.workspace.searchCapabilities(blind, "fixture")).single()
        assertEquals(0, own.getJSONArray("linked_sources").length())
        val permitted = blind.copy(dependencyNodes = blind.dependencyNodes + "sort")
        assertTrue(results(f.workspace.searchCapabilities(permitted, "stable")).any {
            it.getString("object_id") == release.getString("object_id")
        })
        assertTrue(results(f.workspace.searchCapabilities(permitted.copy(groupId = "other"), "stable")).isEmpty())
    }

    @Test fun mismatchedToolIdentityKindOrSourceHashCannotExpandRecall() {
        val f = CollaborationExecutableToolTest.Fixture()
        val release = f.ref(f.release())
        val saved = f.workspace.read(f.access(), release.getString("object_id"), 1)!!
        val tool = f.workspace.read(f.access(), f.tool.getString("object_id"), 1)!!
        for (change in listOf<(JSONObject) -> Unit>(
            { it.put("sha256", "changed") }, { it.put("kind", "artifact") },
            { it.getJSONObject(HOST).put("source_sha256", "changed") })) {
            val wrong = JSONObject(tool.toString()).apply(change)
            assertNull(CollaborationCapabilityRecall.match(saved, CollaborationCapabilityRecall.query("stable")) { wrong })
        }
        assertNull(CollaborationCapabilityRecall.match(saved, CollaborationCapabilityRecall.query("stable")) { null })
        val rejected = JSONObject(saved.toString()).apply { getJSONObject(HOST).put("state", "rejected") }
        var reads = 0
        assertNull(CollaborationCapabilityRecall.match(rejected, CollaborationCapabilityRecall.query("stable")) { reads++; tool })
        assertEquals(0, reads)
    }

    @Test fun searchDoesNotIndexSourceCodeOrTestAnswers() {
        val f = CollaborationExecutableToolTest.Fixture()
        f.ref(f.release())
        assertTrue(results(f.workspace.searchCapabilities(f.access(), "parameters")).isEmpty())
        assertTrue(results(f.workspace.searchCapabilities(f.access(), "expected")).isEmpty())
        val tool = f.workspace.read(f.access(), f.tool.getString("object_id"), 1)!!
        assertNull(CollaborationCapabilityRecall.match(tool, CollaborationCapabilityRecall.query("stable")))
        val found = results(f.workspace.searchCapabilities(f.access(), "stable")).single()
        val fields = found.getJSONArray("linked_sources").getJSONObject(0).getJSONArray("fields")
        assertFalse(fields.toString().contains("source"))
        assertFalse(fields.toString().contains("cases"))
    }

    @Test fun linkedToolReadsAreCachedWithinOnePageButNeverAcrossScopes() {
        val f = CollaborationExecutableToolTest.Fixture()
        val observed = f.observed()
        f.ref(f.release(observed))
        repeat(20) { i ->
            var offset: Int? = 0
            while (offset != null) offset = f.ledger.readPage(f.access("reviewer", 4, "release-$i"),
                observed.getString("evidence_id"), observed.getString("sha256"), offset)!!.next
            f.ref(f.publish("release-$i", RELEASE, f.releaseSpec(observed), "reviewer", 4, JSONArray().put(observed)))
        }
        var reads = 0
        val suffix = "revision:${f.tool.getString("object_id")}:1"
        val rows = object : CollaborationWorkspaceRows by f.rows {
            override fun read(key: String): String? {
                if (key.endsWith(suffix)) reads++
                return f.rows.read(key)
            }
        }
        val workspace = CollaborationResearchWorkspace(rows)
        val future = f.access().copy(runId = "future", turnId = "future", round = 0)
        assertEquals(12, results(workspace.searchCapabilities(future, "stable")).size)
        assertEquals(1, reads)
        val blind = f.access("peer", 1).copy(dependencyNodes = setOf("release"))
        assertTrue(results(workspace.searchCapabilities(blind, "stable")).isEmpty())
    }
}
