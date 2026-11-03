package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Infrastructure isolation only; this does not stand in for a model-owned browser task. */
@RunWith(AndroidJUnit4::class)
class AgentRuntimeTimeoutRecoveryDeviceTest {
    @Test fun freshDiagnosisAndStartReuseTheRunningGuest() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("runtime_timeout_probe") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = AgentOnDeviceRuntimeManager(context)
        val request = AgentRuntimeExecutionRequest(
            language = AgentRuntimeLanguage.SHELL, source = "cat /proc/sys/kernel/random/boot_id",
            arguments = emptyList(), timeoutMillis = 60_000, networkEnabled = false,
            artifactPaths = emptyList(), workspaceId = "public-diagnose-${UUID.randomUUID()}",
            workspaceMutationExpected = false, discoverBuildArtifacts = false)
        val before = manager.execute(request)
        assertEquals(before.stderr, 0, before.exitCode)
        assertTrue(before.runtimeInstanceId.isNotBlank())
        assertEquals(AgentRuntimeEngineControllerRegistry.current()?.instanceId, before.runtimeInstanceId)
        val bridge = requireNotNull(AgentOnDeviceRuntimeBridgeRegistry.current())
        val registry = AgentNativeToolRegistry().registerAll(AgentRuntimeControlTools.definitions(context))
        val diagnosis = registry.invoke(AgentRuntimeControlTools.DIAGNOSE, emptyMap())
        assertTrue(diagnosis.toJson(), diagnosis.isSuccess)
        val health = diagnosis.output["health_observation"] as Map<*, *>
        assertEquals(true, health["confirmed"])
        assertEquals(true, health["ready"])
        assertSame(bridge, AgentOnDeviceRuntimeBridgeRegistry.current())
        val instance = diagnosis.output["runtime_instance"] as String
        val start = registry.invoke(AgentRuntimeControlTools.CONTROL,
            mapOf("operation" to "start", "expected_instance" to instance))
        assertTrue(start.toJson(), start.isSuccess)
        assertEquals(instance, start.output["runtime_instance"])
        assertEquals(false, start.output["live_state_may_be_lost"])
        val stale = registry.invoke(AgentRuntimeControlTools.CONTROL,
            mapOf("operation" to "restart", "expected_instance" to "f".repeat(64)))
        assertEquals("runtime_instance_changed", stale.error?.code)
        val after = manager.execute(request.copy(requestId = UUID.randomUUID().toString()))
        assertEquals(after.stderr, 0, after.exitCode)
        assertEquals(before.stdout.trim(), after.stdout.trim())
        assertEquals(before.runtimeInstanceId, after.runtimeInstanceId)
        assertSame(bridge, AgentOnDeviceRuntimeBridgeRegistry.current())
        println("PUBLIC_RUNTIME_DIAGNOSE_PROBE fresh_health=true start_reused_guest=true stale_restart_rejected=true")
    }

    @Test fun unobservedInspectionDoesNotReplaceTheRunningGuest() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("runtime_timeout_probe") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = AgentOnDeviceRuntimeManager(context)
        val request = AgentRuntimeExecutionRequest(
            language = AgentRuntimeLanguage.SHELL, source = "cat /proc/sys/kernel/random/boot_id",
            arguments = emptyList(), timeoutMillis = 60_000, networkEnabled = false,
            artifactPaths = emptyList(), workspaceId = "public-probe-${UUID.randomUUID()}",
            workspaceMutationExpected = false, discoverBuildArtifacts = false)
        val before = manager.execute(request)
        assertEquals(before.stderr, 0, before.exitCode)
        val bridge = requireNotNull(AgentOnDeviceRuntimeBridgeRegistry.current())
        val uncertain = AgentOnDeviceRuntimeLifecycle.inspectAfterBridgeProbe(context,
            AgentRuntimeBridgeHealth(false, observationConfirmed = false))
        assertEquals(AgentRuntimeLifecyclePhase.DEGRADED, uncertain.phase)
        assertTrue(uncertain.reason.contains("unconfirmed"))
        assertSame(bridge, AgentOnDeviceRuntimeBridgeRegistry.current())
        val after = manager.execute(request.copy(requestId = UUID.randomUUID().toString()))
        assertEquals(after.stderr, 0, after.exitCode)
        assertEquals(before.stdout.trim(), after.stdout.trim())
        assertSame(bridge, AgentOnDeviceRuntimeBridgeRegistry.current())
        println("PUBLIC_RUNTIME_UNCONFIRMED_PROBE same_guest=true running_guest_reused=true")
    }

    @Test fun timedOutSleepLeavesTheSameGuestAvailableToAnIndependentRequest() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("runtime_timeout_probe") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val manager = AgentOnDeviceRuntimeManager(context)
        val prefix = "public-timeout-${UUID.randomUUID()}"
        val bootSource = "cat /proc/sys/kernel/random/boot_id"
        fun request(suffix: String, source: String, timeout: Long) = AgentRuntimeExecutionRequest(
            language = AgentRuntimeLanguage.SHELL, source = source, arguments = emptyList(), timeoutMillis = timeout,
            networkEnabled = false, artifactPaths = emptyList(), workspaceId = "$prefix-$suffix",
            workspaceMutationExpected = false, discoverBuildArtifacts = false,
            resourceLimits = AgentRuntimeResourceLimits(wallClockMillis = 60_000, cpuMillis = 5_000))

        val before = manager.execute(request("warm", bootSource, 60_000))
        assertEquals(before.stderr, 0, before.exitCode)
        assertTrue(before.stdout.trim().matches(Regex("[a-f0-9-]{36}")))
        val bridge = requireNotNull(AgentOnDeviceRuntimeBridgeRegistry.current())
        val running = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val slow = executor.submit<Throwable?> {
                runCatching {
                    manager.execute(request("slow", "printf preserved > marker.txt; sleep 20", 5_000)
                        .copy(progressListener = { running.countDown() }))
                }.exceptionOrNull()
            }
            running.await(2, TimeUnit.SECONDS)
            val quick = executor.submit<AgentRuntimeExecutionResponse> { manager.execute(request("quick", bootSource, 30_000)) }
            val error = slow.get(35, TimeUnit.SECONDS)
            assertTrue("Expected a host observation timeout, got ${error?.javaClass?.simpleName}", error is AgentNativeToolTimeoutException)
            val details = (error as AgentNativeToolTimeoutException).details
            assertEquals(false, details["runtime_reset"])
            assertEquals(true, details["runtime_health_observed"])
            assertEquals(true, details["runtime_ready"])
            assertEquals(true, details["outcome_unknown"])
            val result = quick.get(35, TimeUnit.SECONDS)
            assertEquals(result.stderr, 0, result.exitCode)
            assertEquals(before.stdout.trim(), result.stdout.trim())
            assertSame(bridge, AgentOnDeviceRuntimeBridgeRegistry.current())
            assertTrue(bridge.refreshHealth().ready)
            val preserved = manager.execute(request("slow", "cat marker.txt", 30_000))
            assertEquals(preserved.stderr, 0, preserved.exitCode)
            assertEquals("preserved", preserved.stdout)
            println("PUBLIC_RUNTIME_TIMEOUT_PROBE same_guest=true runtime_reset=false parallel_request=passed cancellation_observed=${details["cancellation_observed"]}")
        } finally { executor.shutdownNow() }
    }
}
