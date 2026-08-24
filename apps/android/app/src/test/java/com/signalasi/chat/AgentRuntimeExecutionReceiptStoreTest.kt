package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class AgentRuntimeExecutionReceiptStoreTest {
    @Test
    fun beginWritesOnlyTheNewReceiptAndItsIndex() {
        val persistence = RecordingReceiptPersistence()
        val store = AgentRuntimeExecutionReceiptStore(persistence)

        val receipt = store.begin(request("request-1"), mapOf("python" to "3.13"))

        assertEquals(AgentRuntimeReceiptStatus.RUNNING, receipt.status)
        assertEquals(1, persistence.containsCount)
        assertEquals(1, persistence.keysCount)
        assertEquals(1, persistence.mutateCount)
        assertEquals(2, persistence.values.size)
        assertEquals(0, persistence.readCount)
    }

    @Test
    fun completionReadsAndWritesOnlyTheRequestedReceipt() {
        val persistence = RecordingReceiptPersistence()
        val store = AgentRuntimeExecutionReceiptStore(persistence)
        store.begin(request("request-1"), emptyMap())
        persistence.resetCounts()

        val updated = store.complete(
            requestId = "request-1",
            response = AgentRuntimeExecutionResponse(
                exitCode = 0,
                stdout = "done",
                stderr = "",
                durationMillis = 25L
            ),
            artifacts = emptyList()
        )

        assertEquals(AgentRuntimeReceiptStatus.COMPLETED, updated?.status)
        assertEquals(2, persistence.readCount)
        assertEquals(1, persistence.writeCount)
        assertEquals(0, persistence.mutateCount)
    }

    @Test
    fun duplicateRequestIdsAreRejectedWithoutDecryptingHistory() {
        val persistence = RecordingReceiptPersistence()
        val store = AgentRuntimeExecutionReceiptStore(persistence)
        store.begin(request("request-1"), emptyMap())
        persistence.resetCounts()

        assertThrows(IllegalStateException::class.java) {
            store.begin(request("request-1"), emptyMap())
        }

        assertEquals(1, persistence.containsCount)
        assertEquals(0, persistence.readCount)
        assertEquals(0, persistence.writeCount)
        assertEquals(0, persistence.mutateCount)
    }

    @Test
    fun independentStoreInstancesShareCurrentReceiptState() {
        val persistence = RecordingReceiptPersistence()
        val first = AgentRuntimeExecutionReceiptStore(persistence)
        val second = AgentRuntimeExecutionReceiptStore(persistence)
        first.begin(request("request-1"), emptyMap())

        val found = second.find("request-1")

        assertEquals("request-1", found?.requestId)
        assertEquals(AgentRuntimeReceiptStatus.RUNNING, found?.status)
        assertNull(second.find("missing"))
    }

    @Test
    fun retentionRemovesOnlyTheOldestReceiptAndIndex() {
        val persistence = RecordingReceiptPersistence()
        var now = 1_000L
        val store = AgentRuntimeExecutionReceiptStore(persistence) { now++ }

        repeat(1_001) { index -> store.begin(request("request-$index"), emptyMap()) }

        assertNull(store.find("request-0"))
        assertEquals("request-1000", store.list(limit = 1).single().requestId)
        assertEquals(1_000, store.list().size)
        assertEquals(2_000, persistence.values.size)
    }

    @Test
    fun timeoutFailureKeepsTheReceiptAndUsesTheInjectedClock() {
        val persistence = RecordingReceiptPersistence()
        var now = 5_000L
        val store = AgentRuntimeExecutionReceiptStore(persistence) { now }
        store.begin(request("request-1"), emptyMap())
        now = 8_000L

        val failed = store.fail("request-1", AgentNativeToolTimeoutException())

        assertEquals(AgentRuntimeReceiptStatus.TIMED_OUT, failed?.status)
        assertEquals(5_000L, failed?.createdAtMillis)
        assertEquals(8_000L, failed?.completedAtMillis)
        assertEquals("Native tool invocation exceeded its deadline", failed?.error)
    }

    @Test
    fun recentListDecryptsOnlyTheRequestedReceiptCount() {
        val persistence = RecordingReceiptPersistence()
        var now = 1_000L
        val store = AgentRuntimeExecutionReceiptStore(persistence) { now++ }
        repeat(20) { index -> store.begin(request("request-$index"), emptyMap()) }
        persistence.resetCounts()

        val recent = store.list(limit = 5)

        assertEquals(listOf("request-19", "request-18", "request-17", "request-16", "request-15"), recent.map { it.requestId })
        assertEquals(1, persistence.keysCount)
        assertEquals(5, persistence.readCount)
    }

    private fun request(requestId: String) = AgentRuntimeExecutionRequest(
        requestId = requestId,
        language = AgentRuntimeLanguage.PYTHON,
        source = "print('ok')",
        arguments = emptyList(),
        timeoutMillis = 30_000L,
        networkEnabled = false,
        artifactPaths = emptyList(),
        workspaceId = "workspace-1"
    )
}

private class RecordingReceiptPersistence : AgentRuntimeReceiptPersistence {
    val values = sortedMapOf<String, String>()
    var containsCount = 0
    var readCount = 0
    var writeCount = 0
    var mutateCount = 0
    var keysCount = 0

    override fun contains(key: String): Boolean {
        containsCount += 1
        return values.containsKey(key)
    }

    override fun readString(key: String, defaultValue: String): String {
        readCount += 1
        return values[key] ?: defaultValue
    }

    override fun writeString(key: String, value: String) {
        writeCount += 1
        values[key] = value
    }

    override fun mutateStrings(upserts: Map<String, String>, removeKeys: Collection<String>) {
        mutateCount += 1
        removeKeys.forEach(values::remove)
        values.putAll(upserts)
    }

    override fun keys(prefix: String): List<String> {
        keysCount += 1
        return values.keys.filter { it.startsWith(prefix) }
    }

    override fun clear() {
        values.clear()
    }

    fun resetCounts() {
        containsCount = 0
        readCount = 0
        writeCount = 0
        mutateCount = 0
        keysCount = 0
    }
}
