package com.galaxyssi.chat

internal enum class HealthCareVisitSection { MEASUREMENTS, CONTEXT, ACTIONS, QUESTIONS, PROFILE }

internal data class HealthCareVisitItem(val key: String, val section: HealthCareVisitSection,
    val title: String, val text: String, val record: HealthCareRecordRef? = null)

/** Local, short-lived review material. It is neither a diagnosis nor an external disclosure grant. */
internal data class HealthCareVisitSummary(val concernId: String, val revision: Int, val metric: HealthMetric,
    val inputVersion: String, val settingsVersion: String, val privacyVersion: String,
    val profile: HealthCareProfileLink?, val createdAt: Long, val sections: Set<HealthCareVisitSection>,
    val title: String, val introduction: String, val limitations: String, val items: List<HealthCareVisitItem>) {
    init {
        require(HealthProfilePolicy.uuid(concernId) && revision > 0 && createdAt > 0 && sections.isNotEmpty())
        require(items.size <= 100 && items.map { it.key }.distinct().size == items.size)
        require(items.all { it.section in sections })
    }
    fun selectedText(keys: Set<String>): String {
        require(keys.isNotEmpty() && keys.all { key -> items.any { it.key == key } })
        return (listOf(title, introduction) + items.filter { it.key in keys }.map { "${it.title}\n${it.text}" } + limitations)
            .joinToString("\n\n").also { require(it.length <= MAX_SHARED_CHARS) }
    }
    companion object {
        const val MAX_AGE = 10 * 60 * 1000L
        const val MAX_SHARED_CHARS = 100_000
        fun fresh(createdAt: Long, now: Long) = now >= createdAt && now - createdAt < MAX_AGE
    }
}
