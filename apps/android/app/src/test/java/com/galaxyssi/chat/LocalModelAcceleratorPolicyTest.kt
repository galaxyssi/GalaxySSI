package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalModelAcceleratorPolicyTest {
    @Test
    fun completeDeviceReportsAllBackendsReady() {
        val snapshot = LocalModelAcceleratorPolicy.evaluate(probe())

        assertTrue(snapshot.capabilities.all(LocalModelAcceleratorCapability::ready))
        assertEquals("Qualcomm QNN", snapshot[LocalModelAcceleratorKind.VENDOR_SDK].provider)
    }

    @Test
    fun gpuHardwareDoesNotPretendDelegateIsBundled() {
        val capability = LocalModelAcceleratorPolicy.evaluate(
            probe(gpuRuntimeAvailable = false)
        )[LocalModelAcceleratorKind.GPU]

        assertEquals(LocalModelAcceleratorState.HARDWARE_ONLY, capability.state)
        assertFalse(capability.ready)
        assertTrue(capability.hardwareEvidence.contains("Vulkan"))
    }

    @Test
    fun nnapiNeedsBothPlatformAndRuntimeProvider() {
        val runtimeMissing = LocalModelAcceleratorPolicy.evaluate(
            probe(nnapiProviderAvailable = false)
        )[LocalModelAcceleratorKind.NNAPI]
        val platformMissing = LocalModelAcceleratorPolicy.evaluate(
            probe(nnapiPlatformAvailable = false, nnapiProviderAvailable = true)
        )[LocalModelAcceleratorKind.NNAPI]

        assertEquals(LocalModelAcceleratorState.HARDWARE_ONLY, runtimeMissing.state)
        assertEquals(LocalModelAcceleratorState.UNAVAILABLE, platformMissing.state)
    }

    @Test
    fun vendorFamilyWithoutBundledAdapterIsHardwareOnly() {
        val capability = LocalModelAcceleratorPolicy.evaluate(
            probe(vendorSdkAvailable = false)
        )[LocalModelAcceleratorKind.VENDOR_SDK]

        assertEquals(LocalModelAcceleratorState.HARDWARE_ONLY, capability.state)
        assertTrue(capability.runtimeEvidence.contains("not bundled"))
    }

    @Test
    fun unknownVendorIsUnavailableRatherThanGuessed() {
        val capability = LocalModelAcceleratorPolicy.evaluate(
            probe(
                vendorFamily = "",
                vendorHardwareEvidence = "Unknown SoC",
                vendorSdkAvailable = false
            )
        )[LocalModelAcceleratorKind.VENDOR_SDK]

        assertEquals(LocalModelAcceleratorState.UNAVAILABLE, capability.state)
        assertEquals("Vendor accelerator", capability.provider)
    }

    @Test
    fun cpuHardwareWithoutRuntimeIsReportedHonestly() {
        val capability = LocalModelAcceleratorPolicy.evaluate(
            probe(cpuRuntimeAvailable = false)
        )[LocalModelAcceleratorKind.CPU]

        assertEquals(LocalModelAcceleratorState.HARDWARE_ONLY, capability.state)
    }

    @Test
    fun missingGpuHardwareCannotBecomeReadyFromRuntimeAlone() {
        val capability = LocalModelAcceleratorPolicy.evaluate(
            probe(gpuHardwareAvailable = false, gpuRuntimeAvailable = true)
        )[LocalModelAcceleratorKind.GPU]

        assertEquals(LocalModelAcceleratorState.UNAVAILABLE, capability.state)
    }

    private fun probe(
        cpuHardwareAvailable: Boolean = true,
        cpuRuntimeAvailable: Boolean = true,
        gpuHardwareAvailable: Boolean = true,
        gpuRuntimeAvailable: Boolean = true,
        nnapiPlatformAvailable: Boolean = true,
        nnapiProviderAvailable: Boolean = true,
        vendorFamily: String = "Qualcomm QNN",
        vendorHardwareEvidence: String = "Qualcomm SM8650",
        vendorSdkAvailable: Boolean = true
    ) = LocalModelAcceleratorProbe(
        cpuHardwareAvailable = cpuHardwareAvailable,
        cpuDescription = "8 cores / arm64-v8a",
        cpuRuntimeAvailable = cpuRuntimeAvailable,
        cpuRuntimeDescription = if (cpuRuntimeAvailable) "CPU backend bundled" else "CPU backend missing",
        gpuHardwareAvailable = gpuHardwareAvailable,
        gpuDescription = "Vulkan 1.3",
        gpuRuntimeAvailable = gpuRuntimeAvailable,
        gpuRuntimeDescription = if (gpuRuntimeAvailable) "GPU backend bundled" else "GPU backend not bundled",
        nnapiPlatformAvailable = nnapiPlatformAvailable,
        nnapiProviderAvailable = nnapiProviderAvailable,
        nnapiDescription = "Android NNAPI",
        vendorFamily = vendorFamily,
        vendorHardwareEvidence = vendorHardwareEvidence,
        vendorSdkAvailable = vendorSdkAvailable,
        vendorRuntimeEvidence = if (vendorSdkAvailable) "Vendor SDK bundled" else "Vendor SDK not bundled"
    )
}
