package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in proof that the bundled portable CPython runs inside the persistent phone Linux system. */
@RunWith(AndroidJUnit4::class)
class AgentPortablePythonDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var project: File

    @Before
    fun setUp() {
        assumeTrue(InstrumentationRegistry.getArguments().getString(LIVE_PYTHON_ARGUMENT) == "true")
        project = File(context.filesDir, "agent-native-workspaces/$WORKSPACE_ID").apply {
            check(mkdirs() || isDirectory)
        }
        assumeTrue(File(project, ARCHIVE_NAME).isFile)
    }

    @After
    fun tearDown() {
        if (::project.isInitialized) project.deleteRecursively()
    }

    @Test
    fun portablePythonRunsInsidePersistentDebian() {
        val runtime = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(runtime.reason, AgentRuntimeLifecyclePhase.READY, runtime.phase)
        val result = AgentOnDeviceRuntimeManager(context).execute(
            AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = """
                    set -eu
                    target=/root/galaxyssi-portable-python-test
                    trap 'rm -rf "${'$'}target"' EXIT
                    mkdir -p "${'$'}target"
                    tar -xzf $ARCHIVE_NAME -C "${'$'}target"
                    "${'$'}target/python/bin/python3" -c 'import json, sqlite3; print(json.dumps({"python": "ready", "sqlite": sqlite3.sqlite_version}))'
                    "${'$'}target/python/bin/python3" -m pip --version
                """.trimIndent(),
                arguments = emptyList(),
                timeoutMillis = 120_000L,
                networkEnabled = false,
                artifactPaths = emptyList(),
                workspaceId = WORKSPACE_ID,
                requestId = "portable-python-${System.currentTimeMillis()}",
                resourceLimits = AgentRuntimeResourceLimits(
                    wallClockMillis = 120_000L,
                    cpuMillis = 90_000L,
                    memoryBytes = 512L * 1024L * 1024L,
                    diskBytes = 512L * 1024L * 1024L,
                    maxProcesses = 32,
                    maxOutputBytes = 128L * 1024L,
                    maxArtifactBytes = 1024L
                )
            )
        )

        assertEquals("stdout=${result.stdout}\nstderr=${result.stderr}", 0, result.exitCode)
        assertTrue(result.stdout, result.stdout.contains("\"python\": \"ready\""))
        assertTrue(result.stdout, result.stdout.contains("pip 26.2.1"))
    }

    @Test
    fun portablePythonRunsInjectedArchiveToolsInsideMountedWorkspace() {
        val runtime = AgentOnDeviceRuntimeLifecycle.ensureRunning(context)
        assertEquals(runtime.reason, AgentRuntimeLifecyclePhase.READY, runtime.phase)
        val result = AgentOnDeviceRuntimeManager(context).execute(
            AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = """
                    set -eu
                    target=/root/galaxyssi-portable-python-archive-test
                    trap 'rm -rf "${'$'}target"' EXIT
                    mkdir -p "${'$'}target"
                    tar -xzf $ARCHIVE_NAME -C "${'$'}target"
                    export PATH="${'$'}target/python/bin:${'$'}PATH"
                    command -v zip
                    command -v unzip
                    mkdir -p archive-check/project
                    printf 'print(42)\n' > archive-check/project/main.py
                    (cd archive-check && zip -qr project.zip project)
                    mkdir -p archive-check/unpacked
                    unzip -q archive-check/project.zip -d archive-check/unpacked
                    test -f archive-check/unpacked/project/main.py
                    printf 'portable-archive-tools-ready\n'
                """.trimIndent(),
                arguments = emptyList(),
                timeoutMillis = 180_000L,
                networkEnabled = false,
                artifactPaths = listOf("archive-check/project.zip"),
                workspaceId = WORKSPACE_ID,
                requestId = "portable-archive-tools-${System.currentTimeMillis()}",
                resourceLimits = AgentRuntimeResourceLimits(
                    wallClockMillis = 180_000L,
                    cpuMillis = 150_000L,
                    memoryBytes = 512L * 1024L * 1024L,
                    diskBytes = 512L * 1024L * 1024L,
                    maxProcesses = 32,
                    maxOutputBytes = 128L * 1024L,
                    maxArtifactBytes = 16L * 1024L * 1024L
                )
            )
        )

        assertEquals("stdout=${result.stdout}\nstderr=${result.stderr}", 0, result.exitCode)
        assertTrue(result.stdout, result.stdout.contains("portable-archive-tools-ready"))
        assertTrue(result.artifacts.single()["host_path"].toString().endsWith("project.zip"))
    }

    private companion object {
        const val LIVE_PYTHON_ARGUMENT = "galaxyssi.livePortablePython"
        const val WORKSPACE_ID = "portable-python-device-test"
        const val ARCHIVE_NAME =
            "cpython-3.13.15+20260814-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz"
    }
}
