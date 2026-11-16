package com.galaxyssi.chat

internal object AttentionArticleRetryPolicy {
    private const val MAX_RETRIES = 3
    const val STOPPED = Long.MAX_VALUE

    // A claimed job carries the attempts before this attempt, including the original attempt.
    fun exhausted(attemptsBeforeClaim: Int) = attemptsBeforeClaim >= MAX_RETRIES

    fun delay(attemptsBeforeClaim: Int, error: String): Long {
        val base = if (error.startsWith("article_") && error !in setOf("article_translation_timeout",
                "article_translation_model_pending")) 30 * 60_000L else 60_000L
        return (base * (1L shl attemptsBeforeClaim.coerceIn(0, MAX_RETRIES))).coerceAtMost(4 * 60 * 60_000L)
    }
}
