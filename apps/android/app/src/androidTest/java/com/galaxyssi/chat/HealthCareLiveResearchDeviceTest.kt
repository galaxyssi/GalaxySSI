package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in paid probe: real paired reasoning and phone HTTPS, isolated synthetic care databases.
 * Reuses production prompts, parser, observation compaction and tools, not the Activity consent UI.
 */
class HealthCareLiveResearchDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val report = JSONArray()
    private val historyReads = mutableListOf<String>()
    private val feedbackNotes = mutableListOf<String>()
    private val deliveredFeedback = mutableSetOf<String>()
    private val journalReads = mutableSetOf<Int>()
    private val reportFile get() = File(context.filesDir, "health-care-live-research.json")

    @Test fun pairedModelPersistsStructuredAssessmentBeforeCompleting(): Unit = runBlocking {
        val related = InstrumentationRegistry.getArguments().getString("health_live_related") == "true"
        assumeTrue(related || InstrumentationRegistry.getArguments().getString("health_live_model_review") == "true")
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it) }.firstOrNull {
            !it.optBoolean("deleted") && AppStore.agentIdForContact(context, it.optString("id")) == "codex" &&
                !AppStore.isDesktopDeviceContact(context, it.optString("id")) &&
                GalaxySSILinkProtocol.serverLink(context, it.optString("desktop_id"))?.paired == true
        } ?: error("No paired Codex contact; preserve pairing and credentials")
        GalaxySSIMqttClient.connect(context)
        withTimeout(30_000) { while (!GalaxySSIMqttClient.isRequestReplyReady()) delay(100) }
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, it.policy().version) }
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
            if (related) HealthRecordStore(context, names.records).use {
                it.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", System.currentTimeMillis() - 2000))
                it.save(HealthDraft(HealthMetric.BLOOD_PRESSURE, mapOf("systolic" to "121", "diastolic" to "79"), "mmHg", System.currentTimeMillis() - 3000))
            }
            HealthCareStore(context, names.care).use { store ->
                store.configure(true, ""); HealthCareEngine.evaluate(context, names)
                val raw = store.forMetric(HealthMetric.GLUCOSE)!!
                val issue = store.bindDiscussion(raw.id, raw.revision, UUID.randomUUID().toString())
                val config = AgentModelSelectionSettings.configurationForTarget(context, issue.conversationId, contact.getString("id"))
                val scope = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
                    store.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version },
                    HealthCareDiscussion.desktopDestination(context, contact.getString("id")), System.currentTimeMillis(),
                    contact.getString("id"), config?.modelId.orEmpty(), config?.reasoningEffort?.wireValue.orEmpty(),
                    related = HealthCareRelatedContext.capture(store, if (related) setOf(HealthMetric.WEIGHT, HealthMetric.BLOOD_PRESSURE) else emptySet()))
                val authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), scope, "b".repeat(64))
                store.authorizeResearch(authorization, null)
                val job = store.queueResearch(authorization.id, issue.id, System.currentTimeMillis())
                val grant = scope.copy(turnId = job.turnId, researchAuthorizationId = authorization.id)
                store.approveDiscussion(grant)
                val answer = runTurn(store, issue, grant, contact,
                    "这是隔离合成测试，不是我的健康资料。请核对现有资料质量，说明还缺什么关键测量情境，并保存结构化评估。" +
                        "本轮不查网页，不建议治疗，不创建计划或提醒。请用中文回复，不要假设已经确诊。" +
                        if (related) "请通过历史工具读取授权的体重和血压，连同血糖综合核对，在结构化评估中引用三项记录，区分各自单位和时间，不推断因果或同期测量。" else "", emptyList(), names)
                assertTrue(answer.isNotBlank())
                val review = store.modelReview(job.turnId) ?: error("The real provider did not persist a structured assessment")
                assertEquals(grant, review.grant); assertTrue(review.input.evidenceIds.isEmpty())
                if (related) {
                    val expected = grant.related.keys.map { store.relatedMeasurement(it)!!.assessment!!.record!! }
                    assertTrue(historyReads.containsAll(expected.map { it.id }))
                    assertTrue(review.input.records.containsAll(expected))
                    assertTrue(answer.contains("血压") && answer.contains("体重"))
                }
                assertEquals(issue, store.concern(issue.id)); assertNull(store.nextReminder())
                val running = store.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
                assertEquals(HealthCareResearchState.COMPLETED, store.updateResearchJob(running, HealthCareResearchState.COMPLETED).state)
                val notice = store.modelAttention(issue.id)
                assertEquals(review.input.attentionRequested, notice != null)
                notice?.let { assertEquals(job.turnId, it.turnId); assertEquals(job.conversationId, it.conversationId) }
                println("HEALTH_LIVE structured_assessment=true related_measurements=$related real_provider=true no_plan_or_reminder=true")
            }
        } finally {
            reportFile.writeText(report.toString(2))
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }

    @Test fun pairedModelReadsOnlyApprovedVisitJournal(): Unit = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_live_visit_followup") == "true")
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it) }.firstOrNull {
            !it.optBoolean("deleted") && AppStore.agentIdForContact(context, it.optString("id")) == "codex" &&
                !AppStore.isDesktopDeviceContact(context, it.optString("id")) &&
                GalaxySSILinkProtocol.serverLink(context, it.optString("desktop_id"))?.paired == true
        } ?: error("No paired Codex contact; preserve pairing and credentials")
        GalaxySSIMqttClient.connect(context)
        withTimeout(30_000) { while (!GalaxySSIMqttClient.isRequestReplyReady()) delay(100) }
        try { HealthCareVisitFollowUpFixture(context).use { f ->
            HealthPrivacyStore(context, f.names.privacy).use { if (!it.policy().online) it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, it.policy().version) }
            HealthCareEngine.evaluate(context, f.names)
            f.start()
            repeat(9) { n -> f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN,
                barriers = if (n == 0) "合成记录：交通安排困难，无法按原计划参加活动" else "",
                note = if (n == 8) "合成记录：已查好公交路线，尚未实际参加活动" else "合成日常记录 ${n + 1}")) }
            val snapshot = f.snapshot(); val issue = snapshot.visit.issue
            HealthCareStore(context, f.names.care).use { store ->
                val selected = AgentModelSelectionSettings.configurationForTarget(context, issue.conversationId, contact.getString("id"))
                val grant = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
                    store.settings().version, snapshot.visit.privacy.version, HealthCareDiscussion.desktopDestination(context, contact.getString("id")),
                    System.currentTimeMillis(), contact.getString("id"), selected?.modelId.orEmpty(), selected?.reasoningEffort?.wireValue.orEmpty(),
                    profileLink = issue.profileLink, visitFollowUp = HealthCareVisitFollowUpScope.of(snapshot.followUp!!, snapshot.visit.selected!!))
                store.approveDiscussion(grant)
                val answer = runTurn(store, issue, grant, contact,
                    "这是隔离的合成测试，不是我的健康资料。请完整阅读这份随访记录的所有分页，比较较早的困难与最近的进展，给出两个下一步沟通要点。不要改计划、安排提醒或声称已经康复。", emptyList(), f.names)
                assertTrue(answer.isNotBlank()); assertEquals(10, journalReads.size)
                assertTrue("The response did not discuss the saved practical barrier", answer.contains("交通") || answer.contains("公交"))
                assertEquals(issue, store.concern(issue.id)); assertTrue(store.reminders(issue.id).isEmpty()); assertNull(store.plan(grant.turnId))
                println("HEALTH_LIVE visit_followup=true all_ten_entries_read=true no_plan_or_reminder=true real_provider=true")
            }
        } } finally { reportFile.writeText(report.toString(2)) }
    }

    @Test fun pairedModelOrganizesOnlySelectedSourceIntoUnreviewedProposal(): Unit = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_live_instruction") == "true")
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it) }.firstOrNull {
            !it.optBoolean("deleted") && AppStore.agentIdForContact(context, it.optString("id")) == "codex" &&
                !AppStore.isDesktopDeviceContact(context, it.optString("id")) &&
                GalaxySSILinkProtocol.serverLink(context, it.optString("desktop_id"))?.paired == true
        } ?: error("No paired Codex contact; preserve pairing and credentials")
        GalaxySSIMqttClient.connect(context)
        withTimeout(30_000) { while (!GalaxySSIMqttClient.isRequestReplyReady()) delay(100) }
        try { HealthCareInstructionFixture(context).use { f ->
            val value = f.create()
            HealthCareStore(context, f.documents.names.care).use { store ->
                val issue = store.concern(value.concernId)!!
                val selected = AgentModelSelectionSettings.configurationForTarget(context, issue.conversationId, contact.getString("id"))
                val grant = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
                    store.settings().version, HealthPrivacyStore(context, f.documents.names.privacy).use { it.policy().version },
                    HealthCareDiscussion.desktopDestination(context, contact.getString("id")), System.currentTimeMillis(),
                    contact.getString("id"), selected?.modelId.orEmpty(), selected?.reasoningEffort?.wireValue.orEmpty(),
                    profileLink = issue.profileLink, instruction = HealthCareInstructionScope.of(value))
                store.approveDiscussion(grant)
                val answer = runTurn(store, issue, grant, contact,
                    "这是隔离的合成测试，不是我的医嘱。请把选中的复查原文整理成待我核对的建议字段，缺失日期不要推断。", emptyList(), f.documents.names)
                assertTrue(answer.isNotBlank())
                val proposal = store.instructionProposal(grant.turnId) ?: error("Real provider did not stage a source-grounded proposal")
                assertEquals(HealthCareInstructionProposalState.PENDING, proposal.state)
                assertTrue(proposal.fields.values.all { it.quote.isEmpty() || value.source.quote.contains(it.quote) })
                assertFalse(proposal.draft.reviewed); assertEquals(value, store.instruction(value.id))
                assertEquals(issue, store.concern(value.concernId)); assertNull(store.nextReminder()); assertNull(store.plan(grant.turnId))
                println("HEALTH_LIVE instruction_proposal=true exact_source=true unreviewed=true no_action_or_reminder=true real_provider=true")
            }
        } } finally { reportFile.writeText(report.toString(2)) }
    }

    @Test fun pairedModelReadsAuthorizedResearchFeedbackAcrossPages(): Unit = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_live_feedback") == "true")
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it) }.firstOrNull {
            !it.optBoolean("deleted") && AppStore.agentIdForContact(context, it.optString("id")) == "codex" &&
                !AppStore.isDesktopDeviceContact(context, it.optString("id")) &&
                GalaxySSILinkProtocol.serverLink(context, it.optString("desktop_id"))?.paired == true
        } ?: error("No paired Codex contact; preserve pairing and credentials")
        GalaxySSIMqttClient.connect(context)
        withTimeout(30_000) { while (!GalaxySSIMqttClient.isRequestReplyReady()) delay(100) }
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                privacy.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, privacy.policy().version)
            }
            val initial = HealthCareFollowUpTestFixture.confirmed(context, names)
            HealthCareStore(context, names.care).use { store ->
                repeat(32) { index ->
                    val issue = store.concern(initial.id)!!
                    val note = if (index == 0) "最早的合成反馈：夜班后睡眠不足，希望改在午休行动。"
                        else "合成反馈第${index + 1}条：今天只完成部分行动。"
                    feedbackNotes += note
                    store.recordActionFeedback(issue.id, issue.revision, issue.actions.first().id,
                        HealthCareFeedbackKind.PARTIAL, note, UUID.randomUUID().toString(), System.currentTimeMillis())
                }
                val issue = store.concern(initial.id)!!
                val selected = AgentModelSelectionSettings.configurationForTarget(context, issue.conversationId, contact.getString("id"))
                val scope = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id,
                    issue.revision, store.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version },
                    HealthCareDiscussion.desktopDestination(context, contact.getString("id")), System.currentTimeMillis(),
                    contact.getString("id"), selected?.modelId.orEmpty(), selected?.reasoningEffort?.wireValue.orEmpty(),
                    profileLink = issue.profileLink, questionsShared = true, feedbackHistoryShared = true)
                val authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), scope, "b".repeat(64))
                store.authorizeResearch(authorization, null)
                val job = store.queueResearch(authorization.id, issue.id, System.currentTimeMillis())
                val grant = scope.copy(turnId = job.turnId, revision = job.revision, researchAuthorizationId = authorization.id)
                store.approveDiscussion(grant)
                val question = "这是隔离的合成测试，不是我的健康数据。请读取此事项全部已授权的历史行动反馈，翻页直到没有下一页。" +
                    "概括执行困难，并引用最早一条反馈的原话。不要把执行反馈当作健康改善，不要查网页、创建计划、确认计划或安排提醒。"
                val answer = runTurn(store, issue, grant, contact, question, emptyList(), names)
                assertEquals("Not all feedback reached a model prompt", feedbackNotes.toSet(), deliveredFeedback)
                assertTrue("The real model lost the earlier barrier", answer.contains("夜班后睡眠不足"))
                assertTrue("The real model lost the earlier preference", answer.contains("午休"))
                assertEquals(issue, store.concern(issue.id)); assertNull(store.plan(grant.turnId)); assertNull(store.nextDue())
                assertEquals(32, deliveredFeedback.size)
                println("HEALTH_LIVE feedback_pagination=true standing_consent=true unchanged_plan=true real_provider=true")
            }
        } finally {
            reportFile.writeText(report.toString(2))
            listOf(names.care, names.records, names.privacy, names.reminders, names.profile).forEach(context::deleteDatabase)
        }
    }

    @Test fun pairedModelResearchesAndAnswersFollowupWithoutConfirmingPlan(): Unit = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("health_live_research") == "true")
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it) }.firstOrNull {
            !it.optBoolean("deleted") && AppStore.agentIdForContact(context, it.optString("id")) == "codex" &&
                !AppStore.isDesktopDeviceContact(context, it.optString("id")) &&
                GalaxySSILinkProtocol.serverLink(context, it.optString("desktop_id"))?.paired == true
        } ?: error("No paired Codex contact; preserve pairing and credentials")
        GalaxySSIMqttClient.connect(context)
        withTimeout(30_000) { while (!GalaxySSIMqttClient.isRequestReplyReady()) delay(100) }
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val conversation = UUID.randomUUID().toString()
        val history = mutableListOf<AgentTranscriptEntry>()
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
            HealthCareStore(context, names.care).use { it.configure(true, it.settings().version) }
            HealthCareEngine.evaluate(context, names)
            HealthCareStore(context, names.care).use { store ->
                val found = store.forMetric(HealthMetric.GLUCOSE)!!
                val concern = store.bindDiscussion(found.id, found.revision, conversation)
                val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
                val selected = AgentModelSelectionSettings.configurationForTarget(context, conversation, contact.getString("id"))
                val grant = HealthCareDiscussionGrant(conversation, UUID.randomUUID().toString(), concern.id,
                    concern.revision, store.settings().version, privacy.version,
                    HealthCareDiscussion.desktopDestination(context, contact.getString("id")), System.currentTimeMillis(),
                    contact.getString("id"), selected?.modelId.orEmpty(), selected?.reasoningEffort?.wireValue.orEmpty())
                store.approveDiscussion(grant)
                val firstQuestion = "\u8fd9\u662f\u5408\u6210\u6d4b\u8bd5\uff0c\u4e0d\u662f\u6211\u7684\u5065\u5eb7\u6570\u636e\u3002" +
                    "\u62a5\u544a\u53c2\u8003\u8303\u56f4\u662f4-6\uff0c\u8840\u7cd6\u662f6.3 mmol/L\uff0c\u68c0\u6d4b\u6761\u4ef6\u8fd8\u6ca1\u6838\u5bf9\u3002" +
                    "\u8bf7\u5148\u9605\u8bfb https://medlineplus.gov/lab-tests/how-to-understand-your-lab-results/ " +
                    "\u89e3\u91ca\u4e3a\u4ec0\u4e48\u4e0d\u80fd\u7528\u8303\u56f4\u4e2d\u70b9\u4f5c\u4e3a\u6700\u4f73\u503c\uff0c" +
                    "\u63d0\u51fa\u6838\u5bf9\u6761\u4ef6\u548c\u4e0e\u533b\u751f\u8ba8\u8bba\u7684\u5f85\u786e\u8ba4\u8349\u6848\u3002\u4e0d\u8981\u786e\u8bca\u6216\u8bbe\u63d0\u9192\u3002" +
                    "\u8bf7\u7528\u624b\u673a\u5de5\u5177\u771f\u5b9e\u8bfb\u53d6\u6765\u6e90\uff0c\u5e76\u4fdd\u5b58\u4e3a\u5f85\u786e\u8ba4\u8ba1\u5212\uff0c\u4e0d\u662f\u53ea\u5728\u56de\u590d\u4e2d\u5217\u51fa\u8349\u6848\u3002"
                val first = runTurn(store, concern, grant, contact, firstQuestion, history, names)
                assertTrue(first.isNotBlank())
                val plan = store.plan(grant.turnId) ?: error("Real model did not submit a source-grounded draft")
                assertEquals(HealthCarePlanState.PENDING, plan.state)
                assertNull("Incomplete measurement conditions cannot support maintenance", plan.maintenance)
                assertEquals(plan.actions.map { it.id }.toSet(), plan.applicability.keys)
                assertTrue(plan.sources.all { it.evidence != null && it.quote.isNotBlank() })
                assertTrue(store.concern(concern.id)!!.actions.isEmpty()); assertNull(store.nextDue())
                history += entry(AgentTranscriptRole.USER, firstQuestion, grant)
                history += entry(AgentTranscriptRole.ASSISTANT, first, grant)
                val next = grant.copy(turnId = UUID.randomUUID().toString(), approvedAt = System.currentTimeMillis())
                store.approveDiscussion(next)
                val answer = runTurn(store, concern, next, contact,
                    "\u5148\u4e0d\u786e\u8ba4\u8ba1\u5212\u3002\u4e0d\u7528\u518d\u67e5\u7f51\u9875\uff0c\u4e5f\u4e0d\u8981\u65b0\u5efa\u8349\u6848\u3002" +
                        "\u8bf7\u590d\u8ff0\u521a\u624d\u7684\u6570\u503c\u3001\u5355\u4f4d\u548c\u8fd8\u672a\u6838\u5bf9\u7684\u4fe1\u606f\uff0c\u5e76\u8bf4\u660e\u8ba1\u5212\u6709\u6ca1\u6709\u6267\u884c\u3002", history, names)
                assertTrue("Follow-up lost the measurement", answer.contains("6.3"))
                assertTrue("Follow-up lost units", answer.contains("mmol", true) || answer.contains("\u6beb\u6469"))
                assertEquals(plan, store.plan(grant.turnId)); assertNull(store.plan(next.turnId))
                assertTrue(store.concern(concern.id)!!.actions.isEmpty()); assertNull(store.nextDue())
                HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                    mapOf("glucose" to "5.4"), "mmol/L", System.currentTimeMillis() - 500, reference = "4-6")) }
                HealthCareEngine.evaluate(context, names)
                val updated = store.concern(concern.id)!!
                assertEquals(HealthCareStage.REASSESS, updated.stage)
                assertNotNull(updated.assessment.comparison)
                val followup = next.copy(turnId = UUID.randomUUID().toString(), revision = updated.revision,
                    approvedAt = System.currentTimeMillis())
                store.approveDiscussion(followup)
                val reassessed = runTurn(store, updated, followup, contact,
                    "\u6211\u521a\u52a0\u5165\u4e86\u4e00\u6761\u5408\u6210\u590d\u67e5\u7ed3\u679c\u3002\u8bf7\u6bd4\u8f83\u524d\u540e\u4e24\u6b21\u6570\u503c\u548c\u5355\u4f4d\uff0c" +
                        "\u8bf4\u660e\u8fd8\u9700\u6838\u5bf9\u4ec0\u4e48\uff0c\u80fd\u5426\u76f4\u63a5\u5224\u5b9a\u7a33\u5b9a\u5e76\u7ed3\u675f\u8ddf\u8e2a\u3002" +
                        "\u4e0d\u7528\u518d\u67e5\u7f51\u9875\uff0c\u4e0d\u8981\u65b0\u5efa\u8349\u6848\u6216\u8bbe\u63d0\u9192\u3002", history, names)
                assertTrue("Reassessment lost previous/current values", reassessed.contains("6.3") && reassessed.contains("5.4"))
                assertEquals(updated, store.concern(concern.id)); assertNull(store.plan(followup.turnId)); assertNull(store.nextDue())
                val now = System.currentTimeMillis()
                var oldest = ""
                HealthRecordStore(context, names.records).use { records -> repeat(35) { index ->
                    val saved = records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to if (index == 34) "6.1" else "6.3"),
                        "mmol/L", now - (index + 1L) * 86_400_000L, reference = "4-6")) as HealthSaveResult.Saved
                    if (index == 34) oldest = saved.record.id
                } }
                HealthCareEngine.evaluate(context, names)
                val longitudinal = store.concern(concern.id)!!
                val historyGrant = followup.copy(turnId = UUID.randomUUID().toString(), revision = longitudinal.revision,
                    approvedAt = System.currentTimeMillis())
                store.approveDiscussion(historyGrant)
                val answerHistory = runTurn(store, longitudinal, historyGrant, contact,
                    "这仍是隔离合成测试。请用手机健康历史工具读取更早的记录，确认最早一条的数值和单位，并说明检测条件是否完整。" +
                        "近期页不是全部历史，请翻到最早的记录。不要新建计划、设提醒或判定已经稳定。", emptyList(), names)
                assertTrue("Real model did not read the older source page", oldest in historyReads)
                assertTrue("Real model lost the oldest measurement", answerHistory.contains("6.1"))
                assertEquals(longitudinal, store.concern(concern.id)); assertNull(store.nextDue())
                val maintenanceGrant = historyGrant.copy(turnId = UUID.randomUUID().toString(), approvedAt = System.currentTimeMillis())
                store.approveDiscussion(maintenanceGrant)
                val reviewAnswer = runTurn(store, longitudinal, maintenanceGrant, contact,
                    "仍是合成测试。现在这次结果已经在报告范围内，能否直接转入长期维护，不用再复查？" +
                        "请根据现有证据说明理由；不要虚构检测条件、医生确认或复查间隔。", emptyList(), names)
                assertTrue(reviewAnswer.isNotBlank())
                val reviewPlan = store.plan(maintenanceGrant.turnId)
                if (reviewPlan?.maintenance != null) assertTrue("Unknown conditions must block maintenance adoption",
                    HealthCareMaintenancePolicy.gaps(reviewPlan, longitudinal, System.currentTimeMillis()).isNotEmpty())
                assertEquals(longitudinal, store.concern(concern.id)); assertNull(store.nextReminder()); assertNull(store.nextDue())
                println("HEALTH_LIVE maintenance_not_automatically_authorized=true")
                println("HEALTH_LIVE scoped_history_pagination=true")
                println("HEALTH_LIVE research_and_followup=true reassessment_context=true pending_only=true real_provider=true")
            }
        } finally {
            reportFile.writeText(report.toString(2))
            listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase)
        }
    }

    private suspend fun runTurn(store: HealthCareStore, concern: HealthCareConcern, grant: HealthCareDiscussionGrant,
        contact: JSONObject, question: String, turns: List<AgentTranscriptEntry>, names: HealthOverviewDatabases): String {
        val web = AgentBoundedWebService(AgentPinnedOkHttpWebTransport())
        val service = AgentWebIntelligenceService(AgentBoundedWebIntelligenceFetcher(web), AgentInMemoryWebIntelligenceStore())
        val registry = AgentNativeToolRegistry()
        HealthCareWebEvidence.wrap(AgentWebIntelligenceNativeTools.definitions(service, web.availability)
            .filter { it.descriptor.id == AgentWebIntelligenceNativeTools.FETCH }) { invocation, output ->
            check(invocation.conversationId == grant.conversationId && invocation.turnId == grant.turnId)
            val proofs = HealthCareEvidencePolicy.read(output, grant, invocation.invocationId, System.currentTimeMillis())
            store.recordEvidence(proofs)
            output + ("health_evidence" to proofs.map { it.output() })
        }.forEach(registry::register)
        registry.register(AgentToolInspectionTools.definition())
        registry.register(HealthCarePlanTool.definition { invocation, input ->
            check(invocation.conversationId == grant.conversationId && invocation.turnId == grant.turnId)
            store.proposePlan(HealthCarePlanPolicy.parse(input, grant, concern, System.currentTimeMillis()))
        })
        if (grant.researchAuthorizationId.isNotEmpty()) registry.register(HealthCareModelReviewTool.definition { invocation, input ->
            check(invocation.conversationId == grant.conversationId && invocation.turnId == grant.turnId)
            store.recordModelReview(grant, input, System.currentTimeMillis())
        })
        registry.register(HealthCareHistoryTool.definition { invocation, input ->
            HealthCareHistoryTool.read(context, names, invocation, input).also { output ->
                val samples = output.optJSONObject("history")?.optJSONArray("samples") ?: JSONArray()
                for (index in 0 until samples.length()) historyReads += samples.getJSONObject(index).getJSONObject("record").getString("id")
            }
        })
        if (grant.feedbackHistoryShared) registry.register(HealthCareFeedbackTool.definition { invocation, input ->
            HealthCareFeedbackTool.read(context, names, invocation, input)
        })
        if (grant.instruction != null) registry.register(HealthCareInstructionTool.definition { invocation, input ->
            check(invocation.conversationId == grant.conversationId && invocation.turnId == grant.turnId)
            HealthCareInstructionTool.selected(context, store, grant.concernId, grant.instruction, names)
            store.proposeInstruction(grant, input, System.currentTimeMillis())
        })
        if (grant.visitFollowUp != null) registry.register(HealthCareVisitFollowUpTool.definition { invocation, input ->
            HealthCareVisitFollowUpTool.read(context, names, invocation, input).also { output ->
                output.optJSONArray("items")?.let { items -> repeat(items.length()) { journalReads += items.getJSONObject(it).getInt("revision") } }
            }
        })
        val screen = ScreenContext("Synthetic health acceptance", pageTitle = "Synthetic health concern")
        val snapshot = if (grant.instruction != null)
            HealthCareInstructionTool.snapshot(store.instruction(grant.instruction.id)!!)
            else if (grant.visitFollowUp != null) HealthCareVisitFollowUpTool.snapshot(
                HealthCareVisitFollowUpTool.selected(store, concern.id, grant.visitFollowUp), store.encounter(grant.visitFollowUp.encounter)!!, concern.revision)
            else HealthCareDiscussionPolicy.snapshot(concern, followUp = if (grant.researchAuthorizationId.isEmpty()) null else
                HealthCareResearchHandoff.snapshot(concern, store.researchJob(grant.turnId)!!, null, null),
                feedbackHistoryShared = grant.feedbackHistoryShared)
        val goal = HealthCareDiscussionPolicy.prompt(question, if (grant.related.isEmpty()) snapshot else
            JSONObject(snapshot).put("related_measurements", HealthCareRelatedContext.snapshot(store, grant.related)).toString(2))
        val runtime = AgentRuntimeContextBuilder.build(sessionId = grant.conversationId, goal = goal, screen = screen,
            permissionMode = PermissionMode.AUTO_LOW_RISK, highRiskGuard = true, memoryCapture = false,
            callableTargets = emptyList(), memories = emptyList(), nativeTools = registry.availableCatalog().descriptors.filter {
                grant.instruction == null && grant.visitFollowUp == null || it.id in HealthCareDiscussionPolicy.tools(grant)
            })
        val observations = mutableListOf<AgentAction>()
        val seed = AgentRequest(goal, screen, emptyList(), memories = emptyList(), runtimeContext = runtime,
            conversationContext = AgentConversationContext(grant.conversationId, "", turns, true, trackingPaused = true),
            executionTurnId = grant.turnId)
        var repair = ""
        // Bound this paid acceptance probe only; no production task budget is changed.
        return withTimeout(600_000L) {
            repeat(12) { round ->
                val request = seed.copy(executionHistory = observations.toList(),
                    replanReason = if (round == 0) "" else PHONE_SUPERVISED_PROJECT_REPLAN_REASON)
                val prompt = repair.ifBlank { if (round == 0) AgentSupervisedProjectLoop.planningPrompt(request)
                    else AgentSupervisedProjectLoop.continuationPrompt(request) }
                deliveredFeedback += feedbackNotes.filter { prompt.contains(it) }
                val raw = exchange(contact, grant, prompt)
                report.put(JSONObject().put("turn", grant.turnId).put("round", round).put("response", raw))
                reportFile.writeText(report.toString(2))
                AgentSupervisedProjectDirectResponseCodec.parse(raw)?.let { return@withTimeout it }
                val normalized = AgentSupervisedProjectControlPayload.normalize(raw, observations)
                val parsed = AgentModelPlanParser.parseWithDiagnostics(request, normalized,
                    AgentSupervisedProjectLoop.plannerSettings(AgentModelPlannerSettings()), allowInitialCompletion = true)
                if (parsed.plan == null) {
                    repair = AgentSupervisedProjectLoop.formatRepairPrompt(request, raw, parsed.rejection?.toJson().orEmpty())
                    println("HEALTH_LIVE round=$round parse=${parsed.rejection?.code}")
                    return@repeat
                }
                repair = ""
                val actions = parsed.plan.actions
                if (actions.singleOrNull()?.isTaskCompleteMarker() == true) return@withTimeout actions.single().description
                actions.forEach { action ->
                    require(action.kind == AgentActionKind.CALL_NATIVE_TOOL) { "Only scoped phone tools allowed" }
                    val id = action.parameters.getValue("tool_id")
                    require(grant.instruction == null && grant.visitFollowUp == null || id in HealthCareDiscussionPolicy.tools(grant))
                    require(registry.lookup(id) != null)
                    val input = jsonObject(JSONObject(action.parameters.getValue("input_json")))
                    val result = registry.invoke(id, input, AgentNativeToolInvocationContext(
                        conversationId = grant.conversationId, turnId = grant.turnId,
                        deadlineEpochMillis = System.currentTimeMillis() + 60_000))
                    val encoded = AgentNativeJsonCodec.stringify(result.output)
                    val evidence = AgentNativeActionObservation.evidence(AgentActionResult(action.id, result.isSuccess,
                        result.message, mapOf("native_tool_output" to encoded,
                            AgentNativeActionObservation.KEY to AgentNativeActionObservation.from(result).orEmpty())), 16_000)
                    observations += action.copy(id = "round-$round-${action.id}",
                        status = if (result.isSuccess) AgentActionStatus.COMPLETED else AgentActionStatus.FAILED,
                        result = result.message, evidence = evidence)
                    report.put(JSONObject().put("tool", id).put("status", result.status.wireValue).put("observation", evidence))
                    println("HEALTH_LIVE round=$round tool=$id status=${result.status.wireValue}")
                }
            }
            error("Live health probe exhausted its test-only 12-round allowance")
        }
    }

    private suspend fun exchange(contact: JSONObject, grant: HealthCareDiscussionGrant, prompt: String): String {
        val source = System.currentTimeMillis()
        val task = "health-live-${UUID.randomUUID()}"
        val id = contact.getString("id")
        val pending = CompletableDeferred<AgentConnectorResponse>()
        val listener = object : GalaxySSIMqttClient.Listener {
            override fun onMessage(payload: String) {
                val json = runCatching { JSONObject(payload) }.getOrNull() ?: return
                if (json.optLong("source_message_id") != source || json.optString("contact_id") != id ||
                    json.optString("conversation_id") != grant.conversationId || json.optString("turn_id") != grant.turnId ||
                    json.optString("task_id") != task || json.optString("type") != "text") return
                val result = AgentRemoteOutcomeCodec.decode(json, AgentRemoteOutcomeCodec.content(context, json)) ?: return
                GalaxySSIMqttClient.completeIncomingDelivery(context, payload)
                pending.complete(result)
            }
        }
        GalaxySSIMqttClient.addListener(listener)
        var received = false
        try {
            assertTrue(GalaxySSIMqttClient.publishUserMessage(prompt, contactId = id, clientMessageId = source,
                conversationId = grant.conversationId, turnId = grant.turnId, taskId = task,
                executionMode = AgentTaskExecutionMode.PLAN_ONLY, connectorTaskMode = PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
                agentModelId = grant.modelId, agentReasoningEffort = AgentModelReasoningEffort.fromWireValue(grant.effort)))
            val response = withTimeout(180_000) { pending.await() }
            received = true
            assertTrue("Paired provider failed: ${AgentObservationRedaction.redact(response.content).take(300)}", response.success)
            return response.content
        } finally {
            if (!received) GalaxySSIMqttClient.publishAgentTaskCancel(task, id, source, grant.conversationId, grant.turnId)
            GalaxySSIMqttClient.removeListener(listener)
        }
    }

    private fun entry(role: AgentTranscriptRole, text: String, grant: HealthCareDiscussionGrant) =
        AgentTranscriptEntry(UUID.randomUUID().toString(), role, text, System.currentTimeMillis(),
            conversationId = grant.conversationId, turnId = grant.turnId)

    private fun jsonValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> jsonObject(value)
        is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
        else -> value
    }

    private fun jsonObject(value: JSONObject): AgentNativeJsonObject =
        value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
}
