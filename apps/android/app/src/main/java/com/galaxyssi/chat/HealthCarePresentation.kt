package com.galaxyssi.chat

internal fun HealthCareStage.titleResource() = when (this) {
    HealthCareStage.VERIFY_CONTEXT -> R.string.health_care_verify
    HealthCareStage.REVIEW_EVIDENCE -> R.string.health_care_review_evidence
    HealthCareStage.REVIEW_PLAN -> R.string.health_care_review_plan
    HealthCareStage.WAITING_RESULTS -> R.string.health_care_waiting
    HealthCareStage.REASSESS -> R.string.health_care_reassess
    HealthCareStage.MAINTENANCE -> R.string.health_care_maintenance
    HealthCareStage.PAUSED -> R.string.health_care_paused
    HealthCareStage.CLOSED -> R.string.health_care_closed
}
internal fun HealthCareSignal.titleResource() = when (this) {
    HealthCareSignal.REPORT_LOW -> R.string.health_care_low
    HealthCareSignal.REPORT_HIGH -> R.string.health_care_high
    HealthCareSignal.GLUCOSE_CONTEXT -> R.string.health_care_glucose_context
    HealthCareSignal.GUIDELINE_SCOPE -> R.string.health_care_guideline_scope
    HealthCareSignal.GUIDELINE_REVIEW -> R.string.health_care_guideline_review
    HealthCareSignal.RISING_SERIES -> R.string.health_care_rising
    HealthCareSignal.FALLING_SERIES -> R.string.health_care_falling
    HealthCareSignal.RESULT_NOT_EXACT -> R.string.health_care_non_exact
    HealthCareSignal.SOURCE_REMOVED -> R.string.health_care_removed
}
internal fun HealthCareActionState.titleResource() = when (this) {
    HealthCareActionState.PROPOSED -> R.string.health_care_draft_plan
    HealthCareActionState.CONFIRMED -> R.string.health_care_action_confirmed
    HealthCareActionState.DONE -> R.string.health_care_action_done
    HealthCareActionState.DECLINED -> R.string.health_care_action_declined
}
