package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentRuntimePackInstallFastPathTest {
    @Test
    fun returnsInstalledPackWithoutRefreshingTheRemoteCatalog() {
        val output = AgentOnDeviceRuntimeTools.readyRuntimePackInstallOutput(
            "python-uv",
            listOf(status("python-uv", AgentRuntimePackState.READY, manifest("1.0.0")))
        )

        assertEquals("python-uv", output?.get("requested_pack"))
        val installed = output?.get("installed") as List<*>
        assertEquals(
            mapOf("pack_id" to "python-uv", "version" to "1.0.0", "state" to "already_ready"),
            installed.single()
        )
    }

    @Test
    fun requiresCatalogResolutionWhenPackIsMissingOrNotTrusted() {
        assertNull(
            AgentOnDeviceRuntimeTools.readyRuntimePackInstallOutput(
                "python-uv",
                listOf(status("python-uv", AgentRuntimePackState.NOT_INSTALLED, null))
            )
        )
        assertNull(
            AgentOnDeviceRuntimeTools.readyRuntimePackInstallOutput(
                "python-uv",
                listOf(status("python-uv", AgentRuntimePackState.READY, null))
            )
        )
    }

    private fun status(
        id: String,
        state: AgentRuntimePackState,
        manifest: AgentRuntimePackManifest?
    ) = AgentRuntimePackStatus(id = id, state = state, manifest = manifest)

    private fun manifest(version: String) = AgentRuntimePackManifest(
        id = "python-uv",
        version = version,
        architecture = "arm64-v8a",
        imageFile = "python-uv.img",
        imageSha256 = "a".repeat(64),
        capabilities = listOf("python.execute", "uv.sync"),
        dependencies = listOf("linux-base"),
        installedSizeBytes = 1L,
        license = "PSF-2.0",
        signatureKeyId = "b".repeat(64),
        signature = "signature"
    )
}
