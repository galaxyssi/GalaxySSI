package com.galaxyssi.chat

import android.view.WindowManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenAssistantChatWindowPolicyTest {
    @Test fun emptyComposerWrapsContentInsteadOfShowingAnEmptyTranscript() {
        assertEquals(WindowManager.LayoutParams.WRAP_CONTENT,
            ScreenAssistantChatWindowPolicy.height(2340, 3, false, false))
    }
    @Test fun compactTranscriptLeavesTheOtherAppVisible() {
        val height = ScreenAssistantChatWindowPolicy.height(2340, 3, false, true)
        assertTrue(height <= 2340 * 0.62f)
        assertTrue(height > 600)
    }
    @Test fun expandedTranscriptUsesTheSameWindowWithSystemBarSpace() {
        assertEquals(2148, ScreenAssistantChatWindowPolicy.height(2340, 3, true, true))
    }
    @Test fun compactWindowFitsShortScreens() {
        assertEquals(372, ScreenAssistantChatWindowPolicy.height(600, 1, false, true))
    }
    @Test fun expandedWindowFitsAboveSamsungKeyboard() {
        assertEquals(1183, ScreenAssistantChatWindowPolicy.height(2340, 3, true, true, 1183))
    }
    @Test fun compactTranscriptAlsoFitsAboveKeyboard() {
        assertEquals(800, ScreenAssistantChatWindowPolicy.height(2340, 3, false, true, 800))
    }
    @Test fun minimumExpandedHeightMustNotPushComposerBelowKeyboard() {
        assertEquals(300, ScreenAssistantChatWindowPolicy.height(900, 3, true, true, 300))
    }
    @Test fun closingKeyboardRestoresExpandedHeight() {
        assertEquals(2148, ScreenAssistantChatWindowPolicy.height(2340, 3, true, true, 2200))
    }
    @Test fun emptyComposerStillWrapsWhenKeyboardIsOpen() {
        assertEquals(WindowManager.LayoutParams.WRAP_CONTENT,
            ScreenAssistantChatWindowPolicy.height(2340, 3, false, false, 1183))
    }
}
