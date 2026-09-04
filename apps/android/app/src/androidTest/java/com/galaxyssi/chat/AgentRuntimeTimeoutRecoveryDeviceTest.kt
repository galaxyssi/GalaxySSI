package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRuntimeTimeoutRecoveryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun timeoutQuarantinesGuestAndNextActionRecoversTheStableWorkspace() {
        val workspaceId = "timeout-recovery-${UUID.randomUUID()}"
        assertEquals(
            AgentRuntimeLifecyclePhase.READY,
            AgentOnDeviceRuntimeLifecycle.ensureRunning(context).phase
        )
        val manager = AgentOnDeviceRuntimeManager(context)
        val timedOut = runCatching {
            manager.execute(request(
                workspaceId = workspaceId,
                requestId = "timeout-${UUID.randomUUID()}",
                source = "printf preserved > marker.txt; sleep 10",
                timeoutMillis = 500L
            ))
        }
        assertTrue(timedOut.exceptionOrNull() is AgentNativeToolTimeoutException)

        val recovered = manager.execute(request(
            workspaceId = workspaceId,
            requestId = "recovered-${UUID.randomUUID()}",
            source = "test \"\$(cat marker.txt)\" = preserved; printf recovered",
            timeoutMillis = 120_000L
        ))

        assertEquals(recovered.stderr, 0, recovered.exitCode)
        assertEquals("recovered", recovered.stdout)
        assertEquals(AgentRuntimeWorkspaceDisposition.COMMITTED, recovered.workspaceDisposition)
    }

    private fun request(
        workspaceId: String,
        requestId: String,
        source: String,
        timeoutMillis: Long
    ) = AgentRuntimeExecutionRequest(
        language = AgentRuntimeLanguage.SHELL,
        source = source,
        arguments = emptyList(),
        timeoutMillis = timeoutMillis,
        networkEnabled = false,
        artifactPaths = emptyList(),
        workspaceId = workspaceId,
        requestId = requestId,
        resourceLimits = AgentRuntimeResourceLimits(
            wallClockMillis = timeoutMillis,
            cpuMillis = timeoutMillis,
            memoryBytes = 128L * 1024L * 1024L,
            diskBytes = 32L * 1024L * 1024L,
            maxProcesses = 8,
            maxOutputBytes = 64L * 1024L,
            maxArtifactBytes = 1024L
        )
    )
}
