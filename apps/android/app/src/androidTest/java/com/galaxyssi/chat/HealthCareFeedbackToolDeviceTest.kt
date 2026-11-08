package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareFeedbackToolDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareConcern) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            HealthCareStore(context, names.care).use { test(names, it, issue) }
        } finally { listOf(names.care, names.records, names.privacy, names.reminders, names.profile).forEach(context::deleteDatabase) }
    }
    private fun save(care: HealthCareStore, id: String, number: Int = 1): HealthCareFeedbackReceipt {
        val issue = care.concern(id)!!
        return care.recordActionFeedback(id, issue.revision, issue.actions.first().id, HealthCareFeedbackKind.PARTIAL,
            "合成随访反馈 $number：本次只完成部分行动，不是医疗结论。", UUID.randomUUID().toString(), System.currentTimeMillis() - number)
    }
    private fun grant(names: HealthOverviewDatabases, care: HealthCareStore, issue: HealthCareConcern,
        shared: Boolean = true, target: String = "local-llm"): HealthCareDiscussionGrant {
        val value = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
            care.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version }, "a".repeat(64),
            System.currentTimeMillis(), target, "fixture", "high", profileLink = issue.profileLink,
            questionsShared = true, feedbackHistoryShared = shared)
        care.approveDiscussion(value)
        return value
    }
    private fun read(names: HealthOverviewDatabases, issue: HealthCareConcern, grant: HealthCareDiscussionGrant,
        extra: AgentNativeJsonObject = emptyMap(), conversation: String = grant.conversationId, turn: String = grant.turnId,
        now: Long = System.currentTimeMillis()) = HealthCareFeedbackTool.read(context, names,
        AgentNativeToolInvocationContext(conversationId = conversation, turnId = turn),
        mapOf("input_version" to issue.inputVersion, "revision" to issue.revision) + extra, now)

    private fun research(names: HealthOverviewDatabases, care: HealthCareStore, issue: HealthCareConcern,
        shared: Boolean = true, previous: String? = null): Pair<HealthCareResearchAuthorization, HealthCareDiscussionGrant> {
        val scope = grant(names, care, issue, shared)
        val authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), scope, "b".repeat(64))
        care.authorizeResearch(authorization, previous)
        val job = care.queueResearch(authorization.id, issue.id, System.currentTimeMillis())
        val approved = scope.copy(turnId = job.turnId, revision = job.revision, researchAuthorizationId = authorization.id)
        care.approveDiscussion(approved)
        return authorization to approved
    }

    @Test fun researchHistoryConsentAndCursorSurviveDatabaseReopen(): Unit = fixture { names, care, initial ->
        val expected = (1..35).map { save(care, initial.id, it).revision }.reversed()
        val issue = care.concern(initial.id)!!
        val (authorization, approval) = research(names, care, issue)
        val first = read(names, issue, approval)
        assertEquals(30, first.getJSONArray("items").length())
        HealthCareStore(context, names.care).use { reopened ->
            assertEquals(authorization, reopened.researchAuthorization(issue.id))
            assertEquals(approval, reopened.discussionGrant(approval.turnId))
            assertTrue(reopened.researchGrantCurrent(approval))
        }
        val second = read(names, issue, approval, mapOf("before_revision" to first.getInt("next")))
        val revisions = listOf(first, second).flatMap { page -> val rows = page.getJSONArray("items")
            (0 until rows.length()).map { rows.getJSONObject(it).getInt("revision") } }
        assertEquals(expected, revisions); assertTrue(second.getBoolean("done"))
        assertEquals(issue, care.concern(issue.id)); assertNull(care.nextDue())
    }
    @Test fun researchWithoutHistoryConsentCannotEscalateItsTurn(): Unit = fixture { names, care, issue ->
        val (_, approval) = research(names, care, issue, shared = false)
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval) }
        assertThrows(HealthCareConflict::class.java) { care.approveDiscussion(approval.copy(feedbackHistoryShared = true)) }
        assertFalse(care.researchGrantCurrent(approval.copy(feedbackHistoryShared = true)))
    }
    @Test fun narrowingResearchConsentCancelsPreparedTurnAndBlocksNextPage(): Unit = fixture { names, care, initial ->
        repeat(31) { save(care, initial.id, it) }
        val issue = care.concern(initial.id)!!
        val (old, approval) = research(names, care, issue)
        val page = read(names, issue, approval)
        val (_, narrowed) = research(names, care, issue, shared = false, previous = old.id)
        assertEquals(HealthCareResearchState.CANCELLED, care.researchJob(approval.turnId)!!.state)
        assertTrue(care.researchJob(approval.turnId)!!.cancellationPending)
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval, mapOf("before_revision" to page.getInt("next"))) }
        assertThrows(HealthCareConflict::class.java) { read(names, issue, narrowed) }
        assertFalse(care.researchAuthorization(issue.id)!!.scope.feedbackHistoryShared)
    }
    @Test fun revokedResearchHistoryCannotBeReadEvenWithPersistedTurnGrant(): Unit = fixture { names, care, initial ->
        save(care, initial.id)
        val issue = care.concern(initial.id)!!; val (authorization, approval) = research(names, care, issue)
        read(names, issue, approval)
        care.revokeResearch(issue.id, authorization.id, System.currentTimeMillis())
        assertEquals(approval, care.discussionGrant(approval.turnId))
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval) }
        assertEquals(1, care.feedback(issue.id).items.size)
    }
    @Test fun freshFeedbackNeedsNewResearchTurnButNotNewStandingConsent(): Unit = fixture { names, care, initial ->
        save(care, initial.id)
        val issue = care.concern(initial.id)!!; val (authorization, approval) = research(names, care, issue)
        read(names, issue, approval)
        save(care, issue.id, 2)
        val current = care.concern(issue.id)!!
        assertThrows(HealthCareConflict::class.java) { read(names, current, approval) }
        val job = care.queueResearch(authorization.id, issue.id, System.currentTimeMillis())
        assertNotEquals(approval.turnId, job.turnId)
        val next = approval.copy(turnId = job.turnId, revision = job.revision, approvedAt = System.currentTimeMillis())
        care.approveDiscussion(next)
        assertEquals(2, read(names, current, next).getJSONArray("items").length())
        assertEquals(authorization, care.researchAuthorization(issue.id))
    }
    @Test fun terminalResearchJobCannotKeepReadingHistory(): Unit = fixture { names, care, issue ->
        val (_, approval) = research(names, care, issue)
        val job = care.researchJob(approval.turnId)!!
        val running = care.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
        read(names, issue, approval)
        care.updateResearchJob(running, HealthCareResearchState.COMPLETED)
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval) }
    }

    @Test fun allSeventyFiveEntriesPageWithoutLossDuplicationOrWrites(): Unit = fixture { names, care, initial ->
        val expected = (1..75).map { save(care, initial.id, it) }
        val issue = care.concern(initial.id)!!; val approval = grant(names, care, issue)
        val rows = mutableListOf<JSONObject>(); var next: Int? = null
        do {
            val page = read(names, issue, approval, next?.let { mapOf("before_revision" to it) } ?: emptyMap())
            val items = page.getJSONArray("items"); assertTrue(items.length() <= 30)
            repeat(items.length()) { rows += items.getJSONObject(it) }
            next = if (page.isNull("next")) null else page.getInt("next")
            assertEquals(next == null, page.getBoolean("done"))
        } while (next != null)
        assertEquals(expected.reversed().map { it.revision }, rows.map { it.getInt("revision") })
        assertEquals(75, rows.map { it.getInt("revision") }.toSet().size)
        assertEquals(expected.reversed().map { it.feedback.note }, rows.map { it.getString("note") })
        assertEquals(issue, care.concern(issue.id)); assertNull(care.nextDue())
    }
    @Test fun emptyHistoryIsNotFabricatedFromLegacyActionNotes(): Unit = fixture { names, care, initial ->
        val legacy = care.update(initial.id, initial.revision, "fixture_legacy") { it.copy(actions = it.actions.map { action ->
            action.copy(state = HealthCareActionState.DONE, outcome = "历史摘要不是独立随访记录") }) }
        val approval = grant(names, care, legacy)
        val page = read(names, legacy, approval)
        assertEquals(0, page.getJSONArray("items").length()); assertTrue(page.getBoolean("done")); assertTrue(page.isNull("next"))
    }
    @Test fun explicitGrantSurvivesReopenAndRepeatedReadsDoNotCreateFeedback(): Unit = fixture { names, care, initial ->
        save(care, initial.id)
        val issue = care.concern(initial.id)!!; val approval = grant(names, care, issue)
        val first = read(names, issue, approval).toString()
        repeat(3) { assertEquals(first, read(names, issue, approval).toString()) }
        HealthCareStore(context, names.care).use { reopened ->
            assertEquals(approval, reopened.discussionGrant(approval.turnId)); assertEquals(1, reopened.feedback(issue.id).items.size)
            assertEquals(issue, reopened.concern(issue.id))
        }
    }
    @Test fun oldGrantCannotBeSilentlyExpandedOrReadHistory(): Unit = fixture { names, care, issue ->
        val old = grant(names, care, issue, shared = false)
        assertThrows(HealthCareConflict::class.java) { read(names, issue, old) }
        assertThrows(HealthCareConflict::class.java) { care.approveDiscussion(old.copy(feedbackHistoryShared = true)) }
        assertFalse(care.discussionGrant(old.turnId)!!.feedbackHistoryShared)
    }
    @Test fun unrelatedConversationTurnAndSnapshotAreRejected(): Unit = fixture { names, care, issue ->
        val approval = grant(names, care, issue)
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval, conversation = UUID.randomUUID().toString()) }
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval, turn = UUID.randomUUID().toString()) }
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval, mapOf("revision" to issue.revision - 1)) }
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval, mapOf("input_version" to "other")) }
        assertThrows(IllegalArgumentException::class.java) { read(names, issue, approval, mapOf("before_revision" to issue.revision + 1)) }
        assertThrows(IllegalArgumentException::class.java) { read(names, issue, approval, mapOf("concern" to UUID.randomUUID().toString())) }
    }
    @Test fun newFeedbackInvalidatesOutstandingPagesUntilNewApproval(): Unit = fixture { names, care, initial ->
        save(care, initial.id)
        val issue = care.concern(initial.id)!!; val approval = grant(names, care, issue)
        read(names, issue, approval)
        save(care, initial.id, 2)
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval) }
        val updated = care.concern(initial.id)!!
        assertEquals(2, read(names, updated, grant(names, care, updated)).getJSONArray("items").length())
    }
    @Test fun privacyRevocationAndExpiryBlockReadWithoutDeletingFeedback(): Unit = fixture { names, care, initial ->
        save(care, initial.id)
        val issue = care.concern(initial.id)!!; val approval = grant(names, care, issue)
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval, now = approval.approvedAt - 1) }
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval, now = approval.approvedAt + HealthCareDiscussionPolicy.MAX_APPROVAL_AGE) }
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
        assertThrows(HealthCareConflict::class.java) { read(names, issue, approval) }
        assertEquals(1, care.feedback(issue.id).items.size)
    }
    @Test fun sourceCorrectionIsRejectedBeforeConcernReconciliation(): Unit = fixture { names, care, initial ->
        val approval = grant(names, care, initial)
        HealthRecordStore(context, names.records).use { records ->
            records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.2"), "mmol/L", System.currentTimeMillis() - 1))
        }
        assertThrows(HealthCareConflict::class.java) { read(names, initial, approval) }
    }
    @Test fun remoteProviderCannotReadWhenOnlineAnalysisIsDisabled(): Unit = fixture { names, care, issue ->
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            if (privacy.policy().online) privacy.change(HealthPrivacyOption.ONLINE_ANALYSIS, false, privacy.policy().version)
        }
        HealthCareEngine.evaluate(context, names)
        val current = care.concern(issue.id)!!
        val approval = grant(names, care, current, target = "fixture-cloud")
        assertThrows(HealthCareConflict::class.java) { read(names, current, approval) }
        val local = grant(names, care, current)
        assertTrue(read(names, current, local).getBoolean("done"))
    }
    @Test fun archivedActionsRemainHistoryNotActivePlan(): Unit = fixture { names, care, initial ->
        val saved = save(care, initial.id)
        val current = care.concern(initial.id)!!
        val archived = care.update(current.id, current.revision, "fixture_archive") { it.copy(actions = emptyList()) }
        val page = read(names, archived, grant(names, care, archived)).getJSONArray("items").getJSONObject(0)
        assertEquals(saved.feedback.note, page.getString("note")); assertFalse(page.getBoolean("action_in_current_plan"))
        assertTrue(page.isNull("current_action_state")); assertFalse(page.getBoolean("health_improvement_verified"))
    }
    @Test fun deletedConcernCannotBeRecoveredThroughAnOldGrant(): Unit = fixture { names, care, initial ->
        val approval = grant(names, care, initial)
        care.delete(initial.id, initial.revision)
        assertThrows(HealthCareConflict::class.java) { read(names, initial, approval) }
    }
}
