package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real-device coverage for the allowlisted network path inside the Android Linux guest. */
@RunWith(AndroidJUnit4::class)
class AgentOnDeviceRuntimeNetworkDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun pythonCanReachAnExplicitlyAllowedDomain() {
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(lifecycle.reason, AgentRuntimeLifecyclePhase.READY, lifecycle.phase)
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(
            context = context,
            screenProvider = {
                ScreenContext(
                    foregroundApp = context.packageName,
                    pageTitle = "GalaxySSI runtime network device test"
                )
            }
        )
        val descriptor = requireNotNull(registry.lookup(AgentOnDeviceRuntimeTools.EXECUTE)).descriptor
        val workspaceId = "runtime-network-${System.currentTimeMillis()}"
        val result = registry.invoke(
            AgentOnDeviceRuntimeTools.EXECUTE,
            mapOf(
                "language" to AgentRuntimeLanguage.PYTHON.wireValue,
                "source" to """
                    import urllib.request

                    with urllib.request.urlopen("http://example.com/", timeout=15) as response:
                        body = response.read(4096).decode("utf-8", errors="replace")
                        print(f"status={response.status}")
                        print(f"example_domain={'Example Domain' in body}")
                """.trimIndent(),
                "arguments" to emptyList<String>(),
                "timeout_ms" to 60_000L,
                "network_enabled" to true,
                "allowed_network_domains" to listOf("example.com"),
                "artifact_paths" to emptyList<String>()
            ),
            AgentNativeToolInvocationContext(
                invocationId = "device-network-${UUID.randomUUID()}",
                sessionId = workspaceId,
                conversationId = workspaceId,
                turnId = "turn-${UUID.randomUUID()}",
                idempotencyKey = "device-network-${UUID.randomUUID()}",
                grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
                attributes = mapOf("workspace_id" to workspaceId)
            )
        )

        assertTrue("status=${result.status} error=${result.error} output=${result.output}", result.isSuccess)
        val stdout = result.output["stdout"].toString()
        assertTrue(stdout, stdout.contains("status=200"))
        assertTrue(stdout, stdout.contains("example_domain=True"))
    }
}
