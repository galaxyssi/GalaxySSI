package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ArtifactRequestRetryGateTest {
    @Test fun duplicateTapsCoalesceButTimeoutAllowsAnotherRequest() {
        var now = 0L
        val gate = ArtifactRequestRetryGate({ now })
        assertTrue(gate.add("image-a"))
        assertFalse(gate.add("image-a"))
        now = 29_999
        assertFalse(gate.add("image-a"))
        now = 30_000
        assertTrue(gate.add("image-a"))
        assertFalse(gate.add("image-a"))
    }

    @Test fun lateArrivalPreservesSaveIntentAndCompletionReleasesOnlyItsArtifact() {
        var now = 0L
        val gate = ArtifactRequestRetryGate({ now })
        assertTrue(gate.add("image-a"))
        assertTrue(gate.add("image-b"))
        now = 600_000
        assertTrue(gate.remove("image-a"))
        assertFalse(gate.remove("image-a"))
        assertTrue(gate.remove("image-b"))
        assertTrue(gate.add("image-a"))
    }

    @Test fun failedPublishCanBeRetriedImmediately() {
        val gate = ArtifactRequestRetryGate({ 1L })
        assertTrue(gate.add("image"))
        assertTrue(gate.remove("image"))
        assertTrue(gate.add("image"))
    }
}
