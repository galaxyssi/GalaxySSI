package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareVisitSummaryTest {
    private val first = HealthCareVisitItem("a", HealthCareVisitSection.MEASUREMENTS, "Measurement", "Synthetic value")
    private val second = HealthCareVisitItem("b", HealthCareVisitSection.ACTIONS, "Action", "Private fixture feedback")
    private val summary = HealthCareVisitSummary(UUID.randomUUID().toString(), 3, HealthMetric.GLUCOSE,
        "source", "settings", "permission", null, 1000, setOf(first.section, second.section), "Visit preparation",
        "Personal notes, not a diagnosis", "Selected items only", listOf(first, second))

    @Test fun shareIncludesOnlyReviewedKeysInVisibleOrder() {
        val text = summary.selectedText(setOf("a"))
        assertTrue(text.contains(first.text)); assertFalse(text.contains(second.text))
        assertFalse(text.contains(summary.concernId)); assertTrue(text.endsWith(summary.limitations))
        val all = summary.selectedText(linkedSetOf("b", "a"))
        assertTrue(all.indexOf(first.text) < all.indexOf(second.text))
    }
    @Test fun emptyAndForeignSelectionsAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { summary.selectedText(emptySet()) }
        assertThrows(IllegalArgumentException::class.java) { summary.selectedText(setOf("foreign")) }
        assertThrows(IllegalArgumentException::class.java) { summary.copy(items = listOf(first, first)) }
        assertThrows(IllegalArgumentException::class.java) { summary.copy(sections = setOf(first.section)) }
    }
    @Test fun oversizedTextIsRejectedInsteadOfTruncatingEvidence() {
        val long = summary.copy(items = listOf(first.copy(text = "x".repeat(HealthCareVisitSummary.MAX_SHARED_CHARS))))
        assertThrows(IllegalArgumentException::class.java) { long.selectedText(setOf("a")) }
    }
    @Test fun previewExpiresAndBackwardClockCannotExtendAuthorization() {
        assertTrue(HealthCareVisitSummary.fresh(1000, 1000))
        assertTrue(HealthCareVisitSummary.fresh(1000, 1000 + HealthCareVisitSummary.MAX_AGE - 1))
        assertFalse(HealthCareVisitSummary.fresh(1000, 1000 + HealthCareVisitSummary.MAX_AGE))
        assertFalse(HealthCareVisitSummary.fresh(1000, 999))
    }
    @Test fun onlyBoundedItemsAndNonemptyScopeCanBePreviewed() {
        assertThrows(IllegalArgumentException::class.java) { summary.copy(sections = emptySet()) }
        assertThrows(IllegalArgumentException::class.java) { summary.copy(items = List(101) { first.copy(key = "row-$it") }) }
    }
}
