package com.galaxyssi.chat

internal object HealthCareModelReviewTestFixture {
    fun input(care: HealthCareStore, concern: String) = HealthCareModelReviewInput(
        "合成测试：资料需要核对", "依据本次授权的记录，不作诊断。", "尚未检索外部依据。", "核对记录中的测量情境。",
        HealthCareReviewDecision.OBSERVE, listOf(HealthCareReviewEvent.SOURCE_CHANGE, HealthCareReviewEvent.USER_FEEDBACK),
        listOf(care.concern(concern)!!.assessment.record!!), emptyList(), "", false, "没有新的已核实发现，无需重复提醒。")
    fun record(care: HealthCareStore, job: HealthCareResearchJob): HealthCareModelReview {
        val grant = care.discussionGrant(job.turnId) ?: care.researchAuthorization(job.concernId)!!.scope.copy(
            turnId = job.turnId, revision = job.revision, researchAuthorizationId = job.authorizationId,
            approvedAt = System.currentTimeMillis()).also(care::approveDiscussion)
        return care.recordModelReview(grant, input(care, job.concernId), System.currentTimeMillis())
    }
    fun complete(care: HealthCareStore, job: HealthCareResearchJob): HealthCareResearchJob {
        record(care, job)
        val running = if (job.state == HealthCareResearchState.QUEUED) care.updateResearchJob(job, HealthCareResearchState.DISPATCHED) else job
        return care.updateResearchJob(running, HealthCareResearchState.COMPLETED)
    }
}
