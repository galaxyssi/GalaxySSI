package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentBrowserRuntimeReadinessTest {
    private fun status(packs: List<AgentRuntimePackStatus>) = AgentOnDeviceRuntimeStatus(
        AgentOnDeviceRuntimeBackend.QEMU_TCG, false, "Starts on demand", "arm64-v8a", "qemu", false, packs)
    private fun pack(id: String, capability: String) = AgentRuntimePackStatus(id, AgentRuntimePackState.READY,
        manifest = AgentRuntimePackManifest(id, "1.0", "arm64-v8a", "$id.img", "a".repeat(64),
            listOf(capability), emptyList(), 1, "MIT", "key", "signature"))
    private val packs = listOf(pack("linux-base", "shell.execute"), pack("node-js", "javascript.execute"),
        pack("browser-automation", "browser.automation.execute"))

    @Test fun backendAloneDoesNotAdvertiseBrowserAvailability() {
        val result = AgentBrowserRuntimeReadiness.availability(status(packs.take(1)))
        assertEquals(AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, result.status)
        assertTrue(result.reason.contains("node-js"))
        assertTrue(result.reason.contains("browser-automation"))
        assertTrue(result.reason.contains(AgentOnDeviceRuntimeTools.INSTALL_PACK))
    }

    @Test fun eachDependencyAndCapabilityIsChecked() {
        packs.indices.forEach { index ->
            for (state in listOf(AgentRuntimePackState.INVALID, AgentRuntimePackState.INCOMPATIBLE, AgentRuntimePackState.NOT_INSTALLED)) {
                val changed = packs.toMutableList().apply { this[index] = this[index].copy(state = state) }
                assertEquals(AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, AgentBrowserRuntimeReadiness.availability(status(changed)).status)
            }
            val changed = packs.toMutableList().apply { this[index] = this[index].copy(manifest = this[index].manifest!!.copy(capabilities = emptyList())) }
            assertEquals(AgentNativeToolAvailabilityStatus.REQUIRES_SETUP, AgentBrowserRuntimeReadiness.availability(status(changed)).status)
        }
    }

    @Test fun installedDependenciesPermitOnDemandStartWithoutClaimingAlreadyLaunched() {
        val result = AgentBrowserRuntimeReadiness.availability(status(packs))
        assertEquals(AgentNativeToolAvailabilityStatus.AVAILABLE, result.status)
        assertTrue(result.reason.contains("verify Chromium startup"))
        assertEquals(AgentNativeToolAvailabilityStatus.REQUIRES_SETUP,
            AgentBrowserRuntimeReadiness.availability(status(packs).copy(backend = AgentOnDeviceRuntimeBackend.NONE)).status)
    }

    @Test fun preflightClassifiesMissingPathAndFailedNodeSeparately() {
        val script = AgentBrowserRuntimeReadiness.shellPrelude()
        listOf("node_missing", "node_path_missing", "node_start_failed", "browser_launcher_missing", "browser_launcher_path_missing")
            .forEach { assertTrue(script.contains(it)) }
        assertTrue(script.contains("node --version"))
        assertFalse(script.contains("exit 127"))
    }

    @Test fun preflightEmitsValidJsonBeforeDispatch() {
        val shell = java.io.File(if (System.getProperty("os.name").orEmpty().startsWith("Windows"))
            "C:/Program Files/Git/bin/bash.exe" else "/bin/sh")
        org.junit.Assume.assumeTrue(shell.isFile)
        for ((setup, expected) in listOf("" to "node_missing",
            "command() { return 0; }; node() { return 127; };\n" to "node_start_failed")) {
            // stdin avoids Windows process argument quoting and preserves the exact guest script.
            val process = ProcessBuilder(shell.path).start()
            process.outputStream.bufferedWriter().use {
                it.write("PATH=; export PATH\n" + setup + AgentBrowserRuntimeReadiness.shellPrelude() +
                    "printf 'must-not-dispatch'")
            }
            assertTrue(process.waitFor(5, java.util.concurrent.TimeUnit.SECONDS))
            assertEquals(process.errorStream.bufferedReader().readText(), 0, process.exitValue())
            val output = process.inputStream.bufferedReader().readText()
            val error = org.json.JSONObject(output).getJSONObject("error")
            assertEquals(expected, error.getString("code"))
            assertFalse(error.getJSONObject("details").getBoolean("executed"))
            assertFalse(output.contains("must-not-dispatch"))
        }
    }

    @Test fun installedDoesNotMeanReadyUntilTheLaunchProbeSucceeds() {
        for (success in listOf(false, true)) {
            var calls = 0
            val definition = AgentInteractiveBrowserTools.definitions({ error("unused") }).first().let { base ->
                AgentNativeToolDefinition(descriptor = base.descriptor, executor = AgentNativeToolExecutor { invocation ->
                    AgentBrowserRuntimeReadiness.verifyInstalled(invocation, mapOf("installed" to listOf("browser-automation")), {
                        calls++
                        assertFalse(it.networkEnabled)
                        assertTrue(it.secretEnvironment.isEmpty())
                        assertTrue(it.source.contains("browser-runtime-readiness.cjs"))
                        AgentRuntimeExecutionResponse(if (success) 0 else 127,
                            if (success) """{"ok":true,"result":{"browser_ready":true}}""" else "", "private diagnostic", 1)
                    }, emptyList())
                })
            }
            val result = AgentNativeToolRegistry().registerAll(listOf(definition)).invoke(definition.descriptor.id,
                mapOf("operation" to "readiness"), AgentNativeToolInvocationContext(conversationId = "fixture"))
            assertEquals(success, result.isSuccess)
            assertEquals(1, calls)
            if (!success) {
                assertEquals("browser_readiness_unobserved", result.error?.code)
                assertEquals(true, result.error?.details?.get("packs_installed"))
            } else assertEquals(true, result.output["browser_ready"])
            assertFalse(result.toJson().contains("private diagnostic"))
        }
    }
}
