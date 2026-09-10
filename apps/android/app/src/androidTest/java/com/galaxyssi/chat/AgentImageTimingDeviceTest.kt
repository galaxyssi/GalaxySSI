package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.net.Uri
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.metrics.*
import java.io.File
import java.util.Collections
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentImageTimingDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val directory = File(context.cacheDir, "image-timing-${UUID.randomUUID()}").apply { mkdirs() }
    private val points = Collections.synchronizedList(mutableListOf<AgentTimingPoint>())
    private val timing = AgentRuntimeTiming({ trace, stage, operation, outcome, at ->
        points += AgentTimingPoint(trace, "b".repeat(32), stage, at, 0, operation, outcome = outcome)
    }, SystemClock::elapsedRealtimeNanos)

    @After fun clean() { directory.deleteRecursively() }

    @Test fun smallOriginalIsUnchangedAndDoesNotInventDecodeOrEncodeSamples() {
        val source = image(false)
        val output = encode(source)!!
        try {
            assertTrue(output.lossless)
            assertArrayEquals(File(source.uri.path!!).readBytes(), output.bytes)
            assertEquals(setOf("image_prepare", "image_original_probe"), completedPhases())
            assertEquals(1, metric("image_prepare").count)
        } finally { output.wipe() }
    }

    @Test fun realJpegDecodeOrientationAndCompressionAreByteIdenticalWithTracing() {
        val source = image(true)
        ExifInterface(source.uri.path!!).apply {
            setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_ROTATE_90.toString())
            saveAttributes()
        }
        val traced = encode(source)!!
        val baseline = AgentImagePipeline.encodeForTransport(context, source)!!
        try {
            assertFalse(traced.lossless)
            assertTrue(traced.bytes.size <= 100_000)
            assertArrayEquals(baseline.bytes, traced.bytes)
            assertTrue(traced.height > traced.width)
            val bitmap = BitmapFactory.decodeByteArray(traced.bytes, 0, traced.bytes.size)!!
            try { assertEquals(traced.width, bitmap.width); assertEquals(traced.height, bitmap.height) }
            finally { bitmap.recycle() }
            assertEquals(imagePhases, completedPhases())
            imagePhases.forEach { assertEquals(1, metric(it).count) }
        } finally { baseline.wipe(); traced.wipe() }
    }

    @Test fun missingAndCorruptInputsRecordFailureWithoutSuccessfulDecodeOrEncode() {
        val missing = attachment(File(directory, "missing.jpg"), 200_000)
        val corrupt = File(directory, "corrupt.jpg").apply { writeBytes(ByteArray(110_000) { 17 }) }
        for (source in listOf(missing, attachment(corrupt, corrupt.length()))) {
            assertNull(encode(source))
        }
        assertEquals(2, metric("image_prepare").unsuccessful)
        assertEquals(2, metric("image_decode").unsuccessful)
        assertEquals(0, metric("image_decode").count)
        assertFalse(points.any { it.stage.contains("image_encode") })
    }

    @Test fun exhaustedBudgetDoesNotReadOrDecodeTheImage() {
        val output = AgentImagePipeline.encodeForTransport(context, image(false), 1, "budget", timing)
        assertNull(output)
        assertEquals(2, points.size)
        assertEquals(1, metric("image_prepare").unsuccessful)
        assertTrue(points.all { it.stage.contains("image_prepare") })
    }

    @Test fun sameTaskMultipleImagesAndConcurrentTasksHaveIndependentPrivateSamples() {
        val source = image(false)
        val pool = Executors.newFixedThreadPool(2)
        try {
            (0 until 12).map { index -> pool.submit {
                encode(source, if (index < 6) "private-task-one" else "private-task-two")!!.wipe()
            } }.forEach { it.get(20, TimeUnit.SECONDS) }
        } finally { pool.shutdownNow(); assertTrue(pool.awaitTermination(10, TimeUnit.SECONDS)) }
        assertEquals(12, metric("image_prepare").count)
        assertEquals(24, points.map { it.operationId }.distinct().size)
        assertEquals(2, points.map { it.traceId }.distinct().size)
        assertTrue(points.all(AgentLatencyContract::valid))
        val serialized = points.toString()
        for (secret in listOf("private-task", source.displayName, source.uri.toString(), source.id)) {
            assertFalse(serialized.contains(secret))
        }
    }

    @Test fun telemetryWriterFailureCannotChangeEncodedBytesOrIntroduceRetries() {
        val source = image(true)
        val baseline = AgentImagePipeline.encodeForTransport(context, source)!!
        var events = 0
        val broken = AgentRuntimeTiming({ _, _, _, _, _ -> events++; error("telemetry unavailable") })
        val actual = AgentImagePipeline.encodeForTransport(context, source, taskId = "broken", timing = broken)!!
        try {
            assertArrayEquals(baseline.bytes, actual.bytes)
            assertEquals(8, events)
        } finally { baseline.wipe(); actual.wipe() }
    }

    @Test fun productionJournalOverheadIsMeasuredAroundRealImageProcessing() {
        val source = image(true)
        val journal = AgentTimingJournal(File(directory, "timings.jsonl"))
        val tracer = AgentLatencyTracer(journal, SystemClock::elapsedRealtimeNanos)
        val recorded = AgentRuntimeTiming({ trace, stage, operation, outcome, at ->
            tracer.recordOpaque(trace, stage, operation, outcome, at)
        }, SystemClock::elapsedRealtimeNanos)
        val baseline = mutableListOf<Double>()
        val traced = mutableListOf<Double>()
        try {
            repeat(4) { AgentImagePipeline.encodeForTransport(context, source, taskId = "warmup", timing = recorded)!!.wipe() }
            repeat(40) { index ->
                val enabled = index % 2 == 0
                val start = SystemClock.elapsedRealtimeNanos()
                val output = AgentImagePipeline.encodeForTransport(context, source, taskId = "image-benchmark",
                    timing = if (enabled) recorded else AgentRuntimeTiming.NONE)!!
                val elapsed = (SystemClock.elapsedRealtimeNanos() - start) / 1_000_000.0
                output.wipe()
                (if (enabled) traced else baseline).add(elapsed)
            }
        } finally { journal.close() }
        val samples = journal.snapshot().filter { it.traceId == AgentLatencyContract.opaqueId("image-benchmark") }
        val metrics = AgentLatencyContract.summarize(samples)
        imagePhases.forEach { assertEquals(20, metrics.getValue("phone_runtime_${it}_ms").count) }
        assertEquals(0L, journal.health()["dropped_events"])
        assertEquals(0L, journal.health()["write_failures"])
        val baselineP95 = baseline.sorted()[18]
        val tracedP95 = traced.sorted()[18]
        Log.i("GalaxySSIImageTimingTest", "sink=production_journal image_pairs=20 baseline_p95_ms=$baselineP95 " +
            "traced_p95_ms=$tracedP95 stages=" + metrics.filterKeys { it.contains("image_") })
        // Relative overhead gate, not a claim about camera input sizes or end-to-end latency.
        assertTrue("Image tracing overhead: baseline=$baselineP95 traced=$tracedP95",
            tracedP95 <= baselineP95 * 1.10 + 10.0)
    }

    private fun encode(source: AgentInputAttachment, task: String = "private-image-task") =
        AgentImagePipeline.encodeForTransport(context, source, taskId = task, timing = timing)

    private fun completedPhases() = points.filter { it.stage.endsWith("_finished") && it.outcome == "completed" }
        .map { it.stage.removePrefix("phone_runtime_").removeSuffix("_finished") }.toSet()

    private fun metric(phase: String) = AgentLatencyContract.summarize(points.toList())
        .getValue("phone_runtime_${phase}_ms")

    private fun image(large: Boolean): AgentInputAttachment {
        val width = if (large) 800 else 32
        val height = if (large) 600 else 32
        var state = 0x13579BDF
        val pixels = IntArray(width * height) {
            state = state * 1103515245 + 12345
            if (large) (0xFF shl 24) or (state and 0x00FFFFFF) else 0xFF20A7D1.toInt()
        }
        val bitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        pixels.fill(0)
        val file = File(directory, "private-image-${UUID.randomUUID()}.${if (large) "jpg" else "png"}")
        try { file.outputStream().use { bitmap.compress(if (large) Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG, 96, it) } }
        finally { bitmap.recycle() }
        if (large) assertTrue(file.length() > 100_000)
        return attachment(file, file.length())
    }

    private fun attachment(file: File, size: Long) = AgentInputAttachment("private-attachment-id", Uri.fromFile(file),
        file.name, if (file.extension == "png") "image/png" else "image/jpeg", size)

    companion object {
        private val imagePhases = setOf("image_prepare", "image_original_probe", "image_decode", "image_encode")
    }
}
