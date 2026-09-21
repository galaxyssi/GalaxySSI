package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CloudCitationPreviewPresentationTest {
    @Test fun repairPrefixDoesNotShrinkTheVisibleDraft() {
        val presentation = CloudCitationPreviewPresentation()
        assertEquals("First paragraph. Second paragraph.", presentation.replace("First paragraph. Second paragraph."))
        assertNull(presentation.replace("Revised first paragraph."))
        assertEquals("Revised first paragraph. Revised second paragraph.",
            presentation.replace("Revised first paragraph. Revised second paragraph."))
    }

    @Test fun explicitRetractionStillRemovesInvalidOrFailedOutput() {
        val presentation = CloudCitationPreviewPresentation()
        presentation.replace("A provisional paragraph")
        assertEquals("", presentation.replace(""))
        assertEquals("New", presentation.replace("New"))
    }

    @Test fun identicalDraftDoesNotCauseAnotherRender() {
        val presentation = CloudCitationPreviewPresentation()
        presentation.replace("Draft")
        assertNull(presentation.replace("Draft"))
    }

    @Test fun attemptsDoNotSharePreviewState() {
        CloudCitationPreviewPresentation().replace("Long old provider draft")
        assertEquals("New", CloudCitationPreviewPresentation().replace("New"))
    }
}
