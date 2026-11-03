package com.galaxyssi.chat

/** A background panel requires an OS-authorized launch, not merely a posted notification. */
internal object ContactReminderPresentationPolicy {
    enum class Route { PANEL, FULL_SCREEN_NOTIFICATION, NOTIFICATION }

    fun route(
        foreground: Boolean,
        locked: Boolean,
        quiet: Boolean,
        backgroundEnabled: Boolean,
        lockscreenEnabled: Boolean,
        overlayAllowed: Boolean,
        fullScreenAllowed: Boolean,
        notificationsAllowed: Boolean
    ): Route {
        if (quiet || (locked && !lockscreenEnabled)) return Route.NOTIFICATION
        if (foreground && !locked) return Route.PANEL
        if (!notificationsAllowed) return Route.NOTIFICATION
        if (locked) return when {
            overlayAllowed -> Route.PANEL
            fullScreenAllowed -> Route.FULL_SCREEN_NOTIFICATION
            else -> Route.NOTIFICATION
        }
        return if (backgroundEnabled && overlayAllowed) Route.PANEL else Route.NOTIFICATION
    }
}
