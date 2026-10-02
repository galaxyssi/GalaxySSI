package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationResearchWorkspaceTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var rejectWrite = false
        override fun read(key: String) = data[key]
        override fun commit(values: Map<String, String>) {
            check(!rejectWrite) { "Storage unavailable" }
            data.putAll(values)
        }
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
    }
    private fun access(node: String = "author", person: String = node, round: Long = 1) =
        CollaborationWorkspaceAccess("group", "run", "turn", round, node, person)
    private fun item(id: String = "candidate-a", kind: String = "proposal") = JSONObject().put("id", id)
        .put("kind", kind).put("title", "Verifiable design").put("body", JSONObject().put("content", "Original design with constraints"))
    private fun raw(vararg items: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Useful contribution").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("questions", JSONArray()).put("workspace", JSONArray(items.toList())).toString()
    private fun ref(result: JSONObject) = result.getJSONArray("revisions").getJSONObject(0)

    @Test fun hostAssignsIdentityVersionAndNeverTrustsVerificationClaim() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val receipt = ref(workspace.publish(access(), raw(item().put("person_id", "coordinator").put("evidence_state", "verified")), 123))
        val saved = requireNotNull(workspace.read(access(), receipt.getString("object_id"), 1))
        assertEquals("author", saved.getString("person_id"))
        assertEquals("member_reported_not_verified", saved.getString("evidence_state"))
        assertEquals(123, saved.getLong("recorded_at"))
        assertEquals(64, saved.getString("sha256").length)
    }

    @Test fun replayIsIdempotentAndConflictingDispatchCannotCreateSecondRevision() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        val input = raw(item())
        val result = workspace.publish(access(), input)
        val count = rows.data.size
        assertEquals(result.toString(), CollaborationResearchWorkspace(rows).publish(access(), input).toString())
        assertEquals(count, rows.data.size)
        assertEquals("rejected", workspace.publish(access(), raw(item("different"))).getString("status"))
    }

    @Test fun independentCurrentRoundCannotReadEditOrListPeerProposal() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val id = ref(workspace.publish(access(), raw(item()))).getString("object_id")
        val independent = access("independent")
        assertNull(workspace.read(independent, id, 1))
        assertTrue(workspace.browse(independent).revisions.isEmpty())
        val update = item().put("object_id", id).put("base_revision", 1)
        assertEquals("rejected", workspace.publish(independent, raw(update)).getString("status"))
        assertNotNull(workspace.read(independent.copy(dependencyNodes = setOf("author")), id, 1))
        assertNotNull(workspace.read(independent.copy(round = 2), id, 1))
        assertNull(workspace.read(independent.copy(groupId = "different-group", round = 2), id, 1))
    }

    @Test fun revisionsPreserveOriginalAndStaleUpdateIsAtomic() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val first = ref(workspace.publish(access(), raw(item())))
        val id = first.getString("object_id")
        val update = item().put("object_id", id).put("base_revision", 1)
            .put("body", JSONObject().put("content", "Improved design"))
        val editor = access("editor", round = 2)
        assertEquals("recorded", workspace.publish(editor, raw(update)).getString("status"))
        val stale = workspace.publish(access("stale", round = 3), raw(item("new-object"), update))
        assertEquals("rejected", stale.getString("status"))
        assertEquals(1, workspace.browse(access(round = 4)).revisions.size)
        assertEquals("Original design with constraints", workspace.read(editor, id, 1)!!.getJSONObject("body").getString("content"))
        val second = workspace.read(editor, id, 2)!!
        assertEquals(first.getString("sha256"), second.getString("previous_sha256"))
        assertEquals("Improved design", second.getJSONObject("body").getString("content"))
    }

    @Test fun hiddenNewRevisionDoesNotHideAnEarlierVisibleOriginal() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val id = ref(workspace.publish(access(round = 0), raw(item()))).getString("object_id")
        workspace.publish(access("editor"), raw(item().put("object_id", id).put("base_revision", 1)))
        assertEquals(1, workspace.browse(access("independent")).revisions.single().getInt("revision"))
    }

    @Test fun combinationAndRepairReferToExactParentsAndCounterexamples() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val first = workspace.publish(access(), raw(item("a"), item("b"), item("counter", "counterexample")))
        val refs = first.getJSONArray("revisions")
        val combination = item("combined").put("parents", JSONArray().put(refs.getJSONObject(0)).put(refs.getJSONObject(1)))
            .put("resolves", JSONArray().put(refs.getJSONObject(2)))
        val editor = access("combiner", round = 2)
        val id = ref(workspace.publish(editor, raw(combination))).getString("object_id")
        val saved = workspace.read(editor, id, 1)!!
        assertEquals(2, saved.getJSONArray("parents").length())
        assertEquals(1, saved.getJSONArray("resolves").length())
        assertEquals(4, workspace.browse(editor).revisions.size)
    }

    @Test fun danglingReferencesAndKindChangesAreRejected() {
        val workspace = CollaborationResearchWorkspace(Rows())
        val id = ref(workspace.publish(access(), raw(item()))).getString("object_id")
        assertEquals("rejected", workspace.publish(access("editor", round = 2), raw(item(kind = "evidence")
            .put("object_id", id).put("base_revision", 1))).getString("status"))
        val dangling = item().put("parents", JSONArray().put(JSONObject().put("object_id", "a".repeat(64)).put("revision", 99)))
        assertEquals("rejected", workspace.publish(access("missing", round = 2), raw(dangling)).getString("status"))
    }

    @Test fun fullBodiesSurviveReopenAndDirectoryIsPaged() {
        val rows = Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        val content = "Original evidence and rejected route. ".repeat(1000)
        val id = ref(workspace.publish(access(), raw(item().put("body", JSONObject().put("content", content))))).getString("object_id")
        repeat(41) { workspace.publish(access("node-$it"), raw(item("object-$it"))) }
        val reopened = CollaborationResearchWorkspace(rows)
        val reader = access(round = 2)
        assertEquals(content, reopened.read(reader, id, 1)!!.getJSONObject("body").getString("content"))
        var cursor = ""
        val ids = mutableListOf<String>()
        do {
            val page = reopened.browse(reader, cursor, 7)
            ids += page.revisions.map { it.getString("object_id") }
            cursor = page.next.orEmpty()
        } while (cursor.isNotEmpty())
        assertEquals(42, ids.size)
        assertEquals(42, ids.toSet().size)
    }

    @Test fun failedCommitCannotPublishPartialRevisionAndCanReplayAfterRecovery() {
        val rows = Rows().apply { rejectWrite = true }
        val workspace = CollaborationResearchWorkspace(rows)
        assertTrue(runCatching { workspace.publish(access(), raw(item())) }.isFailure)
        assertTrue(rows.data.isEmpty())
        rows.rejectWrite = false
        assertEquals("recorded", workspace.publish(access(), raw(item())).getString("status"))
    }

    @Test fun removedGroupCannotRecreateWorkspaceOrReadOldData() {
        val rows = Rows()
        var allowed = true
        val workspace = CollaborationResearchWorkspace(rows) { allowed }
        val id = ref(workspace.publish(access(), raw(item()))).getString("object_id")
        allowed = false
        assertNull(workspace.read(access(), id, 1))
        assertTrue(workspace.browse(access()).revisions.isEmpty())
        val count = rows.data.size
        assertEquals("rejected", workspace.publish(access("late"), raw(item())).getString("status"))
        assertEquals(count, rows.data.size)
    }
}
