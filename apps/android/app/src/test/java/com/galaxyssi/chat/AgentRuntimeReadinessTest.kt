package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class AgentRuntimeReadinessTest {
    @Test
    fun reportsGuestFailureInsteadOfClaimingThatAnInstalledPackIsMissing() {
        val status = status(
            backend = AgentOnDeviceRuntimeBackend.QEMU_TCG,
            backendReady = false,
            reason = "The guest bridge is not healthy",
            lifecycleReason = "Runtime task network firewall is unavailable"
        )

        assertFalse(status.languageReady(AgentRuntimeLanguage.SHELL))
        assertEquals(
            "Runtime task network firewall is unavailable",
            status.readinessFailure(AgentRuntimeLanguage.SHELL)
        )
    }

    @Test
    fun reportsPackAndEngineFailuresPrecisely() {
        val invalidPack = status(
            backend = AgentOnDeviceRuntimeBackend.NONE,
            backendReady = false,
            reason = "Install the linux-base runtime pack",
            packState = AgentRuntimePackState.INVALID,
            packReason = "Runtime pack signature is not trusted"
        )
        assertEquals(
            "linux-base is invalid: Runtime pack signature is not trusted",
            invalidPack.readinessFailure(AgentRuntimeLanguage.SHELL)
        )

        val missingEngine = status(
            backend = AgentOnDeviceRuntimeBackend.NONE,
            backendReady = false,
            reason = "Install the GalaxySSI QEMU engine"
        )
        assertEquals(
            "Install the GalaxySSI QEMU engine",
            missingEngine.readinessFailure(AgentRuntimeLanguage.SHELL)
        )
    }

    @Test
    fun acceptsAHealthyBackendWithTheRequiredCapability() {
        val status = status(
            backend = AgentOnDeviceRuntimeBackend.QEMU_TCG,
            backendReady = true,
            reason = "On-device Linux runtime is ready"
        )

        assertNull(status.readinessFailure(AgentRuntimeLanguage.SHELL))
    }

    private fun status(
        backend: AgentOnDeviceRuntimeBackend,
        backendReady: Boolean,
        reason: String,
        lifecycleReason: String = "",
        packState: AgentRuntimePackState = AgentRuntimePackState.READY,
        packReason: String = ""
    ) = AgentOnDeviceRuntimeStatus(
        backend = backend,
        backendReady = backendReady,
        reason = reason,
        architecture = "arm64-v8a",
        enginePath = "/data/app/libgalaxyssi_qemu.so",
        avfAdvertised = false,
        packs = listOf(
            AgentRuntimePackStatus(
                id = "linux-base",
                state = packState,
                reason = packReason,
                manifest = AgentRuntimePackManifest(
                    id = "linux-base",
                    version = "1.3.3",
                    architecture = "arm64-v8a",
                    imageFile = "linux-base.img",
                    imageSha256 = "a".repeat(64),
                    capabilities = listOf("shell.execute"),
                    dependencies = emptyList(),
                    installedSizeBytes = 1,
                    license = "GPL-2.0-only",
                    signatureKeyId = "b".repeat(64),
                    signature = "signature"
                )
            )
        ),
        lifecycleReason = lifecycleReason
    )
}
