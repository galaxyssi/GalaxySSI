package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class ScreenAssistantBubbleTapPolicyTest {
    @Test fun completedPanelStartsAnotherAnalysisOnFirstTap() {
        assertEquals(ScreenAssistantBubbleTap.ANALYZE, action(panel = true))
    }

    @Test fun idleBubbleStartsAnalysisOnFirstTap() {
        assertEquals(ScreenAssistantBubbleTap.ANALYZE, action())
    }

    @Test fun runningTaskIsShownWithoutDuplicateSubmission() {
        assertEquals(ScreenAssistantBubbleTap.SHOW_PROGRESS, action(running = true))
    }

    @Test fun runningPanelCanStillCollapseWithoutCancellation() {
        assertEquals(ScreenAssistantBubbleTap.COLLAPSE, action(panel = true, running = true))
    }

    @Test fun promptIsClosedWithoutSubmittingItsDraft() {
        assertEquals(ScreenAssistantBubbleTap.DISMISS_PROMPT, action(prompt = true))
        assertEquals(ScreenAssistantBubbleTap.DISMISS_PROMPT, action(prompt = true, running = true))
    }

    private fun action(prompt: Boolean = false, panel: Boolean = false, running: Boolean = false) =
        ScreenAssistantBubbleTapPolicy.action(prompt, panel, running)
}
