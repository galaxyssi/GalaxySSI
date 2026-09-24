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
        foregroundPackage: String = "com.example.other"
    ) = ScreenAssistantVisibilityPolicy.shouldShow(
        enabled, sdk, appForeground, locked, capturing, foregroundPackage, "com.galaxyssi.chat"
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
    }

    @Test fun requiresAccessibilityScreenshotApi() {
        assertFalse(visible(sdk = 29))
        assertTrue(visible(sdk = 30))
    }
}
