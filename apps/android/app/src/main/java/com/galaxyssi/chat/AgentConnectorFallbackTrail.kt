package com.galaxyssi.chat

internal data class AgentConnectorFallbackSelection(
    val resourceId: String,
    val remainingResourceIds: List<String>,
    val deferredRetryIds: List<String>,
    val retriedResourceIds: Set<String>,
    val attemptedResourceIds: Set<String> = emptySet()
)

/** Keeps one soft-failed resource available after untried alternatives are exhausted. */
internal object AgentConnectorFallbackTrail {
    fun mergeAvailable(
        rememberedResourceIds: Collection<String>,
        currentResourceIds: Collection<String>,
        failedResourceId: String,
        attemptedResourceIds: Collection<String> = emptyList()
    ): List<String> {
        val failed = failedResourceId.trim()
        return normalized(rememberedResourceIds + currentResourceIds)
            .filterNot { it == failed || it in attemptedResourceIds }
    }

    fun selectNext(
        failedResourceId: String,
        remainingResourceIds: List<String>,
        deferredRetryIds: List<String>,
        retriedResourceIds: Set<String>,
        retryFailedResource: Boolean,
        attemptedResourceIds: Collection<String> = emptyList()
    ): AgentConnectorFallbackSelection? {
        val retried = normalized(retriedResourceIds).toSet()
        val failed = failedResourceId.trim()
        val attempted = normalized(attemptedResourceIds + retried + deferredRetryIds + failed).toSet()
        val deferred = normalized(deferredRetryIds)
            .filterNot { it in retried || (!retryFailedResource && it == failed) }.toMutableList()
        val remaining = normalized(remainingResourceIds).filterNot { it in attempted }
        if (
            retryFailedResource &&
            failed.isNotBlank() &&
            failed !in retried &&
            failed !in deferred &&
            failed !in remaining
        ) {
            deferred += failed
        }

        remaining.firstOrNull()?.let { next ->
            return AgentConnectorFallbackSelection(
                resourceId = next,
                remainingResourceIds = remaining.drop(1),
                deferredRetryIds = deferred,
                retriedResourceIds = retried,
                attemptedResourceIds = attempted
            )
        }
        val retry = deferred.firstOrNull { it !in retried } ?: return null
        return AgentConnectorFallbackSelection(
            resourceId = retry,
            remainingResourceIds = emptyList(),
            deferredRetryIds = deferred.filterNot { it == retry },
            retriedResourceIds = retried + retry,
            attemptedResourceIds = attempted
        )
    }

    fun parse(value: String): List<String> = normalized(value.split(','))

    fun encode(values: Collection<String>): String = normalized(values).joinToString(",")

    private fun normalized(values: Collection<String>): List<String> = values.asSequence()
        .map(String::trim)
        .filter(String::isNotBlank)
        .distinct()
        .toList()
}
