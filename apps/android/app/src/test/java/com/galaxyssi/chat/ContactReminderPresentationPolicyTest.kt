package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test
import com.galaxyssi.chat.ContactReminderPresentationPolicy.Route.*

class ContactReminderPresentationPolicyTest {
    private fun route(foreground: Boolean = false, locked: Boolean = false, quiet: Boolean = false,
        background: Boolean = true, lockscreen: Boolean = true, overlay: Boolean = false,
        fullScreen: Boolean = false, notifications: Boolean = true) =
        ContactReminderPresentationPolicy.route(foreground, locked, quiet, background, lockscreen,
            overlay, fullScreen, notifications)

    @Test fun foregroundKeepsTheExistingPanel() { assertEquals(PANEL, route(foreground = true)) }
    @Test fun backgroundWithoutPermissionOnlyPostsNotification() { assertEquals(NOTIFICATION, route()) }
    @Test fun backgroundWithUserAuthorizationShowsPanel() { assertEquals(PANEL, route(overlay = true)) }
    @Test fun fullScreenPermissionDoesNotAuthorizeUnlockedBackgroundLaunch() {
        assertEquals(NOTIFICATION, route(fullScreen = true))
    }
    @Test fun backgroundOptOutIsRespected() { assertEquals(NOTIFICATION, route(overlay = true, background = false)) }
    @Test fun lockscreenUsesAuthorizedPanelBeforeFullScreenIntent() {
        assertEquals(PANEL, route(locked = true, overlay = true, fullScreen = true))
    }
    @Test fun lockscreenFallsBackToSystemFullScreenNotification() {
        assertEquals(FULL_SCREEN_NOTIFICATION, route(locked = true, fullScreen = true))
    }
    @Test fun lockscreenWithoutAuthorizationOnlyPostsNotification() { assertEquals(NOTIFICATION, route(locked = true)) }
    @Test fun lockscreenOptOutIsRespectedEvenWithVisibleActivity() {
        assertEquals(NOTIFICATION, route(foreground = true, locked = true, lockscreen = false, overlay = true, fullScreen = true))
    }
    @Test fun staleForegroundFlagCannotBypassLockscreenAuthorization() {
        assertEquals(NOTIFICATION, route(foreground = true, locked = true))
    }
    @Test fun callsAndRecordingsNeverOpenAPanel() {
        for (foreground in listOf(false, true)) for (locked in listOf(false, true)) {
            assertEquals(NOTIFICATION, route(foreground = foreground, locked = locked, quiet = true, overlay = true, fullScreen = true))
        }
    }
    @Test fun disabledNotificationsDoNotLaunchBackgroundPanel() {
        assertEquals(NOTIFICATION, route(overlay = true, notifications = false))
        assertEquals(NOTIFICATION, route(locked = true, overlay = true, fullScreen = true, notifications = false))
    }
    @Test fun foregroundStillWorksWhenSystemNotificationsAreDisabled() {
        assertEquals(PANEL, route(foreground = true, notifications = false))
    }
}
