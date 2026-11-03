package com.galaxyssi.chat

enum class AttentionTitleStatus { PENDING, TRANSLATING, WAITING_MODEL, WAITING_CAPACITY, RETRYING, DISABLED }

internal object ProactiveAttentionTranslationPolicy {
    fun enabled(preferences: AttentionPreferences, language: String): Boolean =
        preferences.configured && preferences.enabled && preferences.translateTitles && language == "zh"

    // Public-title translation is independent of autonomous research permissions.
    fun orderRoutes(routes: List<String>, cloud: (String) -> Boolean, lastFailed: String = ""): List<String> =
        routes.distinct().sortedWith(compareBy<String> { it == lastFailed }.thenBy {
            when { cloud(it) -> 0; it == "local-llm" -> 1; else -> 2 }
        })

    fun statusLabel(status: AttentionTitleStatus): Int = when (status) {
        AttentionTitleStatus.PENDING -> R.string.attention_translation_pending
        AttentionTitleStatus.TRANSLATING -> R.string.attention_translation_running
        AttentionTitleStatus.WAITING_MODEL -> R.string.attention_translation_no_model
        AttentionTitleStatus.WAITING_CAPACITY -> R.string.attention_translation_capacity
        AttentionTitleStatus.RETRYING -> R.string.attention_translation_retry
        AttentionTitleStatus.DISABLED -> R.string.attention_translation_disabled
    }
}
