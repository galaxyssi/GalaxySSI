package com.galaxyssi.chat

/** Only opaque scope identifiers, never journal text or health values. */
internal object HealthCareVisitReviewVisibility {
    private val visible = mutableMapOf<Any, Pair<String, String>>()
    @Synchronized fun show(owner: Any, database: String, encounter: String) { visible[owner] = database to encounter }
    @Synchronized fun hide(owner: Any) { visible.remove(owner) }
    @Synchronized fun contains(database: String, encounter: String) = visible.values.any { it == (database to encounter) }
}
