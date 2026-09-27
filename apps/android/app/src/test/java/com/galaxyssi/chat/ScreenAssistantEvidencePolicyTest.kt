package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ScreenAssistantEvidencePolicyTest {
    private fun node(text: String, description: String = "", editable: Boolean = false, password: Boolean = false) =
        PhoneUiNode("0/1", text, description, "internal:view_id", "android.TextView", "0,0,100,100",
            true, true, editable, false, true, null, password)
    private fun snapshot(vararg nodes: PhoneUiNode, truncated: Boolean = false) =
        PhoneUiSnapshot(42, "test.gallery", "internal-revision", nodes.toList(), truncated)

    @Test fun imageEvidenceIsNotReplacedByVisibleGalleryButtons() {
        assertTrue(ScreenAssistantEvidencePolicy.shouldCaptureImage(snapshot(node("Share"), node("Delete"))))
        assertTrue(ScreenAssistantEvidencePolicy.shouldCaptureImage(null))
        val evidence = ScreenAssistantEvidencePolicy.supplementaryText(snapshot(node("Share"), node("Delete")))
        assertTrue(evidence.contains("not a description of the image"))
        assertFalse(evidence.contains("internal:view_id"))
        assertFalse(evidence.contains("android.TextView"))
        assertFalse(evidence.contains("internal-revision"))
        assertFalse(evidence.contains("clickable"))
    }

    @Test fun repeatedLabelsAreDeduplicatedWithoutReordering() {
        val evidence = ScreenAssistantEvidencePolicy.supplementaryText(snapshot(
            node("Brand Flow", "Brand Flow"), node("Brand Flow"), node("Coming soon")))
        assertEquals(1, Regex("Brand Flow").findAll(evidence).count())
        assertTrue(evidence.indexOf("Brand Flow") < evidence.indexOf("Coming soon"))
    }

    @Test fun passwordAndEditableContentsAreNeverIncluded() {
        assertFalse(ScreenAssistantEvidencePolicy.shouldCaptureImage(snapshot(node("secret", password = true))))
        val evidence = ScreenAssistantEvidencePolicy.supplementaryText(snapshot(
            node("private password", password = true), node("private draft", editable = true), node("Product")))
        assertFalse(evidence.contains("private password"))
        assertFalse(evidence.contains("private draft"))
        assertTrue(evidence.contains("protected password field"))
        assertTrue(evidence.contains("Product"))
    }

    @Test fun boundedTextRetainsAnExplicitIncompleteMarker() {
        val evidence = ScreenAssistantEvidencePolicy.supplementaryText(snapshot(node("x".repeat(5_000))), 50)
        assertTrue(evidence.contains("x".repeat(50)))
        assertFalse(evidence.contains("x".repeat(51)))
        assertTrue(evidence.contains("UI text is incomplete"))
        assertTrue(ScreenAssistantEvidencePolicy.supplementaryText(snapshot(node("short"), truncated = true))
            .contains("UI text is incomplete"))
    }

    @Test fun displayedQuestionIsOnlyTheQuestionOrDefault() {
        assertEquals("What is this?", ScreenAssistantEvidencePolicy.displayedQuestion(" What is this? ", "Analyze screen"))
        assertEquals("Analyze screen", ScreenAssistantEvidencePolicy.displayedQuestion(" ", "Analyze screen"))
    }
}
