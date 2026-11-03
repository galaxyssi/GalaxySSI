package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeoutOrNull

internal interface AttentionTitleTranslator : AutoCloseable {
    suspend fun isReady(): Boolean
    suspend fun translate(title: String): String
}

internal data class AttentionLocalTitleResult(
    val remaining: Map<String, String>,
    val translated: Int,
    val reason: String = ""
)

/** The local translator never discovers agents, spends model permits, or sends headlines over a network. */
internal class AttentionLocalTitleTranslation(
    private val createTranslator: () -> AttentionTitleTranslator,
    private val cached: (String) -> String,
    private val save: (String, String) -> Unit,
    private val requestDownload: () -> Unit,
    private val batchTimeoutMillis: Long = 12_000L,
    private val titleTimeoutMillis: Long = 3_000L
) {
    suspend fun translate(titles: Map<String, String>): AttentionLocalTitleResult {
        val remaining = titles.filterValues { cached(it).isBlank() }.toMutableMap()
        if (remaining.isEmpty()) return AttentionLocalTitleResult(emptyMap(), 0)
        var saved = 0
        var reason = ""
        try {
            val completed = withTimeoutOrNull(batchTimeoutMillis) {
                createTranslator().use { translator ->
                    if (!translator.isReady()) {
                        requestDownload()
                        reason = "model_pending"
                        return@use
                    }
                    for ((id, title) in remaining.toMap()) {
                        currentCoroutineContext().ensureActive()
                        val text = withTimeoutOrNull(titleTimeoutMillis) { translator.translate(title).trim() }
                        val rejection = if (text == null) "timeout" else ProactiveAttentionTitlePolicy.rejection(title, text)
                        if (rejection == null) {
                            save(title, checkNotNull(text))
                            remaining.remove(id)
                            saved++
                        } else reason = rejection
                    }
                }
                true
            }
            if (completed == null) reason = "timeout"
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            reason = failure.javaClass.simpleName
        }
        return AttentionLocalTitleResult(remaining, saved, reason)
    }
}
