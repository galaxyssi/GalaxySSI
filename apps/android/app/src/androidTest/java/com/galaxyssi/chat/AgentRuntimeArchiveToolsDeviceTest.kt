package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRuntimeArchiveToolsDeviceTest {
    @Test
    fun linuxGuestProvidesWritablePersistentTaskTempDirectory() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertTrue("Runtime lifecycle: ${lifecycle.reason}", lifecycle.phase == AgentRuntimeLifecyclePhase.READY)
        val result = AgentOnDeviceRuntimeManager(context).execute(
            AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = """
                    set -eu
                    test "${'$'}TMPDIR" = /root/.cache/tmp
                    test -d "${'$'}TMPDIR"
                    probe="${'$'}TMPDIR/galaxyssi-write-probe-${'$'}${'$'}"
                    printf 'ready\n' > "${'$'}probe"
                    rm -f "${'$'}probe"
                    printf 'persistent-task-temp-ready\n'
                """.trimIndent(),
                arguments = emptyList(),
                timeoutMillis = 30_000L,
                networkEnabled = false,
                artifactPaths = emptyList(),
                workspaceId = "device-runtime-temp-check",
                requestId = "runtime-temp-check-${System.currentTimeMillis()}",
                resourceLimits = AgentRuntimeResourceLimits(
                    wallClockMillis = 30_000L,
                    cpuMillis = 15_000L,
                    memoryBytes = 64L * 1024L * 1024L,
                    diskBytes = 8L * 1024L * 1024L,
                    maxProcesses = 8,
                    maxOutputBytes = 8L * 1024L,
                    maxArtifactBytes = 1024L
                )
            )
        )

        assertEquals("stdout=${result.stdout}\nstderr=${result.stderr}", 0, result.exitCode)
        assertTrue(result.stdout, result.stdout.contains("persistent-task-temp-ready"))
    }

    @Test
    fun linuxGuestRemainsConnectedAcrossIdleReadPoll() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertTrue("Runtime lifecycle: ${lifecycle.reason}", lifecycle.phase == AgentRuntimeLifecyclePhase.READY)
        val result = AgentOnDeviceRuntimeManager(context).execute(
            AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = "sleep 35; printf 'long-task-ready\\n'",
                arguments = emptyList(),
                timeoutMillis = 50_000L,
                networkEnabled = false,
                artifactPaths = emptyList(),
                workspaceId = "device-long-task-check",
                requestId = "long-task-check-${System.currentTimeMillis()}",
                resourceLimits = AgentRuntimeResourceLimits(
                    wallClockMillis = 50_000L,
                    cpuMillis = 5_000L,
                    memoryBytes = 64L * 1024L * 1024L,
                    diskBytes = 8L * 1024L * 1024L,
                    maxProcesses = 8,
                    maxOutputBytes = 8L * 1024L,
                    maxArtifactBytes = 1024L
                )
            )
        )

        assertEquals("stdout=${result.stdout}\nstderr=${result.stderr}", 0, result.exitCode)
        assertTrue(result.stdout, result.stdout.contains("long-task-ready"))
    }

    @Test
    fun linuxGuestResolvesPublicNetworkThroughPhone() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertTrue("Runtime lifecycle: ${lifecycle.reason}", lifecycle.phase == AgentRuntimeLifecyclePhase.READY)
        val result = AgentOnDeviceRuntimeManager(context).execute(
            AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = """
                    set -eu
                    printf '%s\n' '--- resolv.conf ---'
                    cat /etc/resolv.conf
                    printf '%s\n' '--- interfaces ---'
                    cat /proc/net/dev
                    printf '%s\n' '--- routes ---'
                    cat /proc/net/route
                    awk -F: 'NR > 2 { name = ${'$'}1; gsub(/[[:space:]]/, "", name); if (name != "lo") found = 1 } END { exit !found }' /proc/net/dev
                    grep -Eq '^[^[:space:]]+[[:space:]]+00000000' /proc/net/route
                    printf '%s\n' '--- github ---'
                    getent ahostsv4 github.com
                """.trimIndent(),
                arguments = emptyList(),
                timeoutMillis = 30_000L,
                networkEnabled = true,
                allowedNetworkDomains = listOf("github.com"),
                artifactPaths = emptyList(),
                workspaceId = "device-network-diagnostic",
                requestId = "network-diagnostic-${System.currentTimeMillis()}",
                resourceLimits = AgentRuntimeResourceLimits(
                    wallClockMillis = 30_000L,
                    cpuMillis = 15_000L,
                    memoryBytes = 128L * 1024L * 1024L,
                    diskBytes = 16L * 1024L * 1024L,
                    maxProcesses = 16,
                    maxOutputBytes = 128L * 1024L,
                    maxArtifactBytes = 1024L
                )
            )
        )

        assertEquals("stdout=${result.stdout}\nstderr=${result.stderr}", 0, result.exitCode)
    }

    @Test
    fun linuxGuestCanCreateListExtractAndRunAProjectArchive() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertTrue("Runtime lifecycle: ${lifecycle.reason}", lifecycle.phase == AgentRuntimeLifecyclePhase.READY)
        val result = AgentOnDeviceRuntimeManager(context).execute(
            AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = """
                    set -eu
                    command -v zip
                    command -v unzip
                    mkdir -p archive-check/project
                    printf 'print(42)\n' > archive-check/project/main.py
                    (cd archive-check && zip -qr project.zip project)
                    mkdir -p archive-check/unpacked
                    unzip -q archive-check/project.zip -d archive-check/unpacked
                    test -f archive-check/unpacked/project/main.py
                    printf 'archive-tools-ready\n'
                """.trimIndent(),
                arguments = emptyList(),
                timeoutMillis = 60_000L,
                networkEnabled = false,
                artifactPaths = listOf("archive-check/project.zip"),
                workspaceId = "device-archive-tool-check",
                requestId = "archive-check-${System.currentTimeMillis()}",
                resourceLimits = AgentRuntimeResourceLimits(
                    wallClockMillis = 60_000L,
                    cpuMillis = 45_000L,
                    memoryBytes = 128L * 1024L * 1024L,
                    diskBytes = 32L * 1024L * 1024L,
                    maxProcesses = 16,
                    maxOutputBytes = 128L * 1024L,
                    maxArtifactBytes = 16L * 1024L * 1024L
                )
            )
        )

        assertEquals("stdout=${result.stdout}\nstderr=${result.stderr}", 0, result.exitCode)
        assertTrue(result.stdout, result.stdout.contains("archive-tools-ready"))
        assertTrue(result.artifacts.single()["host_path"].toString().endsWith("project.zip"))
    }
}
