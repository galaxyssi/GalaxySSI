package com.galaxyssi.chat

import java.io.Closeable

/** Operation-owned opaque memoization; neither plaintext inputs nor a persistent key cache are retained. */
internal class KnowledgeIndexKeyMemo(private val capacity: Int = 64) : Closeable {
    private val tokens = BackupStagingTokenKey()
    private val values = LinkedHashMap<String, String>(capacity, .75f, true)
    private var closed = false
    internal val size get() = values.size
    init { require(capacity in 1..256) }

    fun key(kind: String, value: String, calculate: () -> String): String {
        check(!closed) { "Knowledge index memo is closed" }
        val token = tokens.token(kind, value)
        values[token]?.let { return it }
        val computed = calculate()
        values[token] = computed
        if (values.size > capacity) values.remove(values.entries.first().key)
        return computed
    }

    override fun close() {
        if (closed) return
        closed = true
        values.clear()
        tokens.close()
    }
}
