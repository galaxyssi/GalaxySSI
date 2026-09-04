package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalModelRuntimeEstimatorTest {
    @Test
    fun normalDeviceAcceptsGemmaWorkload() {
        val estimate = estimate()

        assertEquals(LocalModelRuntimeReadiness.READY, estimate.readiness)
        assertTrue(estimate.launchAllowed)
        assertEquals(4_096, estimate.recommendedContextTokens)
        assertEquals(6, estimate.recommendedThreads)
        assertTrue(estimate.kvCacheBytes > 0L)
        assertTrue(estimate.totalRequiredBytes < estimate.safeMemoryBudgetBytes)
    }

    @Test
    fun oversizedContextIsReducedBeforeBlockingModel() {
        val estimate = estimate(contextTokens = 32_768)

        assertEquals(LocalModelRuntimeReadiness.CAUTION, estimate.readiness)
        assertTrue(LocalModelRuntimeIssue.CONTEXT_REDUCED in estimate.issues)
        assertTrue(estimate.recommendedContextTokens < estimate.requestedContextTokens)
        assertTrue(estimate.totalRequiredBytes <= estimate.safeMemoryBudgetBytes)
    }

    @Test
    fun minimumContextStillOverBudgetBlocksLaunch() {
        val estimate = estimate(
            profile = LocalModelRuntimeProfiles.QWEN_3_8B_Q4_K_M,
            device = device(totalGib = 4, availableGib = 1)
        )

        assertEquals(LocalModelRuntimeReadiness.BLOCKED, estimate.readiness)
        assertTrue(LocalModelRuntimeIssue.INSUFFICIENT_MEMORY in estimate.issues)
        assertFalse(estimate.launchAllowed)
    }

    @Test
    fun activeAndroidLowMemorySignalBlocksLaunch() {
        val estimate = estimate(device = device(systemLowMemory = true))

        assertEquals(LocalModelRuntimeReadiness.BLOCKED, estimate.readiness)
        assertTrue(LocalModelRuntimeIssue.SYSTEM_LOW_MEMORY in estimate.issues)
    }

    @Test
    fun thermalPressureReducesThreadsAndSevereHeatBlocks() {
        val moderate = estimate(device = device(thermalStatus = 2))
        val severe = estimate(device = device(thermalStatus = 3))
        val hotBattery = estimate(device = device(batteryTemperatureCelsius = 45.0))

        assertEquals(LocalModelRuntimeReadiness.CAUTION, moderate.readiness)
        assertEquals(2, moderate.recommendedThreads)
        assertTrue(LocalModelRuntimeIssue.THERMAL_PRESSURE in moderate.issues)
        assertEquals(LocalModelRuntimeReadiness.BLOCKED, severe.readiness)
        assertEquals(LocalModelRuntimeReadiness.BLOCKED, hotBattery.readiness)
    }

    @Test
    fun batteryAndPowerSaverNeverBlockOrThrottleLocalModels() {
        val low = estimate(device = device(batteryPercent = 15, charging = false))
        val critical = estimate(device = device(batteryPercent = 5, charging = false))
        val charging = estimate(device = device(batteryPercent = 5, charging = true))
        val saver = estimate(device = device(powerSaveMode = true))

        assertEquals(LocalModelRuntimeReadiness.READY, low.readiness)
        assertEquals(6, low.recommendedThreads)
        assertFalse(LocalModelRuntimeIssue.LOW_BATTERY in low.issues)
        assertEquals(LocalModelRuntimeReadiness.READY, critical.readiness)
        assertFalse(LocalModelRuntimeIssue.CRITICAL_BATTERY in charging.issues)
        assertEquals(LocalModelRuntimeReadiness.READY, saver.readiness)
        assertEquals(6, saver.recommendedThreads)
    }

    @Test
    fun launchModeRequiresARealModelFile() {
        val estimate = LocalModelRuntimeEstimator.estimate(
            LocalModelRuntimeRequest(
                profile = LocalModelRuntimeProfiles.GEMMA_3_1B_Q4,
                modelFileBytes = 0L,
                modelFilePresent = false,
                requireModelFile = true
            ),
            device()
        )

        assertEquals(LocalModelRuntimeReadiness.BLOCKED, estimate.readiness)
        assertTrue(LocalModelRuntimeIssue.MODEL_FILE_MISSING in estimate.issues)
        assertTrue(LocalModelRuntimeIssue.MODEL_FILE_INVALID in estimate.issues)
    }

    @Test
    fun qnnProfilesRequireQualcommAcceleratorReady() {
        val estimate = LocalModelRuntimeEstimator.estimate(
            LocalModelRuntimeRequest(
                profile = LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN,
                acceleratorReady = false
            ),
            device()
        )

        assertEquals(LocalModelRuntimeReadiness.BLOCKED, estimate.readiness)
        assertTrue(LocalModelRuntimeIssue.ACCELERATOR_UNAVAILABLE in estimate.issues)
    }

    @Test
    fun qnnProfilesAreMarkedForVendorAcceleration() {
        assertEquals(
            LocalModelAcceleratorKind.VENDOR_SDK,
            LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.preferredAccelerator
        )
        assertEquals(
            LocalModelAcceleratorKind.VENDOR_SDK,
            LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN.preferredAccelerator
        )
        assertEquals("Q4_0", LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.quantizationLabel)
        assertEquals("Q4_0", LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN.quantizationLabel)
        assertTrue(LocalModelRuntimeProfiles.QWEN_3_1_7B_QNN.fileName.endsWith("Q4_0.gguf"))
        assertTrue(LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN.fileName.endsWith("Q4_0.gguf"))
    }

    @Test
    fun qairtProfileUsesQualcommManagedArtifactInsteadOfGgufDownload() {
        val profile = LocalModelRuntimeProfiles.QWEN_3_1_7B_QAIRT

        assertEquals(LocalModelArtifactFormat.QAIRT, profile.artifactFormat)
        assertEquals(LocalModelAcceleratorKind.VENDOR_SDK, profile.preferredAccelerator)
        assertEquals("SM8850", profile.targetChipset)
        assertEquals("W4A16", profile.quantizationLabel)
        assertTrue(profile.downloadable)
        assertTrue(profile.sourceUrls(preferChinaMirror = false).isEmpty())
    }

    @Test
    fun qnnMemoryEstimateWarnsButLetsRuntimeAttemptLaunch() {
        val estimate = estimate(
            profile = LocalModelRuntimeProfiles.GEMMA_4_E4B_QNN,
            device = device(totalGib = 12, availableGib = 5)
        )

        assertEquals(LocalModelRuntimeReadiness.CAUTION, estimate.readiness)
        assertTrue(LocalModelRuntimeIssue.INSUFFICIENT_MEMORY in estimate.issues)
        assertTrue(estimate.launchAllowed)
    }

    @Test(expected = IllegalStateException::class)
    fun launchGateRejectsBlockedAssessment() {
        LocalModelRuntimeEstimator.requireLaunchable(
            estimate(device = device(systemLowMemory = true))
        )
    }

    @Test
    fun kvCacheScalesWithContextLength() {
        val short = estimate(contextTokens = 2_048)
        val long = estimate(contextTokens = 4_096)

        assertEquals(short.kvCacheBytes * 2L, long.kvCacheBytes)
    }

    private fun estimate(
        profile: LocalModelRuntimeProfile = LocalModelRuntimeProfiles.GEMMA_3_4B_Q4,
        contextTokens: Int = 4_096,
        device: LocalModelDeviceSnapshot = device()
    ): LocalModelRuntimeEstimate = LocalModelRuntimeEstimator.estimate(
        LocalModelRuntimeRequest(
            profile = profile,
            requestedContextTokens = contextTokens
        ),
        device
    )

    private fun device(
        totalGib: Long = 12,
        availableGib: Long = 8,
        systemLowMemory: Boolean = false,
        cpuCoreCount: Int = 8,
        batteryPercent: Int? = 80,
        charging: Boolean = true,
        batteryTemperatureCelsius: Double? = 32.0,
        thermalStatus: Int? = 0,
        powerSaveMode: Boolean = false
    ) = LocalModelDeviceSnapshot(
        totalMemoryBytes = totalGib * GIB,
        availableMemoryBytes = availableGib * GIB,
        systemLowMemory = systemLowMemory,
        cpuCoreCount = cpuCoreCount,
        batteryPercent = batteryPercent,
        charging = charging,
        batteryTemperatureCelsius = batteryTemperatureCelsius,
        thermalStatus = thermalStatus,
        powerSaveMode = powerSaveMode
    )

    companion object {
        private const val GIB = 1024L * 1024L * 1024L
    }
}
