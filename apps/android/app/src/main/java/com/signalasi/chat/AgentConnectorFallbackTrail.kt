package com.signalasi.chat

internal data class AgentConnectorFallbackSelection(
    val resourceId: String,
    val remainingResourceIds: List<String>,
    val deferredRetryIds: List<String>,
    val retriedResourceIds: Set<String>
)

/** Keeps one soft-failed resource available after untried alternatives are exhausted. */
internal object AgentConnectorFallbackTrail {
    fun selectNext(
        failedResourceId: String,
        remainingResourceIds: List<String>,
        deferredRetryIds: List<String>,
        retriedResourceIds: Set<String>,
        retryFailedResource: Boolean
    ): AgentConnectorFallbackSelection? {
        val remaining = normalized(remainingResourceIds)
        val retried = normalized(retriedResourceIds).toSet()
        val deferred = normalized(deferredRetryIds).toMutableList()
        val failed = failedResourceId.trim()
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
                retriedResourceIds = retried
            )
        }
        val retry = deferred.firstOrNull { it !in retried } ?: return null
        return AgentConnectorFallbackSelection(
            resourceId = retry,
            remainingResourceIds = emptyList(),
            deferredRetryIds = deferred.filterNot { it == retry },
            retriedResourceIds = retried + retry
        )
    }

    fun parse(value: String): List<String> = normalized(value.split(','))

    fun encode(values: Collection<String>): String = normalized(values).joinToString(",")

    private fun normalized(values: Collection<String>): List<String> = values.asSequence()
        .map(String::trim)
        .filter(String::isNotBlank)
        .distinct()
        .take(MAX_RESOURCES)
        .toList()

    private const val MAX_RESOURCES = 12
}
