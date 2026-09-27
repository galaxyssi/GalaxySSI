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
}
