package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentNativeToolExecutionGateTest {
    @Test
    fun independentReadOnlyToolsExecuteConcurrently() {
        val entered = CountDownLatch(2)
        val release = CountDownLatch(1)
        val active = AtomicInteger()
        val maximum = AtomicInteger()
        val registry = AgentNativeToolRegistry()
            .register(tool("test.read.one", AgentNativeToolConcurrency.PARALLEL_READ_ONLY) {
                observeConcurrency(active, maximum, entered, release)
            })
            .register(tool("test.read.two", AgentNativeToolConcurrency.PARALLEL_READ_ONLY) {
                observeConcurrency(active, maximum, entered, release)
            })
        val pool = Executors.newFixedThreadPool(2)

        try {
            val first = pool.submit<AgentNativeToolResult> { registry.invoke("test.read.one", emptyMap()) }
            val second = pool.submit<AgentNativeToolResult> { registry.invoke("test.read.two", emptyMap()) }

            assertTrue(entered.await(2, TimeUnit.SECONDS))
            release.countDown()
            assertTrue(first.get(2, TimeUnit.SECONDS).isSuccess)
            assertTrue(second.get(2, TimeUnit.SECONDS).isSuccess)
            assertEquals(2, maximum.get())
        } finally {
            release.countDown()
            pool.shutdownNow()
        }
    }

    @Test
    fun serialToolsNeverOverlapAcrossConcurrentInvocations() {
        val active = AtomicInteger()
        val maximum = AtomicInteger()
        val registry = AgentNativeToolRegistry()
            .register(tool("test.write.one", AgentNativeToolConcurrency.SERIAL) {
                observeSerial(active, maximum)
            })
            .register(tool("test.write.two", AgentNativeToolConcurrency.SERIAL) {
                observeSerial(active, maximum)
            })
        val pool = Executors.newFixedThreadPool(2)

        try {
            val results = listOf(
                pool.submit<AgentNativeToolResult> { registry.invoke("test.write.one", emptyMap()) },
                pool.submit<AgentNativeToolResult> { registry.invoke("test.write.two", emptyMap()) }
            ).map { it.get(3, TimeUnit.SECONDS) }

            assertTrue(results.all(AgentNativeToolResult::isSuccess))
            assertEquals(1, maximum.get())
        } finally {
            pool.shutdownNow()
        }
    }

    @Test
    fun mutationWaitsForActiveObservationToFinish() {
        val readEntered = CountDownLatch(1)
        val releaseRead = CountDownLatch(1)
        val writeEntered = CountDownLatch(1)
        val registry = AgentNativeToolRegistry()
            .register(tool("test.read", AgentNativeToolConcurrency.PARALLEL_READ_ONLY) {
                readEntered.countDown()
                assertTrue(releaseRead.await(2, TimeUnit.SECONDS))
                AgentNativeToolExecutionResult.success()
            })
            .register(tool("test.write", AgentNativeToolConcurrency.SERIAL) {
                writeEntered.countDown()
                AgentNativeToolExecutionResult.success()
            })
        val pool = Executors.newFixedThreadPool(2)

        try {
            val read = pool.submit<AgentNativeToolResult> { registry.invoke("test.read", emptyMap()) }
            assertTrue(readEntered.await(2, TimeUnit.SECONDS))
            val write = pool.submit<AgentNativeToolResult> { registry.invoke("test.write", emptyMap()) }

            assertFalse(writeEntered.await(200, TimeUnit.MILLISECONDS))
            releaseRead.countDown()
            assertTrue(read.get(2, TimeUnit.SECONDS).isSuccess)
            assertTrue(write.get(2, TimeUnit.SECONDS).isSuccess)
            assertTrue(writeEntered.await(1, TimeUnit.SECONDS))
        } finally {
            releaseRead.countDown()
            pool.shutdownNow()
        }
    }

    @Test
    fun waitingMutationCanBeCancelledWithoutEnteringExecutor() {
        val firstEntered = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val secondEntered = CountDownLatch(1)
        val cancellation = AgentNativeToolCancellationSource()
        val registry = AgentNativeToolRegistry()
            .register(tool("test.write.blocking", AgentNativeToolConcurrency.SERIAL) {
                firstEntered.countDown()
                assertTrue(releaseFirst.await(2, TimeUnit.SECONDS))
                AgentNativeToolExecutionResult.success()
            })
            .register(tool("test.write.cancelled", AgentNativeToolConcurrency.SERIAL) {
                secondEntered.countDown()
                AgentNativeToolExecutionResult.success()
            })
        val pool = Executors.newFixedThreadPool(2)

        try {
            val first = pool.submit<AgentNativeToolResult> {
                registry.invoke("test.write.blocking", emptyMap())
            }
            assertTrue(firstEntered.await(2, TimeUnit.SECONDS))
            val second = pool.submit<AgentNativeToolResult> {
                registry.invoke(
                    "test.write.cancelled",
                    emptyMap(),
                    hooks = AgentNativeToolInvocationHooks(cancellationToken = cancellation.token)
                )
            }

            cancellation.cancel()
            assertEquals(
                AgentNativeToolResultStatus.CANCELLED,
                second.get(2, TimeUnit.SECONDS).status
            )
            assertEquals(1L, secondEntered.count)
            releaseFirst.countDown()
            assertTrue(first.get(2, TimeUnit.SECONDS).isSuccess)
        } finally {
            releaseFirst.countDown()
            pool.shutdownNow()
        }
    }

    @Test
    fun siblingFileMutationsExecuteConcurrently() {
        val entered = CountDownLatch(2)
        val release = CountDownLatch(1)
        val active = AtomicInteger()
        val maximum = AtomicInteger()
        val registry = AgentNativeToolRegistry()
            .register(tool(
                "test.workspace.write.left",
                AgentNativeToolConcurrency.SERIAL,
                setOf("workspace.file.bounded")
            ) { observeConcurrency(active, maximum, entered, release) })
            .register(tool(
                "test.workspace.write.right",
                AgentNativeToolConcurrency.SERIAL,
                setOf("workspace.file.bounded")
            ) { observeConcurrency(active, maximum, entered, release) })
        val pool = Executors.newFixedThreadPool(2)

        try {
            val first = pool.submit<AgentNativeToolResult> {
                registry.invoke(
                    "test.workspace.write.left",
                    mapOf("workspace_id" to "sibling-test", "path" to "src/left.kt")
                )
            }
            val second = pool.submit<AgentNativeToolResult> {
                registry.invoke(
                    "test.workspace.write.right",
                    mapOf("workspace_id" to "sibling-test", "path" to "src/right.kt")
                )
            }

            assertTrue(entered.await(2, TimeUnit.SECONDS))
            release.countDown()
            assertTrue(first.get(2, TimeUnit.SECONDS).isSuccess)
            assertTrue(second.get(2, TimeUnit.SECONDS).isSuccess)
            assertEquals(2, maximum.get())
        } finally {
            release.countDown()
            pool.shutdownNow()
        }
    }

    @Test
    fun sameFileMutationsRemainSerialized() {
        val firstEntered = CountDownLatch(1)
        val releaseFirst = CountDownLatch(1)
        val secondEntered = CountDownLatch(1)
        val registry = AgentNativeToolRegistry()
            .register(tool(
                "test.workspace.write.first",
                AgentNativeToolConcurrency.SERIAL,
                setOf("workspace.file.bounded")
            ) {
                firstEntered.countDown()
                assertTrue(releaseFirst.await(2, TimeUnit.SECONDS))
                AgentNativeToolExecutionResult.success()
            })
            .register(tool(
                "test.workspace.write.second",
                AgentNativeToolConcurrency.SERIAL,
                setOf("workspace.file.bounded")
            ) {
                secondEntered.countDown()
                AgentNativeToolExecutionResult.success()
            })
        val input = mapOf("workspace_id" to "same-file-test", "path" to "src/shared.kt")
        val pool = Executors.newFixedThreadPool(2)

        try {
            val first = pool.submit<AgentNativeToolResult> {
                registry.invoke("test.workspace.write.first", input)
            }
            assertTrue(firstEntered.await(2, TimeUnit.SECONDS))
            val second = pool.submit<AgentNativeToolResult> {
                registry.invoke("test.workspace.write.second", input)
            }

            assertFalse(secondEntered.await(200, TimeUnit.MILLISECONDS))
            releaseFirst.countDown()
            assertTrue(first.get(2, TimeUnit.SECONDS).isSuccess)
            assertTrue(second.get(2, TimeUnit.SECONDS).isSuccess)
            assertTrue(secondEntered.await(1, TimeUnit.SECONDS))
        } finally {
            releaseFirst.countDown()
            pool.shutdownNow()
        }
    }

    private fun tool(
        id: String,
        concurrency: AgentNativeToolConcurrency,
        capabilities: Set<String> = emptySet(),
        execute: () -> AgentNativeToolExecutionResult
    ) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(
            id = id,
            version = "1.0.0",
            title = id,
            description = "$id test tool",
            location = AgentNativeToolLocation.APPLICATION,
            inputSchema = AgentNativeJsonSchema.objectSchema(),
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.LOW,
            capabilities = capabilities,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
            concurrency = concurrency
        ),
        executor = AgentNativeToolExecutor { execute() }
    )

    private fun observeConcurrency(
        active: AtomicInteger,
        maximum: AtomicInteger,
        entered: CountDownLatch,
        release: CountDownLatch
    ): AgentNativeToolExecutionResult {
        val current = active.incrementAndGet()
        maximum.accumulateAndGet(current, ::maxOf)
        entered.countDown()
        return try {
            assertTrue(release.await(2, TimeUnit.SECONDS))
            AgentNativeToolExecutionResult.success()
        } finally {
            active.decrementAndGet()
        }
    }

    private fun observeSerial(
        active: AtomicInteger,
        maximum: AtomicInteger
    ): AgentNativeToolExecutionResult {
        val current = active.incrementAndGet()
        maximum.accumulateAndGet(current, ::maxOf)
        return try {
            Thread.sleep(150)
            AgentNativeToolExecutionResult.success()
        } finally {
            active.decrementAndGet()
        }
    }
}
