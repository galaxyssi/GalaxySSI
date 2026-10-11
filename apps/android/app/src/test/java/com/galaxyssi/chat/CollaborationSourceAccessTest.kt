package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationSourceAccessTest {
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 1, "review", "reviewer", setOf("author"))
    private fun record(label: String, node: String = "author", kind: String = "workspace") = JSONObject()
        .put(if (kind == "workspace") "object_id" else "evidence_id", AgentNativeJsonCodec.sha256(label))
        .put("sha256", AgentNativeJsonCodec.sha256("content:$label")).put("revision", 1)
        .put("group_id", "group").put("run_id", "run").put("turn_id", "turn").put("round", 1)
        .put("node_id", node).put("person_id", node).put("parents", JSONArray()).put("host_observations", JSONArray())
        .put("body", JSONObject().put("secret", label))
    private fun ref(record: JSONObject, kind: String = "workspace") = JSONObject()
        .put(if (kind == "workspace") "object_id" else "evidence_id", record.getString(if (kind == "workspace") "object_id" else "evidence_id"))
        .put("sha256", record.getString("sha256")).apply { if (kind == "workspace") put("revision", record.getInt("revision")) }
    private fun input(root: JSONObject): Map<String, Any?> = ref(root).toNativeObject() + ("mode" to CollaborationSourceAccess.MODE)
    private fun read(root: JSONObject, saved: List<JSONObject> = emptyList(), evidence: JSONObject? = null,
                     who: CollaborationWorkspaceAccess = access, query: Map<String, Any?> = input(root)) =
        CollaborationSourceAccess.read(query, who, { id, rev -> (listOf(root) + saved).find {
            it.optString("object_id") == id && it.optInt("revision") == rev
        } }, { evidence })
    private fun reject(action: () -> Unit) {
        try { action(); fail("Expected rejected selector or scope") } catch (_: IllegalArgumentException) { }
    }

    @Test fun directSourcesExposeAvailabilityNotHiddenContentsOrTransitiveGrants() {
        val hidden = record("hidden secret", "other")
        val available = record("visible secret")
        val observation = record("tool secret", kind = "evidence")
        val root = record("root").put("parents", JSONArray().put(ref(hidden)).put(ref(available)))
            .put("host_observations", JSONArray().put(ref(observation, "evidence")))
        val output = read(root, listOf(hidden, available), observation)
        val refs = output.getJSONArray("references")
        assertEquals(3, output.getInt("total_references"))
        assertEquals("missing_changed_or_out_of_scope", refs.getJSONObject(0).getString("status"))
        assertFalse(refs.getJSONObject(0).has("read_original"))
        assertEquals("available", refs.getJSONObject(1).getString("status"))
        assertEquals("evidence", refs.getJSONObject(2).getJSONObject("read_original").getString("mode"))
        assertEquals(0, refs.getJSONObject(2).getInt("source_index"))
        assertEquals("host_observations", refs.getJSONObject(2).getString("source_field"))
        assertFalse(output.toString().contains("secret"))
        assertFalse(output.has(CollaborationEvidenceReadCoverage.FIELD))
        assertFalse(output.getBoolean("availability_snapshot"))
        assertTrue(output.isNull("next_cursor"))
        assertFalse(access.canRead(hidden))
    }

    @Test fun paginationBoundsLookupsWithoutLimitingTotalSources() {
        val sources = (1..47).map { record("source$it") }
        val root = record("root").put("parents", JSONArray(sources.map { ref(it) }))
        var cursor = ""
        val ids = mutableListOf<String>()
        val pageSizes = mutableListOf<Int>()
        do {
            var reads = 0
            val output = CollaborationSourceAccess.read(input(root) + ("cursor" to cursor), access, { id, _ ->
                reads++
                if (id == root.getString("object_id")) root else sources.find { it.getString("object_id") == id }
            }, { error("No evidence reads expected") })
            val refs = output.getJSONArray("references")
            pageSizes += refs.length()
            assertEquals(refs.length() + 1, reads)
            repeat(refs.length()) { ids += refs.getJSONObject(it).getJSONObject("reference").getString("object_id") }
            cursor = if (output.isNull("next_cursor")) "" else output.getString("next_cursor")
        } while (cursor.isNotEmpty())
        assertEquals(listOf(20, 20, 7), pageSizes)
        assertEquals(sources.map { it.getString("object_id") }, ids)
    }

    @Test fun cursorsAreBoundToExactOwnerAndCompleteAssignmentScope() {
        val parent = record("source")
        val root = record("root").put("parents", JSONArray(List(21) { ref(parent) }))
        val cursor = read(root, listOf(parent)).getString("next_cursor")
        val query = input(root) + ("cursor" to cursor)
        listOf(access.copy(runId = "other"), access.copy(turnId = "other"), access.copy(round = 2),
            access.copy(nodeId = "other"), access.copy(personId = "other"),
            access.copy(dependencyNodes = setOf("author", "extra")), access.copy(pinnedReads = setOf("extra"))).forEach {
            reject { read(root, listOf(parent), who = it, query = query) }
        }
        val changed = JSONObject(root.toString()).put("sha256", "f".repeat(64))
        reject { read(changed, listOf(parent), query = input(changed) + ("cursor" to cursor)) }
        val other = JSONObject(root.toString()).put("object_id", "e".repeat(64))
        reject { read(other, listOf(parent), query = input(other) + ("cursor" to cursor)) }
        assertEquals(1, read(root, listOf(parent), query = query).getJSONArray("references").length())
    }

    @Test fun selectorsCannotSupplyScopeOrArbitraryReferences() {
        val root = record("root")
        listOf("group_id", "person_id", "node_id", "offset", "inputs", "query", "record_id", "work_id", "topic", "evidence_id")
            .forEach { reject { read(root, query = input(root) + (it to "anything")) } }
        listOf(null, true, "1", 0, -1, 1.5, Long.MAX_VALUE, Double.NaN).forEach {
            reject { read(root, query = input(root) + ("revision" to it)) }
        }
        listOf("", "../x", "a".repeat(63), "A".repeat(64), 42).forEach {
            reject { read(root, query = input(root) + ("object_id" to it)) }
            reject { read(root, query = input(root) + ("sha256" to it)) }
        }
        listOf(null, false, 1, "x".repeat(513)).forEach { value ->
            reject { read(root, query = input(root) + ("cursor" to value)) }
        }
    }

    @Test fun unreadableOrChangedRootStopsBeforeAnySourceLookup() {
        val root = record("root", "other")
        var reads = 0
        reject { CollaborationSourceAccess.read(input(root), access, { _, _ -> reads++; root }, { error("not reached") }) }
        assertEquals(1, reads)
        reject { read(record("root"), query = input(record("root")) + ("sha256" to "f".repeat(64))) }
        reject { read(record("root"), who = access.copy(groupId = "other")) }
    }

    @Test fun missingChangedAndIsolatedTargetsHaveTheSameNonDisclosingStatus() {
        val source = record("source")
        val root = record("root").put("parents", JSONArray().put(ref(source)))
        val projections = listOf(emptyList(), listOf(JSONObject(source.toString()).put("sha256", "f".repeat(64))),
            listOf(JSONObject(source.toString()).put("node_id", "other"))).map {
            read(root, it).getJSONArray("references").toString()
        }
        assertEquals(1, projections.toSet().size)
    }

    @Test fun evidenceIdentityAndScopeAreCheckedEvenWhenResolverReturnsSomething() {
        val expected = record("expected", kind = "evidence")
        val root = record("root").put("host_observations", JSONArray().put(ref(expected, "evidence")))
        listOf(null, record("other", kind = "evidence"), JSONObject(expected.toString()).put("node_id", "other"),
            JSONObject(expected.toString()).put("sha256", "f".repeat(64))).forEach {
            assertEquals("missing_changed_or_out_of_scope", read(root, evidence = it).getJSONArray("references").getJSONObject(0).getString("status"))
        }
    }

    @Test fun bodyLinksAreNotTraversedAndRecordsRemainUnchanged() {
        val root = record("root").put("body", JSONObject().put("parents", JSONArray().put(ref(record("body source")))))
        val before = root.toString()
        val output = read(root)
        assertEquals(0, output.getJSONArray("references").length())
        assertEquals(0, output.getInt("total_references"))
        assertEquals(before, root.toString())
    }

    @Test fun exactExistingGrantAllowsOneReferenceNotItsAncestors() {
        val ancestor = record("ancestor", "other")
        val parent = record("parent", "other").put("parents", JSONArray().put(ref(ancestor)))
        val root = record("root").put("parents", JSONArray().put(ref(parent)))
        val who = access.copy(pinnedReads = setOf(requireNotNull(CollaborationMilestoneDispatch.grant(parent))))
        assertEquals("available", read(root, listOf(parent, ancestor), who = who).getJSONArray("references").getJSONObject(0).getString("status"))
        assertFalse(who.canRead(ancestor))
    }

    @Test fun unchangedCursorReflectsCurrentAvailabilityNotAnOldSnapshot() {
        val source = record("source")
        val root = record("root").put("parents", JSONArray(List(21) { ref(source) }))
        val query = input(root) + ("cursor" to read(root, listOf(source)).getString("next_cursor"))
        assertEquals("available", read(root, listOf(source), query = query).getJSONArray("references").getJSONObject(0).getString("status"))
        assertEquals("missing_changed_or_out_of_scope", read(root, query = query).getJSONArray("references").getJSONObject(0).getString("status"))
    }

    @Test fun persistedWorkspaceReadDoesNotMutatePublicationOrMarkEvidenceRead() {
        val rows = CollaborationGoalAcceptanceTest.Rows()
        var authorized = true
        val workspace = CollaborationResearchWorkspace(rows, accessAuthorized = { authorized })
        val author = access.copy(nodeId = "author", personId = "author")
        fun publish(id: String, parents: JSONArray = JSONArray()): JSONObject {
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
                .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", "artifact").put("title", id)
                    .put("body", JSONObject().put("content", id)).put("parents", parents)))
            return workspace.publish(author.copy(nodeId = id, dependencyNodes = setOf("source")), raw.toString()).getJSONArray("revisions").getJSONObject(0)
        }
        val parent = publish("source")
        val root = publish("root", JSONArray().put(parent))
        val who = access.copy(dependencyNodes = setOf("root"))
        val before = rows.data.toMap()
        val reopened = CollaborationResearchWorkspace(rows, accessAuthorized = { authorized })
        val output = reopened.sourceAccess(who, input(root))
        assertEquals("missing_changed_or_out_of_scope", output.getJSONArray("references").getJSONObject(0).getString("status"))
        assertEquals(before, rows.data)
        authorized = false
        reject { reopened.sourceAccess(who, input(root)) }
    }
}
