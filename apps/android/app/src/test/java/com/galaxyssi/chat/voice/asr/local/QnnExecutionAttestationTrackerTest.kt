package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class QnnExecutionAttestationTrackerTest {
    @Test
    fun verificationAdvancesOnlyAfterSuccessfulEncoderAndDecoderExecutions() {
        val tracker = QnnExecutionAttestationTracker(htpSharedMemoryEnabled = true)

        val configured = tracker.executionAttestation()
        assertEquals(QnnExecutionVerification.CONFIGURED, configured.verification)
        assertFalse(configured.contextBinariesRestored)
        assertFalse(configured.fullHtpExecutionVerified)

        tracker.markContextBinariesRestored()
        tracker.recordEncoderExecution()
        val encoded = tracker.executionAttestation()
        assertEquals(QnnExecutionVerification.ENCODER_EXECUTED, encoded.verification)
        assertEquals(1L, encoded.encoderExecutionCount)
        assertEquals(0L, encoded.decoderExecutionCount)
        assertFalse(encoded.fullHtpExecutionVerified)

        tracker.recordDecoderExecution()
        val verified = tracker.executionAttestation(warmupCompleted = true)
        assertEquals(QnnExecutionVerification.ENCODER_AND_DECODER_EXECUTED, verified.verification)
        assertTrue(verified.fullHtpExecutionVerified)
        assertTrue(verified.warmupCompleted)
        assertTrue(verified.htpSharedMemoryEnabled)
        assertEquals("QNNExecutionProvider", verified.executionProvider)
        assertEquals("htp", verified.backendType)
        assertEquals(5_026, verified.expectedEncoderNpuLayers)
        assertEquals(1_213, verified.expectedDecoderNpuLayers)
        assertEquals(QnnLayerCountSource.QUALCOMM_TARGET_DEVICE_PROFILE, verified.layerCountSource)
    }
}
