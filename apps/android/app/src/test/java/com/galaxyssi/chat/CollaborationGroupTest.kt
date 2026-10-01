package com.galaxyssi.chat

import java.io.File
import org.junit.Assert.*
import org.junit.Test

class CollaborationGroupTest {
    private fun member(name: String = "Turing") = CollaborationMember(name = name,
        agentId = "codex:desktop", providerLabel = "Codex", role = "Review evidence", modelId = "gpt-6-sol")

    @Test fun catalogContains1024DistinctEnglishNames() {
        val names = File("src/main/assets/collaboration/agent-names.txt").readLines()
        assertEquals(1024, CollaborationNamePolicy.validate(names).size)
        assertEquals("Turing", CollaborationNamePolicy.allocate(names, emptyList()))
        assertNotEquals("Turing", CollaborationNamePolicy.allocate(names, listOf("TURING")))
    }

    @Test fun providerChangesPreserveIdentityAndResponsibilities() {
        val before = member()
        val after = before.copy(agentId = "deepseek", providerLabel = "DeepSeek", modelId = "deepseek-chat")
        assertEquals(before.id, after.id)
        assertEquals(before.role, after.role)
        assertEquals(before.requested("group").instanceId, after.requested("group").instanceId)
        assertNotEquals(before.requested("group").agentId, after.requested("group").agentId)
    }

    @Test fun sameProviderHasIndependentPersistentInstances() {
        val group = CollaborationGroup("group", listOf(member(), member("Curie")))
        val requests = group.requested(emptyList())
        assertEquals(1, requests.map { it.agentId }.distinct().size)
        assertEquals(2, requests.map { it.instanceId }.distinct().size)
        assertTrue(requests.all { it.collaborationGroupId == "group" && it.modelId == "gpt-6-sol" })
    }

    @Test fun onlySentMessageEligibleMembersAreSelectedAutomatically() {
        val mention = member("Hopper").copy(participation = CollaborationParticipation.MENTION_ONLY)
        val muted = member("Curie").copy(observeMessages = false)
        val group = CollaborationGroup("group", listOf(member(), mention, muted))
        assertEquals(listOf("Turing"), group.requested(emptyList()).map { it.displayName })
        assertEquals("Hopper", group.requested(listOf(mention.requested("group"))).single().displayName)
    }

    @Test fun independentReviewDoesNotReceivePeerEvidence() {
        assertFalse(member().copy(independentReview = true).requested("group").receivePeerResults)
        assertFalse(member().copy(receiveResults = false).requested("group").receivePeerResults)
        assertTrue(member().requested("group").receivePeerResults)
    }

    @Test fun settingsRoundTripIncludingCoordinatorAndModel() {
        val a = member()
        val b = member("Hopper").copy(participation = CollaborationParticipation.PROACTIVE, independentReview = true)
        val group = CollaborationGroup("group", listOf(a, b), b.id, 4)
        assertEquals(group, CollaborationGroupCodec.decode(CollaborationGroupCodec.encode(group)))
        assertEquals(b.id, group.requested(emptyList()).first().instanceId)
    }

    @Test fun restoredPlainTextDraftMentionsResolveToStableMembersWithoutMatchingEmail() {
        val short = member("Alan")
        val long = member("Alan Turing")
        val curie = member("Curie")
        assertEquals(listOf(long.id, curie.id), CollaborationMentionPolicy.resolve(
            "@Alan Turing review; @curie verify; @Curie again. mail@Alan", listOf(short, long, curie)).map { it.id })
        assertTrue(CollaborationMentionPolicy.resolve("mail@Alan @Alana", listOf(short)).isEmpty())
    }

    @Test fun invalidAndDuplicateNamesFailClosed() {
        assertNull(CollaborationGroupCodec.decode("{}"))
        assertTrue(runCatching { CollaborationGroup("group", listOf(member(), member("turing"))).validate() }.isFailure)
    }

    @Test fun resultFanoutIsBoundedDeduplicatedAndExcludesSelfPrimaryAndIndependentReview() {
        fun snapshotMember(id: String, receive: Boolean = true, status: AgentSubagentStatus = AgentSubagentStatus.RUNNING) =
            AgentTeamMemberSnapshot("codex", "review", AgentDeliveryMode.OBSERVE, status,
                output = if (status == AgentSubagentStatus.SUCCEEDED) "evidence" else "",
                instanceId = id, displayName = id, collaborationGroupId = "group", receivePeerResults = receive)
        val snapshot = AgentTeamExecutionSnapshot("run", "team", "group", "task", "codex", "goal",
            AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.RUNNING,
            listOf(snapshotMember("author", status = AgentSubagentStatus.SUCCEEDED), snapshotMember("recipient"),
                snapshotMember("independent", receive = false), snapshotMember("primary")), primaryInstanceId = "primary")
        val first = CollaborationPeerResultPolicy.messages(snapshot)
        assertEquals(listOf("recipient"), first.map { it.toInstanceId })
        val mailbox = InMemoryAgentTeamMailbox()
        (first + CollaborationPeerResultPolicy.messages(snapshot)).forEach(mailbox::append)
        assertEquals(1, mailbox.messages("run").size)
        val revised = snapshot.copy(members = snapshot.members.map {
            if (it.memberId == "author") it.copy(output = "corrected evidence") else it
        })
        CollaborationPeerResultPolicy.messages(revised).forEach(mailbox::append)
        assertEquals(2, mailbox.messages("run").size)
        assertTrue(CollaborationPeerResultPolicy.messages(snapshot.copy(state = AgentTeamExecutionState.SUCCEEDED)).isEmpty())
    }

    @Test fun creatingGroupDoesNotCreateAnActiveProcessTimer() {
        val created = AgentTranscriptEntry("created", AgentTranscriptRole.PROCESS, "Group created", 1,
            conversationId = "group", dedupeKey = "collaboration-created:group")
        assertTrue(AgentTranscriptPresentationPolicy.collapseProcessGroups(listOf(created)).isEmpty())
        assertEquals(1, AgentTranscriptPresentationPolicy.collapseProcessGroups(listOf(
            created.copy(dedupeKey = "real-progress", taskId = "task"))).size)
    }

    @Test fun aggregateDeduplicationNeverDropsRichDeliverables() {
        val metadata = CollaborationTranscriptMetadata("member", "Turing", "Codex", "review",
            AgentSubagentStatus.SUCCEEDED, "run", result = true, primary = true)
        val member = AgentTranscriptEntry("member", AgentTranscriptRole.PROCESS, "Result", 2,
            conversationId = "group", taskId = "task", collaborationJson = metadata.encode())
        val aggregate = AgentTranscriptEntry("aggregate", AgentTranscriptRole.ASSISTANT, "Result", 3,
            conversationId = "group", taskId = "task")
        assertEquals(listOf(aggregate.copy(collaborationJson = metadata.encode())),
            AgentTranscriptPresentationPolicy.collapseProcessGroups(listOf(member, aggregate)))
        val image = aggregate.copy(richOutputJson = "{\"type\":\"image\",\"attachmentId\":\"photo\"}")
        val rows = AgentTranscriptPresentationPolicy.collapseProcessGroups(listOf(member, image))
        assertEquals(1, rows.size)
        assertEquals(image.richOutputJson, rows.single().richOutputJson)
        assertEquals(AgentTranscriptRole.ASSISTANT, rows.single().role)
    }

    @Test fun memberRowsSurviveProcessCollapsingAndStatusChangesInvalidateOnlyThatRow() {
        val metadata = CollaborationTranscriptMetadata("member", "Turing", "Codex", "review",
            AgentSubagentStatus.RUNNING, "run")
        val user = AgentTranscriptEntry("user", AgentTranscriptRole.USER, "Question", 1, conversationId = "group", turnId = "turn")
        val status = AgentTranscriptEntry("status", AgentTranscriptRole.PROCESS, "review", 2,
            dedupeKey = "collaboration:run:member:status", conversationId = "group", turnId = "turn", collaborationJson = metadata.encode())
        val result = status.copy(id = "result", dedupeKey = "collaboration:run:member:result", text = "evidence",
            collaborationJson = metadata.copy(status = AgentSubagentStatus.SUCCEEDED, result = true).encode())
        assertEquals(listOf(user, status, result), AgentTranscriptPresentationPolicy.collapseProcessGroups(listOf(user, status, result)))
        val completed = status.copy(collaborationJson = metadata.copy(status = AgentSubagentStatus.SUCCEEDED).encode())
        assertTrue(AgentTranscriptRenderPolicy.sameItem(status, completed))
        assertFalse(AgentTranscriptRenderPolicy.sameContent(status, completed))
        assertEquals(metadata, CollaborationTranscriptMetadata.decode(metadata.encode()))
    }
}
