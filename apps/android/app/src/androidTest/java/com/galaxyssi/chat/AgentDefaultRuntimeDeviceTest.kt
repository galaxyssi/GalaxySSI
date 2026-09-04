package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real-device proof that every executable in the embedded default runtime can start. */
@RunWith(AndroidJUnit4::class)
class AgentDefaultRuntimeDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun startsBundledPythonAndUvInsidePhoneLinux() {
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(lifecycle.reason, AgentRuntimeLifecyclePhase.READY, lifecycle.phase)
        val workspaceId = "default-runtime-${UUID.randomUUID()}"
        val result = AgentOnDeviceRuntimeManager(context).execute(
            AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = """
                    set -eu
                    pack=/opt/galaxyssi/packs/python-uv
                    test -x "${'$'}pack/bin/python3"
                    test -x "${'$'}pack/python/bin/python3"
                    "${'$'}pack/bin/python3" -c 'import sqlite3; print("python-ready", sqlite3.sqlite_version)'
                    "${'$'}pack/bin/uv" --version
                """.trimIndent(),
                arguments = emptyList(),
                timeoutMillis = 120_000L,
                networkEnabled = false,
                artifactPaths = emptyList(),
                workspaceId = workspaceId,
                requestId = "default-runtime-${UUID.randomUUID()}",
                resourceLimits = AgentRuntimeResourceLimits(
                    wallClockMillis = 120_000L,
                    cpuMillis = 90_000L,
                    memoryBytes = 512L * 1024L * 1024L,
                    diskBytes = 32L * 1024L * 1024L,
                    maxProcesses = 32,
                    maxOutputBytes = 128L * 1024L,
                    maxArtifactBytes = 1024L
                )
            )
        )

        assertEquals("stdout=${result.stdout}\nstderr=${result.stderr}", 0, result.exitCode)
        assertTrue(result.stdout, result.stdout.contains("python-ready"))
        assertTrue(result.stdout, result.stdout.contains("uv 0.11.29"))
    }
}
