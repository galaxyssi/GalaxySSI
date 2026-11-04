package com.galaxyssi.chat

internal const val HEALTH_OCR_REVIEW_PAGE_SIZE = 20
internal const val HEALTH_OCR_REVIEW_SELECTION_LIMIT = 100

internal data class HealthOcrLinkTarget(val id: String, val revision: Int)

internal data class HealthOcrReviewSelection(val key: String, val version: String, val link: HealthOcrLinkTarget? = null) {
    fun encode() = "$key|$version" + (link?.let { "|${it.id}|${it.revision}" } ?: "")
    companion object {
        fun decode(value: String): HealthOcrReviewSelection? {
            val parts = value.split('|')
            if (parts.size !in listOf(2, 4) || !parts[0].startsWith("ocr:") || parts[0].length > 150 ||
                !parts[1].matches(Regex("[A-Za-z0-9_-]{43}"))) return null
            val target = if (parts.size == 4) {
                val revision = parts[3].toIntOrNull()?.takeIf { it > 0 } ?: return null
                if (!HealthProfilePolicy.uuid(parts[2])) return null
                HealthOcrLinkTarget(parts[2], revision)
            } else null
            return HealthOcrReviewSelection(parts[0], parts[1], target)
        }
    }
}

internal data class HealthOcrReviewRow(val draft: HealthDraft, val version: String, val saved: HealthObservation? = null,
                                      val link: HealthOcrLinkTarget? = null, val linked: Boolean = false) {
    val selection: HealthOcrReviewSelection? get() = if (saved == null && HealthObservationPolicy.validate(draft) == null)
        HealthOcrReviewSelection(HealthRecordStore.draftKey(draft), version, link) else null
}

internal sealed class HealthOcrBatchResult {
    data class Saved(val count: Int, val linked: Int = 0) : HealthOcrBatchResult()
    data class Stale(val key: String) : HealthOcrBatchResult()
    data class Duplicate(val key: String) : HealthOcrBatchResult()
}
