package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ProactiveAttentionPolicyTest {
    private val topics = ProactiveAttentionPolicy.defaults((1..31).map { "Topic $it" })
    private val active = AttentionPreferences(configured = true, topics = topics)
    private val verified = GlobalEvidenceLedger(verified = true, primarySourceCount = 1, freshSourceCount = 1)

    @Test fun defaultCategoriesAreUniqueAndAllSelected() {
        assertEquals(31, topics.size)
        assertEquals(31, topics.map { it.id }.toSet().size)
        assertTrue(topics.all { it.enabled && it.query.isNotBlank() })
        assertEquals(AttentionAlertMode.IMPORTANT, active.alertMode)
    }

    @Test fun catalogContainsAllFourGroupsAndCustomTopicsRemainSeparate() {
        assertEquals(mapOf(AttentionTopicGroup.FINANCE to 15, AttentionTopicGroup.TECHNOLOGY to 7,
            AttentionTopicGroup.GALAXYSSI to 5, AttentionTopicGroup.RESEARCH to 4),
            topics.groupingBy { ProactiveAttentionPolicy.group(it.id) }.eachCount())
        assertEquals(AttentionTopicGroup.CUSTOM, ProactiveAttentionPolicy.group("custom-example"))
    }

    @Test fun upgradeAddsSixteenTopicsWithoutResettingEditedDisabledOrCustomTopics() {
        val legacy = topics.take(15).map { if (it.id == "macro") it.copy(title = "My topic", query = "My scope", enabled = false) else it }
        val custom = AttentionTopic("custom-example", "Custom", "Private scope", false)
        val merged = ProactiveAttentionPolicy.mergeTopics(topics, legacy + custom)
        assertEquals(32, merged.size)
        assertEquals(legacy, merged.take(15))
        assertEquals(16, merged.drop(15).count { it.enabled })
        assertEquals(custom, merged.last())
        assertEquals(merged, ProactiveAttentionPolicy.mergeTopics(topics, merged))
        val disabled = merged.map { if (it.id == "ai_models") it.copy(enabled = false) else it }
        assertFalse(ProactiveAttentionPolicy.mergeTopics(topics, disabled).first { it.id == "ai_models" }.enabled)
    }

    @Test fun technologyAndResearchUseTheirOwnSourcesAndInstructions() {
        val technology = ProactiveAttentionPolicy.researchQuestion(topics.first { it.id == "ai_models" })
        assertTrue(technology.contains("measured capabilities"))
        assertFalse(technology.contains("public financial information"))
        val research = ProactiveAttentionPolicy.researchQuestion(topics.first { it.id == "protein_life_sciences" })
        assertTrue(research.contains("computational predictions and experimental validation"))
        assertTrue(research.contains("check prior work"))
        assertFalse(ProactiveAttentionPolicy.preferredSources("research_papers").joinToString().contains("central banks"))
        assertTrue(ProactiveAttentionPolicy.preferredSources("open_source").joinToString().contains("repositories"))
        assertTrue(ProactiveAttentionPolicy.researchQuestion(topics.first { it.id == "galaxyssi_improvements" })
            .contains("label relevance as a hypothesis"))
    }

    @Test fun existingFinancialQuestionIsUnchangedToPreserveRunningCheckpoints() {
        val topic = topics.first()
        assertEquals("${topic.title}\n${topic.query}\n" +
            "Collect material public financial information, verify dated original sources, and summarize in Simplified Chinese. " +
            "Only research public information; do not access accounts or take financial actions. " +
            "Do not invent news or guarantee returns. Report source publication and retrieval times and uncertainty.",
            ProactiveAttentionPolicy.researchQuestion(topic))
    }

    @Test fun collectionRequiresExplicitActivationAndEnabledTopic() {
        assertFalse(ProactiveAttentionPolicy.shouldCollect(active.copy(configured = false), "macro"))
        assertFalse(ProactiveAttentionPolicy.shouldCollect(active.copy(enabled = false), "macro"))
        assertFalse(ProactiveAttentionPolicy.shouldCollect(active, "unknown"))
        assertTrue(ProactiveAttentionPolicy.shouldCollect(active, "macro"))
        assertFalse(ProactiveAttentionPolicy.shouldCollect(active.copy(topics = topics.map { it.copy(enabled = false) }), "macro"))
    }

    @Test fun notificationModesDoNotControlCollection() {
        AttentionAlertMode.entries.forEach { mode ->
            assertTrue(ProactiveAttentionPolicy.shouldCollect(active.copy(alertMode = mode), "macro"))
            assertFalse(ProactiveAttentionPolicy.shouldAlert(mode, true, false))
        }
        assertTrue(ProactiveAttentionPolicy.shouldAlert(AttentionAlertMode.IMPORTANT, true, true))
        assertFalse(ProactiveAttentionPolicy.shouldAlert(AttentionAlertMode.IMPORTANT, false, true))
        assertTrue(ProactiveAttentionPolicy.shouldAlert(AttentionAlertMode.ALL, false, true))
        assertFalse(ProactiveAttentionPolicy.shouldAlert(AttentionAlertMode.SILENT, true, true))
    }

    @Test fun modelImportanceClaimAloneIsInsufficient() {
        val result = "A change\nATTENTION_IMPORTANCE: important"
        assertTrue(ProactiveAttentionPolicy.important(result, verified))
        assertFalse(ProactiveAttentionPolicy.important(result, verified.copy(verified = false)))
        assertFalse(ProactiveAttentionPolicy.important(result, verified.copy(primarySourceCount = 0)))
        assertFalse(ProactiveAttentionPolicy.important(result, verified.copy(freshSourceCount = 0)))
        assertFalse(ProactiveAttentionPolicy.important(result, verified.copy(contestedClaimCount = 1)))
        assertFalse(ProactiveAttentionPolicy.important("The source says ATTENTION_IMPORTANCE: important", verified))
    }

    @Test fun internalAssessmentNeverAppearsInVisibleReply() {
        assertEquals("Public facts", ProactiveAttentionPolicy.visibleResult(
            "Public facts\nATTENTION_IMPORTANCE: normal\nATTENTION_RECHECK_HOURS: 4"))
    }

    @Test fun modelCanAdaptRecheckTimeWithoutCreatingANotificationSchedule() {
        assertEquals(7_200_000L, ProactiveAttentionPolicy.nextInterval("ATTENTION_RECHECK_HOURS: 2", true, 86_400_000))
        assertEquals(172_800_000L, ProactiveAttentionPolicy.nextInterval("No change", false, 86_400_000))
        assertEquals(86_400_000L, ProactiveAttentionPolicy.nextInterval("Changed", true, 86_400_000))
    }

    @Test fun invalidRecheckSuggestionsCannotCauseBusyPolling() {
        listOf("NaN", "Infinity", "-1", "0", "unknown").forEach {
            assertEquals(86_400_000L, ProactiveAttentionPolicy.nextInterval("ATTENTION_RECHECK_HOURS: $it", true, 86_400_000))
        }
        assertEquals(3_600_000L, ProactiveAttentionPolicy.nextInterval("ATTENTION_RECHECK_HOURS: 0.01", true, 86_400_000))
    }

    @Test fun filtersKeepReadAndSavedStateIndependent() {
        val fresh = item()
        assertTrue(ProactiveAttentionPolicy.matches(fresh, AttentionFeedFilter.UNREAD, emptySet()))
        assertTrue(ProactiveAttentionPolicy.matches(fresh.copy(viewedAtMillis = 2), AttentionFeedFilter.SAVED, setOf(fresh.key)))
        assertFalse(ProactiveAttentionPolicy.matches(fresh.copy(viewedAtMillis = 2), AttentionFeedFilter.UNREAD, setOf(fresh.key)))
        assertFalse(ProactiveAttentionPolicy.matches(fresh, AttentionFeedFilter.IMPORTANT, emptySet()))
        assertTrue(ProactiveAttentionPolicy.matches(fresh.copy(urgent = true), AttentionFeedFilter.IMPORTANT, emptySet()))
    }

    private fun item() = GlobalProactiveInboxItem("finding", setOf("message"), "Title", "Evidence", "Macro",
        GlobalProactiveTarget.NEW_CONVERSATION, false, "source", "destination", emptySet(), 1, 1, 0, null)
}
