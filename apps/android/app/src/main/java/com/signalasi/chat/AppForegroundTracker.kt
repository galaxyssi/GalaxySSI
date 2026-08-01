package com.signalasi.chat

import java.util.Collections
import java.util.WeakHashMap

object AppForegroundTracker {
    private val foregroundActivities = Collections.newSetFromMap(WeakHashMap<Any, Boolean>())

    @Synchronized
    fun onActivityForeground(activity: Any) {
        foregroundActivities.add(activity)
    }

    @Synchronized
    fun onActivityBackground(activity: Any) {
        foregroundActivities.remove(activity)
    }

    @Synchronized
    fun isForeground(): Boolean = foregroundActivities.isNotEmpty()
}
