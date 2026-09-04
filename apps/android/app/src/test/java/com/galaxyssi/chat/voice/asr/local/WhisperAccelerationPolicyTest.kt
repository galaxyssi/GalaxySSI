package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.voice.model.WhisperModelCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WhisperAccelerationPolicyTest {
    @Test
    fun whisperDetectsSmeWithoutLoadingTheLlamaRuntime() {
        val cpuInfo = "Features : fp asimd sve2 sme smei8i32 smef32f32"

        assertTrue(WhisperCpuFeatures.osExposesSme(cpuInfo))
        assertFalse(WhisperCpuFeatures.osExposesSme("Features : fp asimd sve2"))
    }

    @Test
    fun qnnUsesOnlyModelFamiliesWithAValidatedAndroidPipeline() {
        assertTrue(WhisperQnnSupport.isSupportedFamily(WhisperModelCatalog.require("tiny").family))
        assertTrue(WhisperQnnSupport.isSupportedFamily(WhisperModelCatalog.require("base").family))
        assertTrue(WhisperQnnSupport.isSupportedFamily(WhisperModelCatalog.require("small").family))
        assertFalse(WhisperQnnSupport.isSupportedFamily(WhisperModelCatalog.require("medium").family))
        assertFalse(WhisperQnnSupport.isSupportedFamily(WhisperModelCatalog.require("large").family))
        assertFalse(
            CompactWhisperQnnModelCatalog.all.any {
                it.manifest.modelId == LargeTurboQnnModelCatalog.MODEL_ID
            }
        )
    }

    @Test
    fun loadedModelReportsTheBackendThatActuallyExecutedIt() {
        val profile = WhisperModelCatalog.require("tiny")
        val qnn = WhisperLoadedModel(
            profile = profile,
            threadCount = 2,
            loadedAtMillis = 1L,
            loadDurationMs = 2L,
            warmUpTimings = null,
            accelerationBackend = WhisperAccelerationBackend.QNN_HTP,
            accelerationDetail = "Qualcomm QNN / HTP"
        )

        assertEquals(WhisperAccelerationBackend.QNN_HTP, qnn.accelerationBackend)
        assertEquals("Qualcomm QNN / HTP", qnn.accelerationDetail)
    }
}
