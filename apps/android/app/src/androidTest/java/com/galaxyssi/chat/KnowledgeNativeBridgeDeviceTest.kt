package com.galaxyssi.chat

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlin.math.sqrt
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeNativeBridgeDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val epoch = "61".repeat(16)
    private val key = ByteArray(32) { 7 }
    private val identity = ByteArray(32) { 8 }
    private fun vector(seed: Int): FloatArray {
        val random = java.util.Random(seed.toLong())
        val values = FloatArray(32) { (random.nextDouble() - 0.5).toFloat() }
        val norm = sqrt(values.sumOf { it.toDouble() * it }).toFloat()
        values.indices.forEach { values[it] /= norm }
        return values
    }
    private fun isolated(block: (File) -> Unit) {
        KnowledgeNativeBridge.requireAvailable()
        val root = File(context.noBackupFilesDir, "test-native-jni-${UUID.randomUUID()}").apply { mkdirs() }
        try { block(File(root, "index")) } finally { root.deleteRecursively() }
    }
    private fun open(path: File, create: Boolean) = KnowledgeNativeBridge.openIndex(path.absolutePath, key, identity,
        KnowledgeNativeWire.hex(epoch, 16), 32, 4, 1024 * 1024, if (create) vector(0) else null)
    private fun event(sequence: Long, previous: Long, chunks: Long = 2) = KnowledgeNativeEvent(sequence, previous,
        "01".repeat(32), "02".repeat(32), chunks, false)
    private fun append(handle: Long, event: KnowledgeNativeEvent, ordinal: Long) {
        val bytes = KnowledgeNativeWire.event(event)
        val values = vector(ordinal.toInt() + 1)
        try { KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.append(handle, bytes,
            longArrayOf(ordinal, ordinal * 10, ordinal * 10 + 10), values)) }
        finally { bytes.fill(0); values.fill(0f) }
    }

    @Test fun realJniResumesPagesFiltersIncompleteResultsAndDoesNotDuplicateCommittedWork() = isolated { path ->
        var handle = open(path, true)
        val e = event(7, 0)
        try {
            KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.beginEvent(handle, KnowledgeNativeWire.event(e), false))
            append(handle, e, 0)
            assertTrue(KnowledgeNativeWire.matches(KnowledgeNativeBridge.search(handle, vector(1), 8, 128)).isEmpty())
            assertEquals(2L, KnowledgeNativeBridge.nodeCount(handle))
            KnowledgeNativeBridge.closeIndex(handle)
            handle = open(path, false)
            val checkpoint = KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(handle))
            assertEquals(epoch, checkpoint.epoch); assertEquals(1L, checkpoint.pending?.next)
            append(handle, e, 0)
            assertEquals(2L, KnowledgeNativeBridge.nodeCount(handle))
            append(handle, e, 1)
            val hits = KnowledgeNativeWire.matches(KnowledgeNativeBridge.search(handle, vector(2), 8, 128))
            assertEquals(2, hits.size); assertEquals(10, hits.first().start)
            assertTrue(hits.first().similarity > 0.999)
            assertEquals(7L, KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(handle)).sequence)
        } finally { KnowledgeNativeBridge.closeIndex(handle) }
    }

    @Test fun malformedJniArraysAndClosedHandlesThrowWithoutCrashingOrPublishing() = isolated { path ->
        val handle = open(path, true)
        try {
            assertTrue(runCatching { KnowledgeNativeBridge.beginEvent(handle, ByteArray(1), false) }.isFailure)
            assertTrue(runCatching { KnowledgeNativeBridge.search(handle, FloatArray(31), 8, 128) }.isFailure)
            assertTrue(runCatching { KnowledgeNativeBridge.search(handle, vector(1), -1, 128) }.isFailure)
            assertTrue(runCatching { KnowledgeNativeBridge.append(handle, KnowledgeNativeWire.event(event(1, 0)),
                longArrayOf(0, 0), vector(1)) }.isFailure)
            assertEquals(1L, KnowledgeNativeBridge.nodeCount(handle))
            assertEquals(0L, KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(handle)).sequence)
        } finally { KnowledgeNativeBridge.closeIndex(handle) }
        assertTrue(runCatching { KnowledgeNativeBridge.nodeCount(handle) }.isFailure)
        KnowledgeNativeBridge.closeIndex(handle)
    }

    @Test fun cancellationIsPromptAndReopenPreservesDurableCheckpoint() = isolated { path ->
        val handle = open(path, true)
        try {
            val e = event(1, 0)
            KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.beginEvent(handle, KnowledgeNativeWire.event(e), false))
            append(handle, e, 0)
            val started = SystemClock.elapsedRealtime()
            KnowledgeNativeBridge.cancel(handle)
            assertTrue(SystemClock.elapsedRealtime() - started < 100)
            assertTrue(runCatching { append(handle, e, 1) }.isFailure)
        } finally { KnowledgeNativeBridge.closeIndex(handle) }
        val reopened = open(path, false)
        try { assertEquals(1L, KnowledgeNativeWire.checkpoint(KnowledgeNativeBridge.checkpoint(reopened)).pending?.next) }
        finally { KnowledgeNativeBridge.closeIndex(reopened) }
    }

    @Test fun wrongKeyIsRejectedAndNativeResultBuffersAreWipedAfterParsing() = isolated { path ->
        val handle = open(path, true)
        val bytes = KnowledgeNativeBridge.checkpoint(handle)
        assertEquals(0L, KnowledgeNativeWire.checkpoint(bytes).sequence)
        assertTrue(bytes.all { it == 0.toByte() })
        KnowledgeNativeBridge.closeIndex(handle)
        assertTrue(runCatching { KnowledgeNativeBridge.openIndex(path.absolutePath, ByteArray(32) { 9 }, identity,
            KnowledgeNativeWire.hex(epoch, 16), 32, 4, 1024 * 1024, null) }.isFailure)
        val reopened = open(path, false)
        KnowledgeNativeBridge.closeIndex(reopened)
    }
}
