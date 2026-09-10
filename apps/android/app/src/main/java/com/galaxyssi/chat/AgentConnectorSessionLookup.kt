package com.galaxyssi.chat

/** An explicit turn is authoritative; only identity-less legacy replies may scan. */
internal object AgentConnectorSessionLookup {
    fun find(
        sourceMessageId: Long,
        turnId: String,
        indexed: () -> String?,
        matches: (String) -> Boolean,
        removeStaleIndex: (String) -> Unit,
        legacyKeys: () -> Sequence<String>,
        remember: (String) -> Unit
    ): String? {
        if (sourceMessageId <= 0L) return null
        val exactKey = turnId.trim().takeIf(String::isNotBlank)?.let { "task:$it" }
        if (exactKey != null) return exactKey.takeIf(matches)
        val stale = indexed()?.let { key ->
            if (matches(key)) return key
            removeStaleIndex(key)
            key
        }
        return legacyKeys().filter { it != stale }.firstOrNull(matches)?.also(remember)
    }
}
