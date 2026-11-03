package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthPhotoQualityPolicyTest {
    @Test fun edgeDetailIsHigherThanAFlatFieldAndDoesNotChangeBrightness() {
        val flat = IntArray(64 * 64) { 128 }
        val checker = IntArray(64 * 64) { if ((it / 64 + it % 64) % 2 == 0) 255 else 0 }
        val a = HealthPhotoQualityPolicy.inspect(flat, 64, 64)
        val b = HealthPhotoQualityPolicy.inspect(checker, 64, 64)
        assertEquals(0.0, a.first, 0.0); assertTrue(b.first > 1000)
        assertEquals(128.0, a.second, 0.0); assertEquals(127.5, b.second, .001)
    }
    @Test fun darknessAndSmallSizeRemainSeparateQualityHints() {
        val dark = HealthPhotoQuality(1200, 1600, 90, 100.0, 10.0)
        assertTrue(dark.dark); assertFalse(dark.small); assertFalse(dark.lowDetail)
        val small = dark.copy(width = 200, detail = 1.0, luminance = 100.0)
        assertTrue(small.small); assertTrue(small.lowDetail); assertFalse(small.dark)
        assertTrue(small.needsReview)
    }
    @Test fun malformedPlanesAreRejectedRatherThanScoredAsSharp() {
        for (operation in listOf({ HealthPhotoQualityPolicy.inspect(intArrayOf(), 64, 64) },
            { HealthPhotoQualityPolicy.inspect(IntArray(4), 2, 2) }, { HealthPhotoQualityPolicy.inspect(IntArray(9) { 300 }, 3, 3) })) {
            assertTrue(runCatching(operation).isFailure)
        }
    }
    @Test fun photoBatchAndPerPageQualityRoundTripWithoutAnyMeasurement() {
        val batch = HealthPhotoBatch(UUID.randomUUID().toString(), "report", 1)
        val quality = HealthPhotoQuality(1200, 1600, 90, 123.5, 100.5)
        val page = HealthPhotoPage(UUID.randomUUID().toString(), batch.id, 3, quality)
        assertEquals(batch, HealthPhotoBatch.from(JSONObject(batch.json().toString())))
        assertEquals(page, HealthPhotoPage.from(JSONObject(page.json().toString())))
        assertFalse(page.json().has("glucose")); assertFalse(page.json().has("values"))
    }
    @Test fun pendingPageIsNotMistakenForAnInspectedPage() {
        val page = HealthPhotoPage(UUID.randomUUID().toString(), UUID.randomUUID().toString(), 0)
        assertNull(HealthPhotoPage.from(page.json()).quality)
    }
    @Test fun oldImportJobsDoNotBecomeCaptureDraftsAfterUpgrade() {
        val job = HealthImportJob(UUID.randomUUID().toString(), "content://test/report", 1)
        val old = job.json().apply { remove("capture_batch"); remove("capture_submitted") }
        assertEquals(job, HealthImportJob.from(old))
    }
    @Test fun captureAndSubmissionMetadataArePreservedAcrossJobRoundTrips() {
        val job = HealthImportJob(UUID.randomUUID().toString(), "content://test/report", 1,
            captureBatch = UUID.randomUUID().toString(), captureSubmitted = true)
        assertEquals(job, HealthImportJob.from(job.json()))
    }
}
