package com.signalasi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in diagnostics for package repository connectivity inside phone Linux. */
@RunWith(AndroidJUnit4::class)
class AgentLinuxPackageRepositoryProbeDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test
    fun recordsRepositoryConnectivityWithoutMutatingPackages() {
        assumeTrue(InstrumentationRegistry.getArguments().getString(LIVE_PROBE_ARGUMENT) == "true")
        val lifecycle = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(lifecycle.reason, AgentRuntimeLifecyclePhase.READY, lifecycle.phase)
        val workspaceId = "package-repository-probe-${System.currentTimeMillis()}"
        val response = AgentOnDeviceRuntimeManager(context).execute(
            AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = """
                    set +e
                    echo '--- sources ---'
                    cat /etc/apt/sources.list 2>&1
                    find /etc/apt/sources.list.d -maxdepth 1 -type f -print -exec cat {} \; 2>&1
                    echo '--- dns ---'
                    getent ahostsv4 deb.debian.org 2>&1 | head -n 4
                    echo '--- curl-http ---'
                    curl -4 -I --connect-timeout 5 --max-time 15 http://deb.debian.org/debian/dists/bookworm/InRelease 2>&1 | head -n 16
                    echo '--- curl-https ---'
                    curl -4 -I --connect-timeout 5 --max-time 15 https://deb.debian.org/debian/dists/bookworm/InRelease 2>&1 | head -n 16
                    echo '--- apt-update ---'
                    timeout 45s apt-get \
                      -o Acquire::Retries=0 \
                      -o Acquire::ForceIPv4=true \
                      -o Acquire::http::Timeout=10 \
                      -o Acquire::https::Timeout=10 \
                      update 2>&1
                    echo "apt_exit=${'$'}?"
                """.trimIndent(),
                arguments = emptyList(),
                timeoutMillis = 90_000L,
                networkEnabled = true,
                artifactPaths = emptyList(),
                workspaceId = workspaceId,
                requestId = "package-repository-probe-${UUID.randomUUID()}",
                resourceLimits = AgentRuntimeResourceLimits(
                    wallClockMillis = 90_000L,
                    cpuMillis = 60_000L,
                    memoryBytes = 512L * 1024L * 1024L,
                    diskBytes = 16L * 1024L * 1024L,
                    maxProcesses = 32,
                    maxOutputBytes = 256L * 1024L,
                    maxArtifactBytes = 1024L
                )
            )
        )
        val report = File(
            requireNotNull(context.getExternalFilesDir("runtime-tests")),
            "package-repository-probe.txt"
        )
        report.parentFile?.mkdirs()
        report.writeText(
            buildString {
                appendLine("exit_code=${response.exitCode}")
                appendLine("duration_ms=${response.durationMillis}")
                appendLine("--- stdout ---")
                appendLine(response.stdout)
                appendLine("--- stderr ---")
                appendLine(response.stderr)
            }
        )
    }

    private companion object {
        const val LIVE_PROBE_ARGUMENT = "signalasi.livePackageRepositoryProbe"
    }
}
