package com.galaxyssi.chat

internal const val HEALTH_OCR_REVIEW_PAGE_SIZE = 20
internal const val HEALTH_OCR_REVIEW_SELECTION_LIMIT = 100

internal data class HealthOcrReviewSelection(val key: String, val version: String) {
    fun encode() = "$key|$version"
    companion object {
        fun decode(value: String): HealthOcrReviewSelection? {
            val parts = value.split('|')
            return if (parts.size == 2 && parts[0].startsWith("ocr:") && parts[0].length <= 150 &&
                parts[1].matches(Regex("[A-Za-z0-9_-]{43}"))) HealthOcrReviewSelection(parts[0], parts[1]) else null
        }
    }
}

internal data class HealthOcrReviewRow(val draft: HealthDraft, val version: String, val saved: HealthObservation? = null) {
    val selection: HealthOcrReviewSelection? get() = if (saved == null && HealthObservationPolicy.validate(draft) == null)
        HealthOcrReviewSelection(HealthRecordStore.draftKey(draft), version) else null
}

internal sealed class HealthOcrBatchResult {
    data class Saved(val count: Int) : HealthOcrBatchResult()
    data class Stale(val key: String) : HealthOcrBatchResult()
    data class Duplicate(val key: String) : HealthOcrBatchResult()
}
