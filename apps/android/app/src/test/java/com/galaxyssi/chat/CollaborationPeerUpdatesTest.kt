package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPeerUpdatesTest {
    private class Rows : CollaborationWorkspaceRows {
        val data = sortedMapOf<String, String>()
        var fail = false
        override fun read(key: String) = data[key]
        override fun page(prefix: String, after: String, limit: Int) = data.keys.filter { it.startsWith(prefix) && it > after }.take(limit)
        override fun commit(values: Map<String, String>) { check(!fail); data.putAll(values) }
        override fun mutate(values: Map<String, String>, removeKeys: Collection<String>) { removeKeys.forEach(data::remove); commit(values) }
    }
    private val author = CollaborationWorkspaceAccess("group", "run", "turn", 1, "producer", "author")
    private val reader = author.copy(nodeId = "consumer", personId = "peer")
    private fun artifact(id: String, to: List<String> = listOf("peer"), observations: JSONArray = JSONArray()) = JSONObject()
        .put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Testable alternative $id")
        .put("coordination", JSONObject().put("mode", "record_only"))
        .put("requests", JSONArray().put(JSONObject().put("to", JSONArray(to)).put("question", "Check alternative $id")))
        .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", "proposal").put("title", id)
            .put("observations", observations).put("body", JSONObject().put("content", "Discriminating measurement for $id"))))
    private fun workspace(rows: Rows = Rows()) = CollaborationResearchWorkspace(rows).also {
        it.enrollPublication(author, CollaborationResearchStage.EXPLORE)
        it.enrollPublication(reader, CollaborationResearchStage.EXECUTE)
    }
    private fun publish(w: CollaborationResearchWorkspace, id: String, to: List<String> = listOf("peer")): JSONObject {
        val receipt = w.publishMilestone(author, id, artifact(id, to).toString())
        assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
        return receipt.getJSONArray("revisions").getJSONObject(0)
    }
    private fun read(w: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess, ref: JSONObject) =
        w.read(access, ref.getString("object_id"), ref.getInt("revision"))

    @Test fun onlyAddressedAllowedProducerVersionsBecomeDurableExactGrants() {
        val rows = Rows(); val w = workspace(rows)
        val offered = publish(w, "offered")
        val hidden = publish(w, "not-addressed", listOf("other"))
        assertTrue(w.peerUpdates(reader, "", emptySet()).getBoolean("caught_up_at_read"))
        assertNull(read(w, reader, offered))
        val page = w.peerUpdates(reader, "", setOf(author.nodeId))
        assertEquals(1, page.getJSONArray("milestones").length())
        assertEquals("Check alternative offered", page.getJSONArray("milestones").getJSONObject(0)
            .getJSONArray("requests").getJSONObject(0).getString("question"))
        assertNotNull(read(w, w.peerReadAccess(reader), offered))
        assertNull(read(w, w.peerReadAccess(reader), hidden))
        assertNull(read(w, reader, offered))
        assertTrue(w.coordinatorUpdates(reader, "", emptySet(), setOf(author.nodeId)).getBoolean("caught_up_at_read"))
        val before = rows.data.toMap()
        assertEquals(page.toString(), CollaborationResearchWorkspace(rows).peerUpdates(reader, "", emptySet()).toString())
        assertEquals(before, rows.data)
        assertTrue(w.peerUpdates(reader, page.getString("next_cursor"), setOf(author.nodeId)).getBoolean("caught_up_at_read"))
        assertTrue(w.publicationRevisions(author, author.nodeId).isEmpty())
    }

    @Test fun opaqueAndUuidRecipientsBothReceiveOnlyTheirAddressedOriginal() {
        for (id in listOf("turing", "member:primary-7", "f71e12a1-d4dc-4b53-9bfe-e69f081f7826")) {
            val w = CollaborationResearchWorkspace(Rows())
            val recipient = reader.copy(personId = id)
            w.enrollPublication(author, CollaborationResearchStage.EXPLORE)
            w.enrollPublication(recipient, CollaborationResearchStage.EXECUTE)
            val ref = publish(w, "offered", listOf(id))
            val page = w.peerUpdates(recipient, "", setOf(author.nodeId))
            assertEquals(1, page.getJSONArray("milestones").length())
            assertNotNull(read(w, w.peerReadAccess(recipient), ref))
            assertNull(read(w, reader.copy(personId = "unaddressed-display-name"), ref))
        }
    }

    @Test fun coordinatorRequestDoesNotSubstituteForAddressingAPeer() {
        val w = workspace()
        val raw = artifact("coordinator-only").apply {
            remove("requests")
            put("coordination", JSONObject().put("mode", "request")
                .put("decision", "Compare the measured alternatives")
                .put("why_now", "New original evidence is available"))
        }
        val receipt = w.publishMilestone(author, "coordinator-only", raw.toString())
        assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
        val first = w.peerUpdates(reader, "", setOf(author.nodeId))
        assertEquals(0, first.getJSONArray("milestones").length())
        val ref = publish(w, "addressed-peer")
        val next = w.peerUpdates(reader, first.getString("next_cursor"), setOf(author.nodeId))
        assertEquals(1, next.getJSONArray("milestones").length())
        assertNotNull(read(w, w.peerReadAccess(reader), ref))
    }

    @Test fun finalPublicationCanCiteGrantedPeerVersionWithoutChangingDispatchBinding() {
        val rows = Rows(); val w = workspace(rows); val ref = publish(w, "candidate")
        w.peerUpdates(reader, "", setOf(author.nodeId))
        val final = artifact("response", listOf("author"))
        final.getJSONArray("workspace").getJSONObject(0).put("parents", JSONArray().put(ref))
        val receipt = CollaborationResearchWorkspace(rows).submitPublication(reader, final.toString())
        assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
        val saved = w.publicationRevisions(reader, reader.nodeId).single()
        assertEquals(reader.nodeId, saved.getString("node_id"))
        assertEquals(ref.getString("sha256"), saved.getJSONArray("parents").getJSONObject(0).getString("sha256"))
        assertNotNull(w.publicationCheckpoint(reader))
        assertTrue(reader.pinnedReads.isEmpty())
    }

    @Test fun laterVersionsRequireAnotherExplicitOfferAndCursorCannotCrossScopes() {
        val w = workspace(); val ref = publish(w, "candidate")
        val first = w.peerUpdates(reader, "", setOf(author.nodeId))
        val changed = artifact("candidate")
        changed.getJSONArray("workspace").getJSONObject(0).put("object_id", ref.getString("object_id")).put("base_revision", 1)
        val second = w.publishMilestone(author, "candidate-v2", changed.toString()).getJSONArray("revisions").getJSONObject(0)
        assertNull(read(w, w.peerReadAccess(reader), second))
        assertEquals(first.toString(), w.peerUpdates(reader, "", setOf(author.nodeId)).toString())
        w.peerUpdates(reader, first.getString("next_cursor"), setOf(author.nodeId))
        assertNotNull(read(w, w.peerReadAccess(reader), second))
        for (scope in listOf(reader.copy(groupId = "other"), reader.copy(runId = "other"), reader.copy(turnId = "other"),
            reader.copy(round = 2), reader.copy(nodeId = "other"), reader.copy(personId = "other"))) {
            assertThrows(IllegalArgumentException::class.java) { w.peerUpdates(scope, first.getString("next_cursor"), setOf(author.nodeId)) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            w.coordinatorUpdates(reader, first.getString("next_cursor"), emptySet(), emptySet())
        }
    }

    @Test fun observationGrantsAreExactAndAvailableToFinalValidatorAfterReopen() {
        val rows = Rows()
        val observation = JSONObject().put("evidence_id", "a".repeat(64)).put("sha256", "b".repeat(64))
            .put("group_id", author.groupId).put("run_id", author.runId).put("turn_id", author.turnId)
            .put("round", author.round).put("node_id", author.nodeId).put("person_id", author.personId)
        fun open() = CollaborationResearchWorkspace(rows, evidence = { scope, refs ->
            require(scope.canRead(observation)); assertEquals(observation.getString("sha256"), refs.getJSONObject(0).getString("sha256"))
            JSONArray().put(observation)
        })
        val w = open(); w.enrollPublication(author, CollaborationResearchStage.EXPLORE); w.enrollPublication(reader, CollaborationResearchStage.EXECUTE)
        assertEquals("recorded", w.publishMilestone(author, "observed", artifact("observed", observations = JSONArray().put(observation)).toString()).getString("status"))
        w.peerUpdates(reader, "", setOf(author.nodeId))
        val reads = open().peerReadAccess(reader)
        assertTrue(reads.canRead(observation))
        assertFalse(reads.canRead(JSONObject(observation.toString()).put("sha256", "c".repeat(64))))
        assertEquals("recorded", open().submitPublication(reader, artifact("response", observations = JSONArray().put(observation)).toString()).getString("status"))
    }

    @Test fun publicationAndOfferCommitAtomicallyAndRemovalRevokesGrants() {
        val rows = Rows(); val w = workspace(rows); val before = rows.data.toMap()
        rows.fail = true
        assertThrows(IllegalStateException::class.java) { publish(w, "candidate") }
        assertEquals(before, rows.data)
        rows.fail = false; val ref = publish(w, "candidate"); val published = rows.data.toMap()
        rows.fail = true
        assertThrows(IllegalStateException::class.java) { w.peerUpdates(reader, "", setOf(author.nodeId)) }
        assertEquals(published, rows.data)
        assertEquals(reader, w.peerReadAccess(reader))
        rows.fail = false; w.peerUpdates(reader, "", setOf(author.nodeId))
        assertNotNull(read(w, w.peerReadAccess(reader), ref))
        assertThrows(IllegalArgumentException::class.java) { CollaborationResearchWorkspace(rows, accessAuthorized = { false }).peerReadAccess(reader) }
        w.removeGroup(reader.groupId)
        assertTrue(rows.data.keys.none { it.startsWith("group:") })
        assertEquals(reader, w.peerReadAccess(reader))
    }

    @Test fun tamperedRecipientIndexCannotDiscloseAnotherRecipientsPublication() {
        val rows = Rows(); val w = workspace(rows); publish(w, "private", listOf("other"))
        val privateKey = rows.data.keys.single { ":milestone-peer:" in it }
        publish(w, "public")
        val recipientKey = rows.data.keys.single { ":milestone-peer:" in it && it != privateKey }
        val descriptor = JSONObject(rows.data.getValue(privateKey))
        rows.data.remove(recipientKey)
        rows.data[recipientKey.substringBeforeLast(':') + ":" + descriptor.getString("token")] = descriptor.toString()
        assertThrows(IllegalArgumentException::class.java) { w.peerUpdates(reader, "", setOf(author.nodeId)) }
        assertEquals(reader, w.peerReadAccess(reader))
    }

    @Test fun fencedArtifactsAndMultipleRecipientsUseCanonicalRequestsWithoutDuplicates() {
        val rows = Rows(); val w = workspace(rows); val raw = artifact("fenced", listOf("peer", "other", "peer")).toString()
        val receipt = w.publishMilestone(author, "fenced", "```json\n$raw\n```")
        assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
        val before = rows.data.toMap()
        assertEquals(receipt.toString(), w.publishMilestone(author, "fenced", "```json\n$raw\n```").toString())
        assertEquals(before, rows.data)
        val item = w.peerUpdates(reader, "", setOf(author.nodeId)).getJSONArray("milestones").getJSONObject(0)
        assertEquals(listOf("peer"), item.getJSONArray("requests").getJSONObject(0).getJSONArray("to").let { (0 until it.length()).map(it::getString) })
    }

    @Test fun policyAndActiveBindingKeepIndependentOrEndedWorkClosed() {
        fun item() = JSONObject().put("member", "peer").put(CollaborationPeerExchangePolicy.FIELD, JSONArray(listOf("author")))
        assertEquals(setOf("author"), CollaborationPeerExchangePolicy.read(item()))
        for (bad in listOf(item().put("independent_review", true), item().put("member", "author"),
            item().put(CollaborationPeerExchangePolicy.FIELD, "author"), item().put(CollaborationPeerExchangePolicy.FIELD, JSONArray(listOf("author", "author"))),
            item().put(CollaborationPeerExchangePolicy.FIELD, JSONArray(listOf(" author"))))) {
            assertThrows(IllegalArgumentException::class.java) { CollaborationPeerExchangePolicy.read(bad) }
        }
        val member = AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = reader.nodeId,
            context = mapOf("collaboration_group_id" to reader.groupId, CollaborationResearchWorkflow.PERSON to reader.personId,
                CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationGoalLoop.WORK_ID to "work") + CollaborationPeerExchangePolicy.context(item()))
        val checkpoint = AgentTeamExecutionCheckpoint(AgentTeamDefinition("group", "fixture", listOf(member), primaryInstanceId = member.memberId),
            AgentRunRequest(reader.groupId, reader.turnId, "task", runId = reader.runId, goal = "Synthetic task", context = mapOf(CollaborationGoalLoop.ROUND to "1")), emptyMap(), 0)
        assertEquals(member, CollaborationPeerUpdates.member(checkpoint, reader, AgentTeamUserControl.RUN, false))
        for (control in listOf(AgentTeamUserControl.PAUSE, AgentTeamUserControl.STOP))
            assertThrows(IllegalArgumentException::class.java) { CollaborationPeerUpdates.member(checkpoint, reader, control, false) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationPeerUpdates.member(checkpoint, reader, AgentTeamUserControl.RUN, true) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationPeerUpdates.member(checkpoint, reader.copy(nodeId = "other"), AgentTeamUserControl.RUN, false) }
        assertEquals(setOf("author"), CollaborationPeerExchangePolicy.read(CollaborationPeerExchangePolicy.restore(JSONObject().put("member", "peer"), member)))
    }
}
