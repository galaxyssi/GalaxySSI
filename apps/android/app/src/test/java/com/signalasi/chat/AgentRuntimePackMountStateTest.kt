package com.signalasi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimePackMountStateTest {
    @Test
    fun stableExecutionEvaluatesMountStateOnce() {
        val gate = AgentRuntimePackActivationGate()
        val checks = AtomicInteger()

        gate.withExecution(
            needsRecycle = {
                checks.incrementAndGet()
                false
            },
            recycle = { error("Stable execution must not recycle the guest") }
        ) {}

        assertEquals(1, checks.get())
    }

    @Test
    fun idleRecycleUsesTheObservedMountStateWithoutCheckingTwice() {
        val gate = AgentRuntimePackActivationGate()
        val checks = AtomicInteger()
        val recycles = AtomicInteger()

        gate.withExecution(
            needsRecycle = {
                checks.incrementAndGet()
                true
            },
            recycle = { recycles.incrementAndGet() }
        ) {}

        assertEquals(1, checks.get())
        assertEquals(1, recycles.get())
    }

    @Test
    fun recyclesGuestWhenInstalledPackIsMissingFromLaunchConfiguration() {
        assertTrue(
            AgentRuntimePackMountState.requiresRecycle(
                statuses = listOf(
                    status("linux-base", "1.2.3"),
                    status("node-js", "24.18.0")
                ),
                runtimeConfigJson = config()
            )
        )
    }

    @Test
    fun keepsGuestWhenMountedPackVersionsMatchInstalledPacks() {
        assertFalse(
            AgentRuntimePackMountState.requiresRecycle(
                statuses = listOf(
                    status("linux-base", "1.2.3"),
                    status("node-js", "24.18.0"),
                    status("python-uv", "0.9.24")
                ),
                runtimeConfigJson = config(
                    "node-js" to "24.18.0",
                    "python-uv" to "0.9.24"
                )
            )
        )
    }

    @Test
    fun recyclesGuestWhenInstalledPackVersionChanges() {
        assertTrue(
            AgentRuntimePackMountState.requiresRecycle(
                statuses = listOf(status("node-js", "24.18.0")),
                runtimeConfigJson = config("node-js" to "22.0.0")
            )
        )
    }

    @Test
    fun ignoresUntrustedAndUnavailableHostPacks() {
        assertFalse(
            AgentRuntimePackMountState.requiresRecycle(
                statuses = listOf(
                    AgentRuntimePackStatus("node-js", AgentRuntimePackState.NOT_INSTALLED),
                    AgentRuntimePackStatus("python-uv", AgentRuntimePackState.READY, manifest = null)
                ),
                runtimeConfigJson = config()
            )
        )
    }

    @Test
    fun recycleWaitsForActiveExecutionAndRunsOnce() {
        val gate = AgentRuntimePackActivationGate()
        val firstStarted = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val secondFinished = CountDownLatch(1)
        val recycleCount = AtomicInteger()
        val stale = AtomicBoolean(false)

        val first = Thread {
            gate.withExecution(needsRecycle = { false }, recycle = {}) {
                firstStarted.countDown()
                releaseFirst.await(2, TimeUnit.SECONDS)
            }
        }
        val second = Thread {
            firstStarted.await(2, TimeUnit.SECONDS)
            stale.set(true)
            gate.withExecution(
                needsRecycle = stale::get,
                recycle = {
                    recycleCount.incrementAndGet()
                    stale.set(false)
                }
            ) {}
            secondFinished.countDown()
        }

        first.start()
        second.start()
        assertFalse(secondFinished.await(100, TimeUnit.MILLISECONDS))
        releaseFirst.countDown()
        assertTrue(secondFinished.await(2, TimeUnit.SECONDS))
        first.join(2_000)
        second.join(2_000)
        assertTrue(recycleCount.get() == 1)
    }

    private fun status(id: String, version: String) = AgentRuntimePackStatus(
        id = id,
        state = AgentRuntimePackState.READY,
        manifest = AgentRuntimePackManifest(
            id = id,
            version = version,
            architecture = "arm64-v8a",
            imageFile = "$id.img",
            imageSha256 = "a".repeat(64),
            capabilities = listOf("$id.execute"),
            dependencies = if (id == "linux-base") emptyList() else listOf("linux-base"),
            installedSizeBytes = 1L,
            license = "test",
            signatureKeyId = "b".repeat(64),
            signature = "signature"
        )
    )

    private fun config(vararg packs: Pair<String, String>): String =
        org.json.JSONObject()
            .put("packs", org.json.JSONArray().apply {
                packs.forEach { (id, version) ->
                    put(org.json.JSONObject().put("id", id).put("version", version))
                }
            })
            .toString()
}
