package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentPersistentLinuxStatusTest {
    @Test
    fun `runtime status advertises apt only for a ready persistent userspace`() {
        val ready = AgentOnDeviceRuntimeTools.persistentLinuxSystemOutput(status("1.3.3", backendReady = true))
        val legacy = AgentOnDeviceRuntimeTools.persistentLinuxSystemOutput(status("1.3.2", backendReady = true))
        val disconnected = AgentOnDeviceRuntimeTools.persistentLinuxSystemOutput(status("1.3.3", backendReady = false))

        assertEquals("Debian 13", ready["distribution"])
        assertEquals("root", ready["execution_principal"])
        assertEquals(listOf("apt", "dpkg"), ready["package_managers"])
        assertEquals(true, ready["package_manager_ready"])
        assertEquals(false, legacy["package_manager_ready"])
        assertEquals(false, disconnected["package_manager_ready"])
    }

    private fun status(version: String, backendReady: Boolean): AgentOnDeviceRuntimeStatus {
        val manifest = AgentRuntimePackManifest(
            id = "linux-base",
            version = version,
            architecture = "arm64-v8a",
            imageFile = "linux-base.img",
            imageSha256 = "a".repeat(64),
            capabilities = listOf("shell.execute"),
            dependencies = emptyList(),
            installedSizeBytes = 1,
            license = "GPL-2.0-only",
            signatureKeyId = "test-key",
            signature = "signature"
        )
        return AgentOnDeviceRuntimeStatus(
            backend = if (backendReady) AgentOnDeviceRuntimeBackend.QEMU_TCG else AgentOnDeviceRuntimeBackend.NONE,
            backendReady = backendReady,
            reason = "test",
            architecture = "arm64-v8a",
            enginePath = "",
            avfAdvertised = false,
            packs = listOf(
                AgentRuntimePackStatus(
                    id = "linux-base",
                    state = AgentRuntimePackState.READY,
                    manifest = manifest
                )
            )
        )
    }
}
