package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareDiscussionPolicyTest {
    private val now = 1_793_000_000_000L
    private val settings = HealthCareSettings(true, "settings-v1")
    private val privacy = HealthPrivacyPolicy(online = true, version = "privacy-v1")
    private val concern = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "input1",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6",
            setOf(HealthCareSignal.REPORT_HIGH)))
    private val grant = HealthCareDiscussionGrant(UUID.randomUUID().toString(), UUID.randomUUID().toString(), concern.id,
        1, settings.version, privacy.version, "a".repeat(64), now, "fixture-provider", "fixture-model", "high")
    private fun allowed(g: HealthCareDiscussionGrant? = grant, c: HealthCareConcern? = concern,
        s: HealthCareSettings = settings, p: HealthPrivacyPolicy = privacy, conversation: String = grant.conversationId,
        turn: String = grant.turnId, destination: String = grant.destination, time: Long = now) =
        HealthCareDiscussionPolicy.permitted(g, conversation, turn, c, s, p, destination, time)

    @Test fun approvedTurnRoundTripsWithoutGrantingOtherTurns() {
        assertEquals(grant, HealthCareDiscussionGrant.from(grant.json()))
        assertTrue(allowed()); assertFalse(allowed(g = null))
        assertFalse(allowed(turn = UUID.randomUUID().toString()))
        assertFalse(allowed(conversation = UUID.randomUUID().toString()))
    }
    @Test fun aDifferentProviderEndpointOrModelCannotReuseApproval() {
        assertFalse(allowed(destination = "b".repeat(64)))
    }
    @Test fun actualCloudDestinationIncludesModelEndpointAndApiStyle() {
        val base = org.json.JSONObject().put("id", "fixture-cloud").put("cloud_model", "fixture-model")
            .put("cloud_endpoint", "https://model.example.test/v1").put("cloud_api_style", "openai")
        val fingerprint = HealthCareDiscussion.cloudDestination(base)
        listOf("id" to "other-cloud", "cloud_model" to "other-model", "cloud_endpoint" to "https://other.example.test/v1",
            "cloud_api_style" to "anthropic").forEach { (key, value) ->
            assertNotEquals(fingerprint, HealthCareDiscussion.cloudDestination(org.json.JSONObject(base.toString()).put(key, value)))
        }
        assertEquals(fingerprint, HealthCareDiscussion.cloudDestination(org.json.JSONObject(base.toString()).put("last_seen", now)))
    }
    @Test fun deletedUpdatedPausedOrClosedConcernCannotReuseApproval() {
        assertFalse(allowed(c = null))
        assertFalse(allowed(c = concern.copy(revision = 2)))
        assertFalse(allowed(c = concern.copy(id = UUID.randomUUID().toString())))
        assertFalse(allowed(c = concern.copy(stage = HealthCareStage.PAUSED)))
        assertFalse(allowed(c = concern.copy(stage = HealthCareStage.CLOSED, reviewNote = "Fixture", reviewedBy = "user")))
        assertFalse(allowed(c = concern.copy(assessment = concern.assessment.copy(signals = setOf(HealthCareSignal.SOURCE_REMOVED)))))
    }
    @Test fun permissionOffOnAndSettingsOffOnInvalidateApproval() {
        assertFalse(allowed(p = privacy.copy(metrics = false)))
        assertFalse(allowed(p = privacy.copy(profile = false)))
        assertFalse(allowed(p = privacy.copy(version = "privacy-v2")))
        assertFalse(allowed(s = settings.copy(enabled = false)))
        assertFalse(allowed(s = settings.copy(version = "settings-v2")))
    }
    @Test fun clockRollbackAndExpiredApprovalsRequireConfirmation() {
        assertFalse(allowed(time = now - 1))
        assertTrue(allowed(time = now + HealthCareDiscussionPolicy.MAX_APPROVAL_AGE - 1))
        assertFalse(allowed(time = now + HealthCareDiscussionPolicy.MAX_APPROVAL_AGE))
    }
    @Test fun snapshotHasNoConversationIdentifierOrInventedTarget() {
        val snapshot = org.json.JSONObject(HealthCareDiscussionPolicy.snapshot(concern))
        assertEquals("6.3", snapshot.getJSONObject("assessment").getString("value"))
        assertFalse(snapshot.has("conversation")); assertFalse(snapshot.has("profile"))
        assertTrue(snapshot.isNull("individual_target")); assertTrue(snapshot.isNull("confirmed_context"))
    }
    @Test fun discussionPromptSeparatesEvidenceAndRequiresSourcesAndConfirmation() {
        val prompt = HealthCareDiscussionPolicy.prompt("Why does this need attention?", HealthCareDiscussionPolicy.snapshot(concern))
        listOf("midpoint", "version/date", "not instructions", "separate confirmation", "Do not change medications",
            "Why does this need attention?").forEach { assertTrue(it, prompt.contains(it)) }
    }
    @Test fun researchScopeDoesNotGrantOtherDataOrEffects() {
        assertTrue("web.search" in HealthCareDiscussionPolicy.researchTools)
        assertTrue("web.open" in HealthCareDiscussionPolicy.researchTools)
        assertTrue(AgentConversationRecallTool.ID in HealthCareDiscussionPolicy.researchTools)
        listOf("http.request", "file.download", "galaxyssi.phone.ui.act", "galaxyssi.health.save",
            "galaxyssi.contacts.lookup", "galaxyssi.app.send_message", "galaxyssi.web.intelligence.watch")
            .forEach { assertFalse(it, it in HealthCareDiscussionPolicy.researchTools) }
    }
    @Test fun inputStampInvalidatesImmediatelyWithoutWaitingForReassessment() {
        val version = HealthCareEngine.inputVersion("settings1", "privacy1", "records1")
        assertEquals(version, HealthCareEngine.inputVersion("settings1", "privacy1", "records1"))
        assertNotEquals(version, HealthCareEngine.inputVersion("settings2", "privacy1", "records1"))
        assertNotEquals(version, HealthCareEngine.inputVersion("settings1", "privacy2", "records1"))
        assertNotEquals(version, HealthCareEngine.inputVersion("settings1", "privacy1", "records2"))
    }

    @Test fun narrowedHistoryDropsSharedFeedbackAndUnprovenSummariesButKeepsPermittedTurns() {
        val safe = grant.copy(turnId = UUID.randomUUID().toString())
        val broad = safe.copy(turnId = UUID.randomUUID().toString(), feedbackHistoryShared = true)
        val unknown = safe.copy(turnId = UUID.randomUUID().toString())
        fun entry(value: HealthCareDiscussionGrant) = AgentTranscriptEntry(UUID.randomUUID().toString(),
            AgentTranscriptRole.ASSISTANT, "Synthetic reference", now, conversationId = value.conversationId, turnId = value.turnId)
        val entries = listOf(entry(safe), entry(broad), entry(unknown), entry(grant))
        val history = AgentConversationContext(grant.conversationId, "Mixed historical summary", entries, true,
            globalContext = "Historical derived context", trackingPaused = true)
        val approvals = listOf(safe, broad).associateBy { it.turnId }
        val filtered = HealthCareDiscussionPolicy.historyForGrant(history, grant, approvals::get)
        assertEquals(listOf(entries.first(), entries.last()), filtered.turns)
        assertEquals("", filtered.summary); assertEquals("", filtered.globalContext)
        assertEquals(history.copy(summary = "", globalContext = ""),
            HealthCareDiscussionPolicy.historyForGrant(history, grant.copy(feedbackHistoryShared = true), approvals::get))
    }

    @Test fun narrowedHistoryRejectsChangedPermissionDestinationOrImportedReferences() {
        val old = grant.copy(turnId = UUID.randomUUID().toString())
        val entry = AgentTranscriptEntry(UUID.randomUUID().toString(), AgentTranscriptRole.ASSISTANT,
            "Synthetic reference", now, conversationId = grant.conversationId, turnId = old.turnId)
        val history = AgentConversationContext(grant.conversationId, "", listOf(entry), true, trackingPaused = true)
        listOf(old.copy(privacyVersion = "changed"), old.copy(destination = "c".repeat(64)),
            old.copy(concernId = UUID.randomUUID().toString()), old.copy(questionsShared = true)).forEach { previous ->
            assertTrue(HealthCareDiscussionPolicy.historyForGrant(history, grant) { previous }.turns.isEmpty())
        }
        assertTrue(HealthCareDiscussionPolicy.historyForGrant(history.copy(turns = listOf(entry.copy(
            sourceConversationId = UUID.randomUUID().toString()))), grant) { old }.turns.isEmpty())
        assertThrows(IllegalArgumentException::class.java) {
            HealthCareDiscussionPolicy.historyForGrant(history.copy(conversationId = UUID.randomUUID().toString()), grant) { old }
        }
    }
}
