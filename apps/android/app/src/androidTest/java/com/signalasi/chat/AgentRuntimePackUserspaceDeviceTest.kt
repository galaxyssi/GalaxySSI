package com.signalasi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Verifies that mounted language packs execute inside the persistent Linux userspace. */
@RunWith(AndroidJUnit4::class)
class AgentRuntimePackUserspaceDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun installedNodePackExecutesJavaScriptWithoutShellFallback() {
        val manager = AgentOnDeviceRuntimeManager(context)
        assumeTrue(manager.status().packs.any {
            it.id == AgentRuntimeLanguage.JAVASCRIPT.requiredPack &&
                it.state == AgentRuntimePackState.READY
        })
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(lifecycle.reason, AgentRuntimeLifecyclePhase.READY, lifecycle.phase)

        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(
            context = context,
            screenProvider = {
                ScreenContext(
                    foregroundApp = context.packageName,
                    pageTitle = "SignalASI runtime pack userspace device test"
                )
            }
        )
        val descriptor = requireNotNull(registry.lookup(AgentOnDeviceRuntimeTools.EXECUTE)).descriptor
        val workspaceId = "runtime-node-${System.currentTimeMillis()}"
        val result = registry.invoke(
            AgentOnDeviceRuntimeTools.EXECUTE,
            mapOf(
                "language" to AgentRuntimeLanguage.JAVASCRIPT.wireValue,
                "source" to "console.log(process.version)",
                "arguments" to emptyList<String>(),
                "timeout_ms" to 60_000L,
                "network_enabled" to false,
                "allowed_network_domains" to emptyList<String>(),
                "artifact_paths" to emptyList<String>()
            ),
            AgentNativeToolInvocationContext(
                invocationId = "device-node-${UUID.randomUUID()}",
                sessionId = workspaceId,
                conversationId = workspaceId,
                turnId = "turn-${UUID.randomUUID()}",
                idempotencyKey = "device-node-${UUID.randomUUID()}",
                grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
                attributes = mapOf("workspace_id" to workspaceId)
            )
        )

        assertTrue("status=${result.status} error=${result.error} output=${result.output}", result.isSuccess)
        assertTrue(result.output["stdout"].toString().trim().matches(Regex("v\\d+\\.\\d+\\.\\d+")))
    }
}
