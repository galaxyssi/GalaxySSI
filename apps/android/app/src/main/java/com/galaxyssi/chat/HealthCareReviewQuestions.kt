package com.galaxyssi.chat

/** Links an assessment to current, explicitly shared questions without creating or answering any. */
internal object HealthCareReviewQuestions {
    fun validate(issue: HealthCareConcern, grant: HealthCareDiscussionGrant, input: HealthCareModelReviewInput,
        profile: HealthProfileContext?, find: (String) -> HealthCareQuestion?) {
        input.requireSubmission()
        if (input.questions.isEmpty()) return
        if (!grant.questionsShared || grant.concernId != issue.id || grant.profileLink != issue.profileLink ||
            issue.profileLink != null && profile?.stamp != issue.profileLink.stamp) throw HealthCareConflict()
        val known = HealthCareQuestionPolicy.known(issue, profile)
        input.questions.forEach { ref ->
            val question = find(ref.id) ?: throw IllegalArgumentException("Read or retain the question before citing it")
            if (question.concernId != issue.id || question.scope != HealthCareQuestionPolicy.scope(issue) ||
                !grant.related.keys.containsAll(question.related)) throw HealthCareConflict()
            require(question.id == ref.id && question.revision == ref.revision) {
                "Use the current question revision from this review's authorized input"
            }
            require(question.basis == HealthCareQuestionPolicy.basis(issue) &&
                HealthCareQuestionPolicy.view(question, issue, known).getString("state") in setOf("OPEN", "CONFLICT")) {
                "Use current unresolved questions or explicitly review conflicting facts; respect saved answers and user deferral"
            }
        }
    }
}
