package com.signalasi.chat

import java.util.Collections
import java.util.WeakHashMap

object AppForegroundTracker {
    private val foregroundActivities = Collections.newSetFromMap(WeakHashMap<Any, Boolean>())
    private val visibleConversations = WeakHashMap<Any, String>()

    @Synchronized
    fun onActivityForeground(activity: Any, visibleConversationId: String? = null) {
        foregroundActivities.add(activity)
        visibleConversationId
            ?.takeIf(String::isNotBlank)
            ?.let { visibleConversations[activity] = it }
    }

    @Synchronized
    fun onActivityBackground(activity: Any) {
        foregroundActivities.remove(activity)
        visibleConversations.remove(activity)
    }

    @Synchronized
    fun isForeground(): Boolean = foregroundActivities.isNotEmpty()

    @Synchronized
    fun onConversationVisible(activity: Any, contactId: String) {
        if (contactId.isNotBlank()) visibleConversations[activity] = contactId
    }

    @Synchronized
    fun onConversationHidden(activity: Any) {
        visibleConversations.remove(activity)
    }

    @Synchronized
    fun isConversationVisible(contactId: String): Boolean =
        contactId.isNotBlank() && visibleConversations.values.any { it == contactId }
}
