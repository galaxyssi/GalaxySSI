package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareDocumentTest {
    private fun id() = UUID.randomUUID().toString()
    private fun source() = HealthCareDocumentRef(id(), "a".repeat(64), 1234, "application/pdf")
    private fun link() = HealthCareDocumentLink(id(), id(), id(), 8, 7, 5, source(), 1000)
    @Test fun wholeDocumentAndPageRoundTripWithoutInventingClinicalApproval() {
        val whole = link()
        assertEquals(whole, HealthCareDocumentLink.from(whole.json()))
        val page = whole.copy(source = whole.source.copy(page = 2, pageCount = 4))
        assertEquals(page, HealthCareDocumentLink.from(page.json()))
        assertEquals("user_selected_original", page.json().getString("provenance"))
        assertFalse(page.json().has("instruction")); assertFalse(page.json().has("verified_clinician"))
    }
    @Test fun invalidPageRangesAndHalfSpecifiedRangesAreRejected() {
        listOf(0 to 4, -1 to 4, 5 to 4, 1 to 0).forEach { (page, count) ->
            assertThrows(IllegalArgumentException::class.java) { source().copy(page = page, pageCount = count) }
        }
        assertThrows(IllegalArgumentException::class.java) { source().copy(page = 1) }
        assertThrows(IllegalArgumentException::class.java) { source().copy(pageCount = 1) }
    }
    @Test fun imagePagesAreSingleAndUnpagedFormatsCannotClaimPageProvenance() {
        assertNotNull(source().copy(mime = "image/png", page = 1, pageCount = 1))
        assertNotNull(source().copy(mime = "text/csv"))
        assertThrows(IllegalArgumentException::class.java) { source().copy(mime = "image/png", page = 2, pageCount = 2) }
        assertThrows(IllegalArgumentException::class.java) { source().copy(mime = "text/csv", page = 1, pageCount = 2) }
    }
    @Test fun invalidIdentityHashSizeAndMimeAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { source().copy(originalId = "../original") }
        listOf("", "A".repeat(64), "g".repeat(64), "a".repeat(63)).forEach {
            assertThrows(IllegalArgumentException::class.java) { source().copy(sha256 = it) }
        }
        assertThrows(IllegalArgumentException::class.java) { source().copy(size = 0) }
        listOf("", " application/pdf", "x".repeat(201)).forEach {
            assertThrows(IllegalArgumentException::class.java) { source().copy(mime = it) }
        }
    }
    @Test fun receiptRequiresExactParentRevisionsAndCannotUpgradeUserProvenance() {
        val value = link()
        assertThrows(IllegalArgumentException::class.java) { value.copy(revision = 9) }
        assertThrows(IllegalArgumentException::class.java) { value.copy(expectedEncounter = 8) }
        assertThrows(IllegalArgumentException::class.java) { value.copy(expectedEncounter = 0) }
        assertThrows(IllegalArgumentException::class.java) { value.copy(createdAt = 0) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareDocumentLink.from(value.json().put("provenance", "verified_clinician")) }
    }
}
