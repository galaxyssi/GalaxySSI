package com.galaxyssi.chat

import android.os.Bundle
import android.os.Debug
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in real process probe. No network/model calls; routing may update its local telemetry. */
@RunWith(AndroidJUnit4::class)
class AgentRoutingProbeLatencyDeviceTest {
    @Test fun measureRoutingStateSources() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("routing_probe") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val connectors = AppStoreAgentConnectorRegistry(context).planningSnapshot()
        val probes: List<Pair<String, () -> Any>> = listOf(
            "budget" to { AgentTaskBudgetStore(context).load() },
            "usage" to { GlobalModelCallBudgetStore(context).resourceUsageSnapshots() },
            "self_model" to { AgentSelfModelStore(context).snapshot() },
            "quality" to { AgentEvalOpsStore(context).samples() },
            "shadow_history" to { AgentShadowRoutingStore(context).recent() },
            "connectors" to { AppStoreAgentConnectorRegistry(context).planningSnapshot() },
            "actual_route" to { AgentResourceRouter(context).route("Write and read a local test file", connectors.targets, connectors.registrations) },
            "empty_route" to { AgentResourceRouter(context).route("Write and read a local test file", emptyList(), emptyList()) }
        )
        repeat(3) { iteration ->
            probes.forEach { (phase, probe) ->
                val start = SystemClock.elapsedRealtimeNanos()
                probe()
                val duration = SystemClock.elapsedRealtimeNanos() - start
                instrumentation.sendStatus(0, Bundle().apply {
                    putString("stream", "\nROUTING_SOURCE iteration=$iteration phase=$phase duration_ns=$duration\n")
                })
            }
        }
    }

    @Test fun measureMemoryAndEnvironmentProbes() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("routing_probe") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        repeat(6) { iteration ->
            var start = SystemClock.elapsedRealtimeNanos()
            val pssKiB = Debug.getPss()
            val pssNs = SystemClock.elapsedRealtimeNanos() - start
            start = SystemClock.elapsedRealtimeNanos()
            val environment = AgentTaskBudgetProbe.environment(context)
            val environmentNs = SystemClock.elapsedRealtimeNanos() - start
            assertTrue(pssKiB >= 0)
            assertTrue(environment.appMemoryBytes >= 0)
            instrumentation.sendStatus(0, Bundle().apply {
                putString("stream", "\nROUTING_PROBE iteration=$iteration pss_ns=$pssNs environment_ns=$environmentNs\n")
            })
        }
    }
}
