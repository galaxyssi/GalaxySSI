package com.galaxyssi.chat

import android.content.Context
import java.util.UUID

internal class HealthCareAttentionFixture(private val context: Context) : AutoCloseable {
    val names = HealthOverviewDatabases(UUID.randomUUID().toString())
    val care = HealthCareStore(context, names.care)
    val now = System.currentTimeMillis()
    val settings = HealthReminderSettings(notifications = true, quiet = false)
    val issue: HealthCareConcern
    val authorization: HealthCareResearchAuthorization
    lateinit var job: HealthCareResearchJob
    lateinit var grant: HealthCareDiscussionGrant
    init {
        care.configure(true, "")
        measurement("6.3")
        val raw = care.page().items.single()
        issue = care.bindDiscussion(raw.id, raw.revision, UUID.randomUUID().toString())
        val scope = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
            care.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version },
            "a".repeat(64), now, "local-llm", "fixture", "high")
        authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), scope, "b".repeat(64))
        care.authorizeResearch(authorization, null)
        prepare()
    }
    fun measurement(value: String) {
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
            mapOf("glucose" to value), "mmol/L", System.currentTimeMillis() - 1000, reference = "4-6")) }
        HealthCareEngine.evaluate(context, names)
    }
    fun prepare() {
        job = care.queueResearch(authorization.id, issue.id, System.currentTimeMillis())
        grant = authorization.scope.copy(turnId = job.turnId, revision = job.revision, researchAuthorizationId = authorization.id)
        care.approveDiscussion(grant)
    }
    fun record(attention: Boolean = true) = care.recordModelReview(grant,
        HealthCareModelReviewTestFixture.input(care, issue.id).copy(attentionRequested = attention,
            attentionReason = "合成测试：请核对测量情境，并非诊断或紧急警报。"), System.currentTimeMillis())
    fun complete() {
        job = care.updateResearchJob(job, HealthCareResearchState.DISPATCHED)
        job = care.updateResearchJob(job, HealthCareResearchState.COMPLETED)
    }
    val notice get() = care.modelAttention(issue.id)!!
    override fun close() { care.close(); listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
}
