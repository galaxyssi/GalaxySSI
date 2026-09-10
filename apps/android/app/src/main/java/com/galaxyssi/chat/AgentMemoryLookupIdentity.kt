package com.galaxyssi.chat

/** Mirrors sameKey and equals(ignoreCase), without multi-character case expansion. */
internal object AgentMemoryLookupIdentity {
    fun material(item: AgentMemoryItem): String = listOf(
        "personal-memory-lookup-v1", item.kind.name, item.scope.name, item.scopeId, item.key,
        if (item.key.isBlank()) foldValue(item.value) else ""
    ).joinToString("") { "${it.length}:$it" }

    internal fun foldValue(value: String): String = buildString {
        var offset = 0
        while (offset < value.length) {
            val point = Character.codePointAt(value, offset)
            appendCodePoint(Character.toLowerCase(Character.toUpperCase(point)))
            offset += Character.charCount(point)
        }
    }
}
