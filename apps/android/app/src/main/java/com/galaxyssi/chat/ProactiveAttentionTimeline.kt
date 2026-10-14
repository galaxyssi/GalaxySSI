package com.galaxyssi.chat

/** A reading snapshot: incoming news and revised bodies never move an active reader. */
internal class ProactiveAttentionTimeline(private val batchSize: Int = 20) {
    private var source = emptyList<GlobalProactiveInboxItem>()
    private var byKey = emptyMap<String, GlobalProactiveInboxItem>()
    private var eligible = emptyList<String>()
    private var saved = emptySet<String>()
    private val confirmedReads = mutableMapOf<String, Long>()
    var filter = AttentionFeedFilter.ALL
        private set
    var visible = emptyList<GlobalProactiveInboxItem>()
        private set
    val expanded = linkedSetOf<String>()
    val unreadCount get() = source.count { it.isNew }
    val hasOlder get(): Boolean {
        val existing = visible.mapTo(hashSetOf()) { it.key }
        return eligible.any { it !in existing }
    }
    val newerCount get() = newer().size

    fun update(items: List<GlobalProactiveInboxItem>, savedKeys: Set<String>) {
        source = items.map { item ->
            val readAt = confirmedReads[item.key] ?: 0L
            if (item.viewedAtMillis >= readAt) confirmedReads.remove(item.key)
            if (readAt > item.viewedAtMillis) item.copy(viewedAtMillis = readAt) else item
        }.sortedWith(order)
        byKey = source.associateBy { it.key }
        saved = savedKeys
        // Keep the body, order and membership even when the unread filter no longer matches.
        visible = visible.map { old -> byKey[old.key]?.let { current ->
            old.copy(viewedAtMillis = current.viewedAtMillis, feedbackKind = current.feedbackKind)
        } ?: old }
    }

    fun begin(nextFilter: AttentionFeedFilter, restoredKeys: List<String> = emptyList()) {
        filter = nextFilter
        eligible = source.filter { matches(it) }.map { it.key }
        visible = restoredKeys.distinct().mapNotNull(byKey::get)
        if (visible.isEmpty()) visible = eligible.take(batchSize).mapNotNull(byKey::get)
        if (restoredKeys.isNotEmpty()) {
            val last = visible.lastOrNull()
            val restored = restoredKeys.toSet()
            eligible = visible.map { it.key } + source.filter { matches(it) &&
                (last == null || order.compare(it, last) > 0) && it.key !in restored }.map { it.key }
        }
        expanded.retainAll(visible.map { it.key }.toSet())
    }

    fun loadOlder(): Boolean {
        val existing = visible.mapTo(hashSetOf()) { it.key }
        val next = eligible.asSequence().filter { it !in existing }.mapNotNull(byKey::get).take(batchSize).toList()
        visible = visible + next
        return next.isNotEmpty()
    }

    fun loadNewer(): Boolean {
        // Closest batch first: a burst never creates a hole in the timeline.
        val next = newer().takeLast(batchSize)
        visible = next + visible
        return next.isNotEmpty()
    }

    fun markRead(keys: Set<String>, now: Long) {
        keys.forEach { confirmedReads[it] = now }
        fun read(item: GlobalProactiveInboxItem) = if (item.key in keys && item.isNew) item.copy(viewedAtMillis = now) else item
        source = source.map(::read)
        byKey = source.associateBy { it.key }
        visible = visible.map(::read)
    }

    fun setSaved(keys: Set<String>) { saved = keys }

    fun remove(key: String) {
        visible = visible.filterNot { it.key == key }; eligible = eligible - key; expanded.remove(key)
    }

    private fun matches(item: GlobalProactiveInboxItem) = ProactiveAttentionPolicy.matches(item, filter, saved)
    private fun newer(): List<GlobalProactiveInboxItem> {
        val first = visible.firstOrNull() ?: return source.filter(::matches)
        val existing = visible.mapTo(hashSetOf()) { it.key }
        return source.takeWhile { order.compare(it, first) < 0 }.filter { matches(it) && it.key !in existing }
    }

    companion object {
        private val order = compareByDescending<GlobalProactiveInboxItem> { it.deliveredAtMillis }
            .thenByDescending { it.createdAtMillis }.thenBy { it.key }
    }
}

internal class AttentionReadDwell(private val dwellMillis: Long = 2_000) {
    private val since = mutableMapOf<String, Long>()
    fun sample(visible: Set<String>, now: Long, active: Boolean): Set<String> {
        if (!active) { since.clear(); return emptySet() }
        since.keys.retainAll(visible)
        visible.forEach { since.putIfAbsent(it, now) }
        return since.filterValues { now - it >= dwellMillis }.keys.toSet()
    }
    fun reset() = since.clear()
}
