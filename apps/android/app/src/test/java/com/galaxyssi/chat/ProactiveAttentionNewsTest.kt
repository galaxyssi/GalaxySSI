package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class ProactiveAttentionNewsTest {
    @Test fun abandonedPreparationRecoversButALiveOwnerIsNotDuplicated() {
        val original = task().copy(status = GlobalResearchTaskStatus.RUNNING, leaseExpiresAtMillis = now + 60000,
            attemptCount = 1, researchPlan = GlobalResearchPlan(id = "retained"))
        val selected = GlobalResearchClaimCoordinator.claim(listOf(original), now, true, "preparation-test")
        val claimed = selected.claimed!!
        try {
            assertEquals(original.researchPlan, claimed.researchPlan)
            assertEquals(1, claimed.attemptCount)
            assertNull(GlobalResearchClaimCoordinator.claim(selected.tasks, now + 1, true, "preparation-test").claimed)
        } finally { GlobalResearchClaimCoordinator.release("preparation-test", claimed) }
        val resumed = GlobalResearchClaimCoordinator.claim(selected.tasks, now + 2, true, "preparation-test").claimed!!
        GlobalResearchClaimCoordinator.release("preparation-test", resumed)
    }

    @Test fun dispatchedWorkKeepsItsLeaseAndGetsARecoveryWake() {
        val running = task().copy(status = GlobalResearchTaskStatus.RUNNING, leaseExpiresAtMillis = now + 60000,
            researchPlan = GlobalResearchPlan(units = listOf(GlobalResearchUnit(
                purpose = GlobalResearchUnitPurpose.CORROBORATION, question = "", sourceFocus = "",
                status = GlobalResearchUnitStatus.RUNNING, sourceMessageId = 42, leaseExpiresAtMillis = now + 60000))))
        val selection = GlobalResearchClaimCoordinator.claim(listOf(running, task().copy(id = "attention-research:other")),
            now, true, "dispatched-test")
        assertNull(selection.claimed)
        assertEquals(now + 60001, GlobalResearchClaimCoordinator.attentionNextWake(selection.tasks))
        assertEquals(42L, selection.tasks.first().researchPlan.units.single().sourceMessageId)
    }

    @Test fun sourceReadTimeoutIsAcceptedByItsTransportPolicy() {
        var requested = false
        val transport = object : AgentWebTransport {
            override fun execute(request: AgentWebTransportRequest): AgentWebTransportResponse {
                requested = true
                assertTrue(request.timeoutMillis <= ProactiveAttentionNewsPolicy.sourceWebPolicy.maxTimeoutMillis)
                return AgentWebTransportResponse(200, mapOf("Content-Type" to listOf("text/plain")), "original".toByteArray())
            }
        }
        val web = AgentBoundedWebService(transport,
            AgentHostResolver { listOf(java.net.InetAddress.getByName("8.8.8.8")) },
            policy = ProactiveAttentionNewsPolicy.sourceWebPolicy)
        val result = web.fetch("https://public.example.test/article",
            timeoutMillis = ProactiveAttentionNewsPolicy.sourceWebPolicy.maxTimeoutMillis)
        assertTrue(requested)
        assertEquals("original", result.body.toString(Charsets.UTF_8))
    }

    @Test fun exchangeFilingsArePrimaryButLookalikeHostsAreNot() {
        assertEquals(GlobalEvidenceSourceKind.OFFICIAL, GlobalEvidenceEvaluator.sourceKind("https://etf.sse.com.cn/notice"))
        assertEquals(GlobalEvidenceSourceKind.OFFICIAL, GlobalEvidenceEvaluator.sourceKind("https://disc.static.szse.cn/filing"))
        assertEquals(GlobalEvidenceSourceKind.OFFICIAL, GlobalEvidenceEvaluator.sourceKind("https://static.cninfo.com.cn/filing"))
        assertEquals(GlobalEvidenceSourceKind.OFFICIAL, GlobalEvidenceEvaluator.sourceKind("https://www.hkex.com.hk/notice"))
        assertEquals(GlobalEvidenceSourceKind.GOVERNMENT, GlobalEvidenceEvaluator.sourceKind("https://www.csrc.gov.cn/notice"))
        assertEquals(GlobalEvidenceSourceKind.UNKNOWN, GlobalEvidenceEvaluator.sourceKind("https://csrc.gov.attacker.com/notice"))
        assertEquals(GlobalEvidenceSourceKind.UNKNOWN, GlobalEvidenceEvaluator.sourceKind("https://gov.com/notice"))
        assertEquals(GlobalEvidenceSourceKind.UNKNOWN, GlobalEvidenceEvaluator.sourceKind("https://sse.com.cn.attacker.com/notice"))
    }

    private val now = Instant.parse("2026-10-14T02:00:00Z").toEpochMilli()
    private val quote = "This release adds a new public capability on 2026-10-13."
    private val url = "https://github.com/example/project/releases/tag/v2"
    private fun page() = JSONObject().put("url", url).put("title", "Original release")
        .put("content", quote).put("content_sha256", "hash").put("retrieved_at_millis", now)
    private fun item() = JSONObject().put("title", "New capability").put("summary", "A new public capability was released.")
        .put("event_date", "2026-10-13").put("official_announcement", true)
        .put("sources", JSONArray().put(JSONObject().put("url", url).put("quote", quote)))
    private fun review(items: JSONArray, pages: JSONArray = JSONArray().put(page())) =
        ProactiveAttentionNewsPolicy.review(JSONObject().put("items", items).toString(), pages, now)
    private fun task() = GlobalResearchTask(id = "attention-research:ai_models", sourceEventId = "attention",
        sourceConversationId = "attention", topic = "Models", question = "Recent model news",
        depth = GlobalResearchDepth.CONTINUOUS_MONITOR, preferredSources = emptyList())

    @Test fun originalPageQuoteAllowsAnOfficialAnnouncement() {
        val report = review(JSONArray().put(item()))!!
        assertEquals(1, report.count)
        assertTrue(report.ledger.verified)
        assertTrue(report.text.contains(url))
        assertFalse(report.text.contains("hash"))
    }

    @Test fun reviewRetainsFaithfulHeadlineTranslationsSeparatelyFromSummary() {
        val original = "Model 2.1 released"
        val translated = "Model 2.1 \u53d1\u5e03"
        val result = item().put("headline_translations", JSONArray()
            .put(JSONObject().put("original_title", original).put("title_zh", translated))
            .put(JSONObject().put("original_title", "Model 2.2 released").put("title_zh", translated)))
        val report = review(JSONArray().put(result))!!
        assertEquals(mapOf(original to translated), report.items.single().titleTranslations)
        assertTrue(report.text.contains("New capability"))
        assertTrue(report.ledger.verified)
    }

    @Test fun olderAnnouncementsRemainReadableButCannotBecomeUrgentAlerts() {
        val oldQuote = "The exchange suspended trading only on 2026-10-08 until market close."
        val oldPage = page().put("content", oldQuote)
        val old = item().put("event_date", "2026-10-08").put("important", true).put("importance_reason", "Trading suspension")
            .put("sources", JSONArray().put(JSONObject().put("url", url).put("quote", oldQuote)))
        val report = review(JSONArray().put(old), JSONArray().put(oldPage))!!
        assertEquals(1, report.count)
        assertTrue(report.text.contains("ATTENTION_IMPORTANCE: normal"))
        assertFalse(ProactiveAttentionNewsPolicy.hasCurrentAlertDate(report.text, now))
        assertTrue(ProactiveAttentionNewsPolicy.hasCurrentAlertDate("Recent news\n2026-10-13", now))
    }

    @Test fun fabricatedQuotesUnknownSourcesAndMissingReceiptsDoNotPass() {
        val fabricated = item().put("sources", JSONArray().put(JSONObject().put("url", url)
            .put("quote", "This invented text was never in the original page.")))
        assertNull(review(JSONArray().put(fabricated)))
        assertNull(review(JSONArray().put(item()), JSONArray()))
        assertNull(review(JSONArray().put(item()), JSONArray().put(page().put("content_sha256", ""))))
    }

    @Test fun oldNewsAndFutureDatesCannotBecomeFreshFindings() {
        assertNull(review(JSONArray().put(item().put("event_date", "2020-01-01"))))
        assertNull(review(JSONArray().put(item().put("event_date", "2030-01-01"))))
        assertNull(review(JSONArray().put(item().put("event_date", "2026-10-14"))))
        assertEquals(0L, review(JSONArray().put(item()))!!.ledger.sources.single().publishedAtMillis)
    }

    @Test fun unsupportedNeighborDoesNotBlockConfirmedNews() {
        val report = review(JSONArray().put(item()).put(item().put("event_date", "2000-01-01")))!!
        assertEquals(1, report.count)
    }

    @Test fun anInterpretationNeedsIndependentCorroboration() {
        assertNull(review(JSONArray().put(item().put("official_announcement", false))))
    }

    @Test fun emptyReviewIsNotAFabricatedFindingAndMalformedJsonNeedsRepair() {
        assertEquals(0, review(JSONArray())!!.count)
        assertFalse(review(JSONArray())!!.ledger.verified)
        assertNull(ProactiveAttentionNewsPolicy.review("not JSON", JSONArray(), now))
    }

    @Test fun collectionIsSequentialAndExistingSourcesArePreserved() {
        val task = task()
        val plan = GlobalResearchPlanBuilder.create(task, now)
        assertEquals(1, ProactiveAttentionNewsPolicy.pending(plan).size)
        val done = plan.units.first().copy(status = GlobalResearchUnitStatus.COMPLETED, result = "existing evidence")
        val collected = plan.copy(units = listOf(done) + plan.units.drop(1))
        val reviewing = GlobalResearchPlanBuilder.closeCollection(task, collected, GlobalEvidenceLedger(), now)
        assertEquals(done, reviewing.units.first())
        assertTrue(ProactiveAttentionNewsPolicy.isReview(ProactiveAttentionNewsPolicy.pending(reviewing).single()))
        assertEquals(reviewing.units.size, ProactiveAttentionNewsPolicy.close(task, reviewing, now).units.size)
    }

    @Test fun reviewCompletionNeedsNoFurtherModelCallEvenWithOtherPendingCandidates() {
        val task = task()
        val plan = GlobalResearchPlanBuilder.create(task, now)
        val completed = plan.copy(units = plan.units + GlobalResearchUnit(id = "review" + ProactiveAttentionNewsPolicy.REVIEW_SUFFIX,
            purpose = GlobalResearchUnitPurpose.CORROBORATION, question = "Review", sourceFocus = "Original",
            status = GlobalResearchUnitStatus.COMPLETED))
        assertEquals(GlobalResearchPlanPhase.SYNTHESIS_PENDING,
            GlobalResearchPlanBuilder.closeCollection(task, completed, GlobalEvidenceLedger(), now).phase)
    }

    @Test fun inProgressTopicOutranksNewCollection() {
        val task = task()
        val unit = GlobalResearchUnit(purpose = GlobalResearchUnitPurpose.CHANGE_MONITOR, question = "", sourceFocus = "",
            status = GlobalResearchUnitStatus.COMPLETED)
        assertTrue(ProactiveAttentionNewsPolicy.priority(task.copy(researchPlan = GlobalResearchPlan(units = listOf(unit)))) >
            ProactiveAttentionNewsPolicy.priority(task))
    }
}
