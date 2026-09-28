package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenAssistantVisibilityPolicyTest {
    private fun visible(
        enabled: Boolean = true,
        sdk: Int = 33,
        appForeground: Boolean = false,
        locked: Boolean = false,
        capturing: Boolean = false,
        foregroundPackage: String = "com.example.other",
        assistantChatOpen: Boolean = false
    ) = ScreenAssistantVisibilityPolicy.shouldShow(
        enabled, sdk, appForeground, locked, capturing, foregroundPackage, "com.galaxyssi.chat",
        assistantChatOpen
    )

    @Test fun onlyShowsOverAnotherUnlockedAppWhenEnabled() {
        assertTrue(visible())
        assertFalse(visible(enabled = false))
        assertFalse(visible(appForeground = true))
        assertFalse(visible(foregroundPackage = "com.galaxyssi.chat"))
        assertFalse(visible(locked = true))
    }

    @Test fun screenshotCannotIncludeOurOwnBubble() {
        assertFalse(visible(capturing = true))
        assertFalse(visible(capturing = true, appForeground = true,
            foregroundPackage = "com.galaxyssi.chat", assistantChatOpen = true))
    }

    @Test fun floatingChatKeepsBubbleVisibleWhileAppIsForeground() {
        assertTrue(visible(appForeground = true, foregroundPackage = "com.galaxyssi.chat",
            assistantChatOpen = true))
        assertFalse(visible(appForeground = true, foregroundPackage = "com.galaxyssi.chat"))
        assertFalse(visible(appForeground = true, foregroundPackage = "com.galaxyssi.chat",
            assistantChatOpen = true, locked = true))
    }

    @Test fun requiresAccessibilityScreenshotApi() {
        assertFalse(visible(sdk = 29))
        assertTrue(visible(sdk = 30))
    }
}
