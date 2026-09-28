package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenAssistantVisibilityPolicyTest {
    private fun visible(
        enabled: Boolean = true,
        sdk: Int = 33,
        locked: Boolean = false,
        capturing: Boolean = false
    ) = ScreenAssistantVisibilityPolicy.shouldShow(
        enabled, sdk, locked, capturing
    )

    @Test fun showsImmediatelyOverGalaxySSIWhenEnabled() {
        assertTrue(visible())
        assertFalse(visible(enabled = false))
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
