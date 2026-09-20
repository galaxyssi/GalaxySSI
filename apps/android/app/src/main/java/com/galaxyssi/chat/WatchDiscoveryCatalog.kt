package com.galaxyssi.chat

/** Service identity, not a display label, owns each row and each pending selection. */
internal class WatchDiscoveryCatalog<T> {
    data class Key(val serviceName: String, val serviceType: String, val network: String)
    private val entries = linkedMapOf<Key, T>()
    var selected: Key? = null
        private set
    var selectionRevision = 0L
        private set
    val values: List<T> get() = entries.values.toList()
    fun isEmpty(): Boolean = entries.isEmpty()
    fun put(key: Key, value: T) { entries[key] = value }
    fun remove(key: Key): Boolean {
        entries.remove(key)
        return (selected == key).also { if (it) releaseSelection() }
    }
    fun select(key: Key): Boolean {
        if (selected != null || key !in entries) return false
        selected = key
        selectionRevision++
        return true
    }
    fun releaseSelection() { selected = null; selectionRevision++ }
    fun clear() { entries.clear(); releaseSelection() }
}
