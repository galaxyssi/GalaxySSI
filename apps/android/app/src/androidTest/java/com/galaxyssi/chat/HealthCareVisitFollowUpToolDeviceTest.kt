package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareVisitFollowUpToolDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (HealthCareVisitFollowUpFixture) -> Unit) = HealthCareVisitFollowUpFixture(context).use { it.start(); test(it) }
    private fun approve(f: HealthCareVisitFollowUpFixture, shared: Boolean = true, target: String = "local-llm"): HealthCareDiscussionGrant {
        val snapshot = f.snapshot(); val issue = snapshot.visit.issue
        val grant = HealthCareDiscussionGrant(issue.conversationId, id(), issue.id, issue.revision, snapshot.visit.settingsVersion,
            snapshot.visit.privacy.version, "a".repeat(64), System.currentTimeMillis(), target, "fixture", "high", profileLink = issue.profileLink,
            questionsShared = !shared, visitFollowUp = if (shared) HealthCareVisitFollowUpScope.of(snapshot.followUp!!, snapshot.visit.selected!!) else null)
        HealthCareStore(context, f.names.care).use { it.approveDiscussion(grant) }; return grant
    }
    private fun read(f: HealthCareVisitFollowUpFixture, grant: HealthCareDiscussionGrant, input: AgentNativeJsonObject = emptyMap(),
        conversation: String = grant.conversationId, turn: String = grant.turnId, now: Long = System.currentTimeMillis()) =
        HealthCareVisitFollowUpTool.read(context, f.names, AgentNativeToolInvocationContext(conversationId = conversation, turnId = turn),
            mapOf("revision" to grant.revision) + input, now)
    @Test fun allEntriesPageWithoutLossAndReadsDoNotChangeClinicalState(): Unit = fixture { f ->
        repeat(34) { f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "合成随访 $it")) }
        val before = f.snapshot(); val grant = approve(f); val rows = mutableListOf<JSONObject>(); var next: Int? = null
        do {
            val result = read(f, grant, next?.let { mapOf("before_revision" to it) } ?: emptyMap())
            val items = result.getJSONArray("items"); assertTrue(items.length() <= 8)
            repeat(items.length()) { rows += items.getJSONObject(it) }
            next = if (result.isNull("next")) null else result.getInt("next")
        } while (next != null)
        assertEquals(35, rows.size); assertEquals(35, rows.map { it.getInt("revision") }.toSet().size)
        assertEquals(rows.map { it.getInt("revision") }.sortedDescending(), rows.map { it.getInt("revision") })
        assertEquals(before, f.snapshot())
        HealthCareStore(context, f.names.care).use { assertTrue(it.reminders(f.issue.id).isEmpty()); assertEquals(grant, it.discussionGrant(grant.turnId)) }
    }
    @Test fun longFieldsReadInExactChunksAndCannotReadOtherEntry(): Unit = fixture { f ->
        val text = "合成困难记录".repeat(250)
        val value = f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = text))
        val grant = approve(f); val received = StringBuilder(); var offset = 0
        do {
            val page = read(f, grant, mapOf("entry_revision" to value.value.revision, "field" to "note", "offset" to offset))
            assertTrue(page.toString().length < 1200); received.append(page.getString("text"))
            offset = if (page.isNull("next_offset")) -1 else page.getInt("next_offset")
        } while (offset >= 0)
        assertEquals(text, received.toString())
        assertThrows(HealthCareConflict::class.java) { read(f, grant, mapOf("entry_revision" to 1, "field" to "note")) }
        assertThrows(IllegalArgumentException::class.java) { read(f, grant, mapOf("entry_revision" to value.value.revision, "field" to "note", "offset" to text.length + 1)) }
    }
    @Test fun oldDiscussionGrantCannotReadOrBeExpanded(): Unit = fixture { f ->
        val old = approve(f, shared = false)
        assertThrows(HealthCareConflict::class.java) { read(f, old) }
        val scope = HealthCareVisitFollowUpScope.of(f.snapshot().followUp!!, f.visit)
        HealthCareStore(context, f.names.care).use { care ->
            assertThrows(HealthCareConflict::class.java) { care.approveDiscussion(old.copy(questionsShared = false, visitFollowUp = scope)) }
        }
    }
    @Test fun wrongConversationTurnRevisionAndJournalAreRejected(): Unit = fixture { f ->
        val grant = approve(f)
        assertThrows(HealthCareConflict::class.java) { read(f, grant, conversation = id()) }
        assertThrows(HealthCareConflict::class.java) { read(f, grant, turn = id()) }
        assertThrows(HealthCareConflict::class.java) { read(f, grant, mapOf("revision" to grant.revision - 1)) }
        HealthCareStore(context, f.names.care).use { care ->
            assertThrows(HealthCareConflict::class.java) { care.approveDiscussion(grant.copy(turnId = id(), visitFollowUp = grant.visitFollowUp!!.copy(id = id()))) }
        }
    }
    @Test fun newCheckinInvalidatesExistingPageAndFreshApprovalWorks(): Unit = fixture { f ->
        val grant = approve(f); read(f, grant)
        f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "新的合成记录"))
        assertThrows(HealthCareConflict::class.java) { read(f, grant) }
        assertEquals(2, read(f, approve(f)).getJSONArray("items").length())
    }
    @Test fun visitRevisionChangeRejectsPriorSelectionAndReportsReviewGap(): Unit = fixture { f ->
        val grant = approve(f)
        HealthCareStore(context, f.names.care).use { care ->
            care.saveEncounter(f.issue.id, care.concern(f.issue.id)!!.revision, f.visit.id, f.visit.revision,
                f.visit.details.copy(note = "合成就诊修订"), id(), System.currentTimeMillis())
            assertThrows(HealthCareConflict::class.java) { HealthCareVisitFollowUpTool.selected(care, f.issue.id, grant.visitFollowUp!!) }
        }
        assertThrows(HealthCareConflict::class.java) { read(f, grant) }
        assertTrue(read(f, approve(f)).getJSONArray("items").getJSONObject(0).getBoolean("source_review_required"))
    }
    @Test fun revokedPrivacyAndExpiredGrantsBlockReads(): Unit = fixture { f ->
        val grant = approve(f)
        assertThrows(HealthCareConflict::class.java) { read(f, grant, now = grant.approvedAt + HealthCareDiscussionPolicy.MAX_APPROVAL_AGE) }
        HealthPrivacyStore(context, f.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertThrows(HealthCareConflict::class.java) { read(f, grant) }
    }
    @Test fun deletedJournalCannotBeReadByOldGrant(): Unit = fixture { f ->
        val grant = approve(f); f.repository.delete(f.snapshot())
        assertThrows(HealthCareConflict::class.java) { read(f, grant) }
    }
    @Test fun remoteProviderRequiresOnlineAnalysisButLocalStillWorks(): Unit = fixture { f ->
        HealthPrivacyStore(context, f.names.privacy).use { if(it.policy().online) it.change(HealthPrivacyOption.ONLINE_ANALYSIS, false, it.policy().version) }
        HealthCareEngine.evaluate(context, f.names)
        assertThrows(HealthCareConflict::class.java) { read(f, approve(f, target = "fixture-remote")) }
        assertEquals(1, read(f, approve(f)).getJSONArray("items").length())
    }
    @Test fun sourceCorrectionBlocksReadsBeforeReconciliation(): Unit = fixture { f ->
        val grant = approve(f)
        HealthRecordStore(context, f.names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.2"), "mmol/L", System.currentTimeMillis() - 1)) }
        assertThrows(HealthCareConflict::class.java) { read(f, grant) }
    }
}
