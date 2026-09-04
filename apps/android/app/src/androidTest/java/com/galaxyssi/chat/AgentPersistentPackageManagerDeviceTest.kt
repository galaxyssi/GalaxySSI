package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real-device proof that Debian packages and root state survive a guest restart. */
@RunWith(AndroidJUnit4::class)
class AgentPersistentPackageManagerDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun aptPackageAndRootHomeSurviveGuestRestart() {
        assertReady(AgentOnDeviceRuntimeLifecycle.ensureRunning(context))
        val workspaceId = "runtime-apt-${System.currentTimeMillis()}"
        val report = linkedMapOf<String, Any?>()

        val install = executeShell(
            workspaceId = workspaceId,
            networkEnabled = true,
            allowedDomains = listOf("deb.debian.org", "security.debian.org"),
            source = """
                set -eu
                test "${'$'}(id -u)" = "0"
                grep -q '^ID=debian${'$'}' /etc/os-release
                command -v apt-get
                export DEBIAN_FRONTEND=noninteractive
                apt-get update
                apt-get install -y --no-install-recommends bc
                mkdir -p /root/.galaxyssi-runtime-tests
                printf 'persistent-package-manager\n' > /root/.galaxyssi-runtime-tests/apt-marker
                dpkg-query -W -f='${'$'}{Status}\n' bc
                bc --version | head -n 1
            """.trimIndent(),
            timeoutMillis = 600_000L
        )
        report["install"] = install.asReport()
        writeReport(report)
        assertSuccess(install)
        assertTrue(install.output["stdout"].toString().contains("install ok installed"))

        assertReady(AgentOnDeviceRuntimeLifecycle.restart(context))
        val persisted = executeShell(
            workspaceId = workspaceId,
            networkEnabled = false,
            allowedDomains = emptyList(),
            source = """
                set -eu
                test "${'$'}(id -u)" = "0"
                test "${'$'}(cat /root/.galaxyssi-runtime-tests/apt-marker)" = "persistent-package-manager"
                dpkg-query -W -f='${'$'}{Status}\n' bc
                printf 'bc_result=%s\n' "${'$'}(printf '6 * 7\n' | bc)"
            """.trimIndent(),
            timeoutMillis = 120_000L
        )
        report["after_restart"] = persisted.asReport()
        writeReport(report)
        assertSuccess(persisted)
        val persistedStdout = persisted.output["stdout"].toString()
        assertTrue(persistedStdout.contains("install ok installed"))
        assertTrue(persistedStdout.contains("bc_result=42"))

        val cleanup = executeShell(
            workspaceId = workspaceId,
            networkEnabled = false,
            allowedDomains = emptyList(),
            source = """
                set -eu
                export DEBIAN_FRONTEND=noninteractive
                apt-get remove -y bc
                apt-get clean
                rm -rf /root/.galaxyssi-runtime-tests
                ! dpkg-query -W bc >/dev/null 2>&1
            """.trimIndent(),
            timeoutMillis = 180_000L
        )
        report["cleanup"] = cleanup.asReport()
        writeReport(report)
        assertSuccess(cleanup)
    }

    private fun executeShell(
        workspaceId: String,
        source: String,
        networkEnabled: Boolean,
        allowedDomains: List<String>,
        timeoutMillis: Long
    ): AgentNativeToolResult {
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(
            context = context,
            screenProvider = {
                ScreenContext(
                    foregroundApp = context.packageName,
                    pageTitle = "GalaxySSI persistent package manager device test"
                )
            }
        )
        val descriptor = requireNotNull(registry.lookup(AgentOnDeviceRuntimeTools.EXECUTE)).descriptor
        return registry.invoke(
            AgentOnDeviceRuntimeTools.EXECUTE,
            mapOf(
                "language" to AgentRuntimeLanguage.SHELL.wireValue,
                "source" to source,
                "arguments" to emptyList<String>(),
                "timeout_ms" to timeoutMillis,
                "network_enabled" to networkEnabled,
                "allowed_network_domains" to allowedDomains,
                "artifact_paths" to emptyList<String>()
            ),
            AgentNativeToolInvocationContext(
                invocationId = "device-apt-${UUID.randomUUID()}",
                sessionId = workspaceId,
                conversationId = workspaceId,
                turnId = "turn-${UUID.randomUUID()}",
                idempotencyKey = "device-apt-${UUID.randomUUID()}",
                grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id },
                attributes = mapOf("workspace_id" to workspaceId)
            )
        )
    }

    private fun assertReady(snapshot: AgentRuntimeLifecycleSnapshot) {
        assertEquals(snapshot.reason, AgentRuntimeLifecyclePhase.READY, snapshot.phase)
    }

    private fun assertSuccess(result: AgentNativeToolResult) {
        assertTrue(
            "status=${result.status} message=${result.message} error=${result.error} output=${result.output}",
            result.isSuccess
        )
    }

    private fun writeReport(report: Map<String, Any?>) {
        val file = File(
            requireNotNull(context.getExternalFilesDir("runtime-tests")),
            "persistent-package-manager.json"
        )
        file.parentFile?.mkdirs()
        file.writeText(JSONObject(report).toString(2))
    }

    private fun AgentNativeToolResult.asReport(): Map<String, Any?> = linkedMapOf(
        "status" to status.wireValue,
        "message" to message,
        "duration_ms" to receipt.durationMillis,
        "error_code" to error?.code,
        "error_message" to error?.message,
        "output" to output
    )
}
