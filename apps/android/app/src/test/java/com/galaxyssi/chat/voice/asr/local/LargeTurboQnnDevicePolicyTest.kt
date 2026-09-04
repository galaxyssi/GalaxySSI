package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LargeTurboQnnDevicePolicyTest {
    private val policy = LargeTurboQnnDevicePolicy()

    @Test
    fun `matching S26U runtime and installed model are ready`() {
        val decision = policy.evaluate(snapshot())
        assertEquals(QnnAsrEligibility.READY, decision.eligibility)
        assertEquals("large_turbo_qnn_ready", decision.reasonCode)
    }

    @Test
    fun `missing model requests download without falling back`() {
        val decision = policy.evaluate(snapshot(modelState = QnnContextModelState.NOT_INSTALLED))
        assertEquals(QnnAsrEligibility.MODEL_DOWNLOAD_REQUIRED, decision.eligibility)
        assertTrue(decision.fallbackOrder.isEmpty())
    }

    @Test
    fun `low reported memory is advisory and not a fixed rejection threshold`() {
        val decision = policy.evaluate(snapshot(availableMemory = 512L * 1024L * 1024L))
        assertEquals(QnnAsrEligibility.READY, decision.eligibility)
        assertTrue("memory_headroom_low" in decision.advisories)
    }

    @Test
    fun `wrong chipset or runtime requires ordered fallback`() {
        val wrongChipset = policy.evaluate(snapshot(socModel = "SM8750"))
        assertEquals(QnnAsrEligibility.FALLBACK_REQUIRED, wrongChipset.eligibility)
        assertEquals(QnnAsrFallbackTarget.SMALL_OR_BASE_QNN, wrongChipset.fallbackOrder.first())

        val wrongRuntime = policy.evaluate(snapshot(qnnVersion = "2.44.0"))
        assertEquals(QnnAsrEligibility.FALLBACK_REQUIRED, wrongRuntime.eligibility)
        assertEquals("qnn_runtime_incompatible", wrongRuntime.reasonCode)
    }

    @Test
    fun `newer runtime in the same major series accepts the model context`() {
        val decision = policy.evaluate(snapshot(qnnVersion = "2.47.0"))
        assertEquals(QnnAsrEligibility.READY, decision.eligibility)
        assertEquals("large_turbo_qnn_ready", decision.reasonCode)
    }

    @Test
    fun `different runtime major series is rejected`() {
        val decision = policy.evaluate(snapshot(qnnVersion = "3.45.0"))
        assertEquals(QnnAsrEligibility.FALLBACK_REQUIRED, decision.eligibility)
        assertEquals("qnn_runtime_incompatible", decision.reasonCode)
    }

    @Test
    fun `missing V81 runtime never attempts the S26U context`() {
        val decision = policy.evaluate(snapshot(libraries = setOf("libQnnSystem.so", "libQnnHtp.so")))
        assertEquals(QnnAsrEligibility.FALLBACK_REQUIRED, decision.eligibility)
        assertEquals("qnn_runtime_missing", decision.reasonCode)
    }

    private fun snapshot(
        socModel: String = "SM8850-AD",
        qnnVersion: String = "2.45.0",
        libraries: Set<String> = setOf("libQnnSystem.so", "libQnnHtp.so", "libQnnHtpV81Stub.so"),
        availableMemory: Long = 6L * 1024L * 1024L * 1024L,
        modelState: QnnContextModelState = QnnContextModelState.INSTALLED
    ) = QnnAsrDeviceSnapshot(
        androidApiLevel = 36,
        supportedAbis = setOf("arm64-v8a"),
        manufacturer = "Samsung",
        brand = "Samsung",
        hardware = "qcom",
        socManufacturer = "Qualcomm",
        socModel = socModel,
        nativeLibraries = libraries,
        qnnRuntimeVersion = qnnVersion,
        availableMemoryBytes = availableMemory,
        availableStorageBytes = 12L * 1024L * 1024L * 1024L,
        activeModelState = modelState
    )
}
