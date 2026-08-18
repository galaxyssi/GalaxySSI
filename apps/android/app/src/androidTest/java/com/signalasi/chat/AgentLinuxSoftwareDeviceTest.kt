package com.signalasi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in proof that a fresh phone Linux guest can discover compatible packages. */
@RunWith(AndroidJUnit4::class)
class AgentLinuxSoftwareDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test
    fun refreshesPackageMetadataAndFindsInstallableSoftware() {
        assumeTrue(
            InstrumentationRegistry.getArguments().getString(LIVE_SOFTWARE_ARGUMENT) == "true"
        )
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(lifecycle.reason, AgentRuntimeLifecyclePhase.READY, lifecycle.phase)
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(
            context = context,
            screenProvider = {
                ScreenContext(
                    foregroundApp = context.packageName,
                    pageTitle = "Phone Linux software test"
                )
            }
        )
        val result = invoke(
            registry = registry,
            toolId = AgentLinuxSoftwareNativeTools.SEARCH,
            input = mapOf(
                "query" to "jq",
                "source" to AgentLinuxSoftwareNativeTools.SOURCE_LINUX_PACKAGE,
                "limit" to 10
            )
        )

        assertEquals(result.message, AgentNativeToolResultStatus.SUCCEEDED, result.status)
        val results = result.output["results"] as? Iterable<*> ?: emptyList<Any?>()
        val jq = results.mapNotNull { it as? Map<*, *> }
            .firstOrNull { it["software_id"] == "jq" }
        assertTrue("The Debian package catalog did not return jq: $results", jq != null)
        assertTrue(jq?.get("version").toString().isNotBlank())
        assertEquals(true, jq?.get("compatible"))
    }

    private fun invoke(
        registry: AgentNativeToolRegistry,
        toolId: String,
        input: AgentNativeJsonObject
    ): AgentNativeToolResult {
        val descriptor = requireNotNull(registry.lookup(toolId)).descriptor
        val id = UUID.randomUUID().toString()
        return registry.invoke(
            toolId,
            input,
            AgentNativeToolInvocationContext(
                invocationId = "software-$id",
                sessionId = "software-device-test",
                conversationId = "software-device-test",
                turnId = "turn-$id",
                idempotencyKey = "software-$id",
                grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
                attributes = mapOf("workspace_id" to "software-device-test")
            )
        )
    }

    private companion object {
        const val LIVE_SOFTWARE_ARGUMENT = "signalasi.liveLinuxSoftware"
    }
}
