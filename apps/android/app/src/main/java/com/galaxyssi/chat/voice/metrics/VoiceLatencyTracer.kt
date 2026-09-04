package com.galaxyssi.chat.voice.metrics

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.ceil

const val VOICE_LATENCY_TRACE_FLAG = "voice.latency_tracing_v1"

object VoiceTraceEvents {
    const val SESSION_CREATED = "voice_session_created"
    const val MICROPHONE_OPEN_STARTED = "microphone_open_started"
    const val MICROPHONE_OPENED = "microphone_opened"
    const val PCM_CAPTURE_READY = "pcm_capture_ready"
    const val PCM_CAPTURE_STOPPED = "pcm_capture_stopped"
    const val VAD_ENDPOINT = "vad_endpoint"
    const val SPEECH_STARTED = "speech_started"
    const val SPEECH_ENDED = "speech_ended"
    const val ASR_FIRST_PARTIAL = "asr_first_partial"
    const val ASR_FIRST_STABLE = "asr_first_stable"
    const val ASR_FINAL_STARTED = "asr_final_started"
    const val ASR_DECODE_STARTED = "asr_decode_started"
    const val ASR_DECODE_COMPLETED = "asr_decode_completed"
    const val ASR_MODEL_LOAD_STARTED = "asr_model_load_started"
    const val ASR_MODEL_LOAD_COMPLETED = "asr_model_load_completed"
    const val WHISPER_FULL_STARTED = "whisper_full_started"
    const val WHISPER_FULL_COMPLETED = "whisper_full_completed"
    const val ASR_FINAL_RECEIVED = "asr_final_received"
    const val ASR_FINAL_FAILED = "asr_final_failed"
    const val SECOND_PASS_STARTED = "second_pass_started"
    const val SECOND_PASS_COMPLETED = "second_pass_completed"
    const val ROUTE_STARTED = "route_started"
    const val ROUTE_SELECTED = "route_selected"
    const val LOCAL_ACTION_STARTED = "local_action_started"
    const val LOCAL_ACTION_COMPLETED = "local_action_completed"
    const val MODEL_REQUEST_STARTED = "model_request_started"
    const val MODEL_CONNECTED = "model_connected"
    const val MODEL_FIRST_DELTA = "model_first_delta"
    const val MODEL_FIRST_SENTENCE_COMMITTED = "model_first_sentence_committed"
    const val MODEL_REQUEST_COMPLETED = "model_request_completed"
    const val TTS_REQUEST_STARTED = "tts_request_started"
    const val TTS_CONNECTED = "tts_connected"
    const val TTS_FIRST_AUDIO = "tts_first_audio"
    const val TTS_PLAYBACK_STARTED = "tts_playback_started"
    const val TTS_QUEUE_UNDERRUN = "tts_queue_underrun"
    const val TTS_COMPLETED = "tts_completed"
    const val TTS_BARGE_IN_STARTED = "tts_barge_in_started"
    const val TTS_BARGE_IN_COMPLETED = "tts_barge_in_completed"
    const val AGENT_RUN_CREATE_STARTED = "agent_run_create_started"
    const val AGENT_RUN_ACCEPTED = "agent_run_accepted"
    const val AGENT_FIRST_PROGRESS = "agent_first_progress"
    const val AGENT_FIRST_PARTIAL_RESULT = "agent_first_partial_result"
    const val AGENT_COMPLETED = "agent_completed"
    const val SESSION_COMPLETED = "voice_session_completed"
    const val SESSION_CANCELLED = "voice_session_cancelled"
    const val SESSION_FAILED = "voice_session_failed"
}

data class VoiceTraceEvent(
    val traceId: String,
    val sessionId: String,
    val event: String,
    val elapsedRealtimeNs: Long,
    val wallClockMs: Long,
    val attributes: Map<String, String>
)

data class VoiceLatencyPercentiles(
    val count: Int,
    val p50Ms: Long,
    val p90Ms: Long,
    val p95Ms: Long,
    val p99Ms: Long
)

data class VoiceDiagnosticSummary(
    val traceCount: Int,
    val eventCount: Int,
    val completedCount: Int,
    val cancelledCount: Int,
    val failedCount: Int,
    val successRate: Double,
    val cancellationRate: Double,
    val failureRate: Double,
    val fallbackRate: Double,
    val oomCount: Int,
    val nativeCrashCount: Int,
    val thermalDegradeCount: Int,
    val modelVerificationFailureCount: Int,
    val metrics: Map<String, VoiceLatencyPercentiles>
)

fun interface VoiceElapsedRealtimeSource {
    fun nowNanos(): Long
}

fun interface VoiceWallClockSource {
    fun nowMillis(): Long
}

interface VoiceTraceEventSink {
    fun append(event: VoiceTraceEvent)
    fun snapshot(): List<VoiceTraceEvent>
}

class InMemoryVoiceTraceEventSink : VoiceTraceEventSink {
    private val events = mutableListOf<VoiceTraceEvent>()

    override fun append(event: VoiceTraceEvent) = synchronized(events) {
        events += event
    }

    override fun snapshot(): List<VoiceTraceEvent> = synchronized(events) {
        events.toList()
    }
}

class VoiceLatencyTracer(
    private val elapsedSource: VoiceElapsedRealtimeSource,
    private val wallClockSource: VoiceWallClockSource,
    private val enabled: () -> Boolean = { true },
    private val sink: VoiceTraceEventSink = InMemoryVoiceTraceEventSink()
) {
    private val onceKeys = LinkedHashSet<String>()

    fun startSession(attributes: Map<String, String> = emptyMap()): String {
        val id = UUID.randomUUID().toString()
        record(id, id, VoiceTraceEvents.SESSION_CREATED, attributes, once = true)
        return id
    }

    fun record(
        traceId: String,
        sessionId: String = traceId,
        event: String,
        attributes: Map<String, String> = emptyMap(),
        once: Boolean = false
    ): VoiceTraceEvent? {
        if (!enabled()) return null
        val safeTraceId = VoiceTracePrivacy.safeIdentifier(traceId) ?: return null
        val safeSessionId = VoiceTracePrivacy.safeIdentifier(sessionId) ?: safeTraceId
        val safeEvent = VoiceTracePrivacy.safeEvent(event) ?: return null
        if (once) {
            val key = "$safeTraceId:$safeEvent"
            synchronized(onceKeys) {
                if (!onceKeys.add(key)) return null
                if (onceKeys.size > 32_000) {
                    val iterator = onceKeys.iterator()
                    repeat(8_000) {
                        if (iterator.hasNext()) {
                            iterator.next()
                            iterator.remove()
                        }
                    }
                }
            }
        }
        return VoiceTraceEvent(
            traceId = safeTraceId,
            sessionId = safeSessionId,
            event = safeEvent,
            elapsedRealtimeNs = elapsedSource.nowNanos().coerceAtLeast(0L),
            wallClockMs = wallClockSource.nowMillis().coerceAtLeast(0L),
            attributes = VoiceTracePrivacy.sanitizeAttributes(attributes)
        ).also(sink::append)
    }

    fun snapshot(): List<VoiceTraceEvent> = sink.snapshot()

    fun elapsedMillis(traceId: String, startEvent: String, endEvent: String): Long? {
        val events = snapshot()
            .filter { it.traceId == traceId }
            .sortedBy { it.elapsedRealtimeNs }
        val start = events.firstOrNull { it.event == startEvent }?.elapsedRealtimeNs ?: return null
        val end = events.firstOrNull { it.event == endEvent && it.elapsedRealtimeNs >= start }
            ?.elapsedRealtimeNs ?: return null
        return ((end - start) / 1_000_000L).coerceAtLeast(0L)
    }

    fun diagnosticSummary(): VoiceDiagnosticSummary = summarize(snapshot())

    companion object {
        private val metricPairs = linkedMapOf(
            "microphone_open_ms" to (VoiceTraceEvents.MICROPHONE_OPEN_STARTED to VoiceTraceEvents.MICROPHONE_OPENED),
            "endpoint_wait_ms" to (VoiceTraceEvents.SPEECH_STARTED to VoiceTraceEvents.SPEECH_ENDED),
            "asr_decode_ms" to (VoiceTraceEvents.ASR_DECODE_STARTED to VoiceTraceEvents.ASR_DECODE_COMPLETED),
            "whisper_full_ms" to (VoiceTraceEvents.WHISPER_FULL_STARTED to VoiceTraceEvents.WHISPER_FULL_COMPLETED),
            "asr_total_ms" to (VoiceTraceEvents.ASR_FINAL_STARTED to VoiceTraceEvents.ASR_FINAL_RECEIVED),
            "model_connect_ms" to (VoiceTraceEvents.MODEL_REQUEST_STARTED to VoiceTraceEvents.MODEL_CONNECTED),
            "model_first_delta_ms" to (VoiceTraceEvents.MODEL_REQUEST_STARTED to VoiceTraceEvents.MODEL_FIRST_DELTA),
            "model_first_sentence_ms" to (VoiceTraceEvents.MODEL_REQUEST_STARTED to VoiceTraceEvents.MODEL_FIRST_SENTENCE_COMMITTED),
            "model_total_ms" to (VoiceTraceEvents.MODEL_REQUEST_STARTED to VoiceTraceEvents.MODEL_REQUEST_COMPLETED),
            "tts_first_audio_ms" to (VoiceTraceEvents.TTS_REQUEST_STARTED to VoiceTraceEvents.TTS_FIRST_AUDIO),
            "tts_playback_ms" to (VoiceTraceEvents.TTS_REQUEST_STARTED to VoiceTraceEvents.TTS_PLAYBACK_STARTED),
            "tts_barge_in_ms" to (VoiceTraceEvents.TTS_BARGE_IN_STARTED to VoiceTraceEvents.TTS_BARGE_IN_COMPLETED),
            "agent_accept_ms" to (VoiceTraceEvents.AGENT_RUN_CREATE_STARTED to VoiceTraceEvents.AGENT_RUN_ACCEPTED),
            "agent_first_progress_ms" to (VoiceTraceEvents.AGENT_RUN_CREATE_STARTED to VoiceTraceEvents.AGENT_FIRST_PROGRESS),
            "agent_first_output_ms" to (VoiceTraceEvents.AGENT_RUN_CREATE_STARTED to VoiceTraceEvents.AGENT_FIRST_PARTIAL_RESULT),
            "agent_total_ms" to (VoiceTraceEvents.AGENT_RUN_CREATE_STARTED to VoiceTraceEvents.AGENT_COMPLETED),
            "voice_total_ms" to (VoiceTraceEvents.SESSION_CREATED to VoiceTraceEvents.SESSION_COMPLETED)
        )

        fun summarize(events: List<VoiceTraceEvent>): VoiceDiagnosticSummary {
            val byTrace = events.groupBy(VoiceTraceEvent::traceId)
            val completedCount = byTrace.values.count { trace ->
                trace.any { it.event == VoiceTraceEvents.SESSION_COMPLETED }
            }
            val cancelledCount = byTrace.values.count { trace ->
                trace.any { it.event == VoiceTraceEvents.SESSION_CANCELLED }
            }
            val failedCount = byTrace.values.count { trace ->
                trace.any { it.event == VoiceTraceEvents.SESSION_FAILED }
            }
            val terminalCount = completedCount + cancelledCount + failedCount
            val fallbackCount = byTrace.values.count { trace ->
                trace.any { it.attributes["fallback"] == "true" }
            }
            fun rate(count: Int, total: Int): Double = if (total > 0) count.toDouble() / total else 0.0
            val values = metricPairs.keys.associateWith { mutableListOf<Long>() }
            byTrace.values.forEach { traceEvents ->
                val ordered = traceEvents.sortedBy(VoiceTraceEvent::elapsedRealtimeNs)
                metricPairs.forEach { (metric, pair) ->
                    val start = ordered.firstOrNull { it.event == pair.first }?.elapsedRealtimeNs
                        ?: return@forEach
                    val end = ordered.firstOrNull {
                        it.event == pair.second && it.elapsedRealtimeNs >= start
                    }?.elapsedRealtimeNs ?: return@forEach
                    values.getValue(metric) += ((end - start) / 1_000_000L).coerceAtLeast(0L)
                }
            }
            return VoiceDiagnosticSummary(
                traceCount = byTrace.size,
                eventCount = events.size,
                completedCount = completedCount,
                cancelledCount = cancelledCount,
                failedCount = failedCount,
                successRate = rate(completedCount, terminalCount),
                cancellationRate = rate(cancelledCount, terminalCount),
                failureRate = rate(failedCount, terminalCount),
                fallbackRate = rate(fallbackCount, byTrace.size),
                oomCount = events.count { event ->
                    event.attributes["error_code"].orEmpty().contains("outofmemory", ignoreCase = true) ||
                        event.attributes["error_code"].orEmpty().equals("oom", ignoreCase = true)
                },
                nativeCrashCount = events.count { event ->
                    event.attributes["error_code"].orEmpty().lowercase() in setOf(
                        "native_crash", "sigill", "sigsegv", "sigabrt"
                    )
                },
                thermalDegradeCount = events.count { event ->
                    event.attributes["error_code"].orEmpty().equals("thermal_degraded", ignoreCase = true)
                },
                modelVerificationFailureCount = events.count { event ->
                    event.attributes["error_code"].orEmpty().equals("model_verification_failed", ignoreCase = true)
                },
                metrics = values.mapNotNull { (name, samples) ->
                    samples.takeIf(List<Long>::isNotEmpty)?.let { name to percentiles(it) }
                }.toMap()
            )
        }

        private fun percentiles(samples: List<Long>): VoiceLatencyPercentiles {
            val sorted = samples.sorted()
            fun percentile(value: Double): Long {
                val index = (ceil(value * sorted.size).toInt() - 1).coerceIn(0, sorted.lastIndex)
                return sorted[index]
            }
            return VoiceLatencyPercentiles(
                count = sorted.size,
                p50Ms = percentile(0.50),
                p90Ms = percentile(0.90),
                p95Ms = percentile(0.95),
                p99Ms = percentile(0.99)
            )
        }
    }
}

object VoiceTracePrivacy {
    private val allowedKeys = setOf(
        "device_model", "soc", "android_api", "app_version", "native_version",
        "network_type", "asr_provider", "model_provider", "model_profile_id", "model_sha256",
        "quantization", "execution_mode", "thread_count", "thermal_status",
        "battery_percent", "is_charging", "audio_duration_ms", "rtf",
        "agent_provider", "tts_provider", "error_code", "recording_source", "endpoint_reason",
        "http_status", "success", "cold_start", "queue_depth", "transport",
        "task_status", "retry_count", "fallback", "duration_ms", "audio_source", "input_route",
        "short_read_count", "zero_read_count", "dropped_frame_count", "overrun_count",
        "route_change_count"
    )
    private val numericKeys = setOf(
        "android_api", "thread_count", "thermal_status", "battery_percent",
        "audio_duration_ms", "rtf", "http_status", "queue_depth", "retry_count",
        "duration_ms", "audio_source", "short_read_count", "zero_read_count",
        "dropped_frame_count", "overrun_count", "route_change_count"
    )
    private val booleanKeys = setOf("is_charging", "success", "cold_start", "fallback")
    private val identifierPattern = Regex("[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
    private val eventPattern = Regex("[a-z][a-z0-9_]{0,95}")
    private val technicalValuePattern = Regex("[A-Za-z0-9][A-Za-z0-9 ._:+-]{0,119}")

    fun safeIdentifier(value: String): String? = value.trim().takeIf(identifierPattern::matches)

    fun safeEvent(value: String): String? = value.trim().lowercase().takeIf(eventPattern::matches)

    fun sanitizeAttributes(attributes: Map<String, String>): Map<String, String> = buildMap {
        attributes.forEach { (rawKey, rawValue) ->
            val key = rawKey.trim().lowercase()
            if (key !in allowedKeys) return@forEach
            val value = rawValue.trim()
            val safe = when {
                key == "model_sha256" -> value.lowercase().takeIf { it.matches(Regex("[a-f0-9]{64}")) }
                key in numericKeys -> value.takeIf { it.toDoubleOrNull()?.isFinite() == true }
                key in booleanKeys -> value.lowercase().takeIf { it == "true" || it == "false" }
                value.contains('/') || value.contains('\\') || value.contains('@') -> null
                else -> value.takeIf(technicalValuePattern::matches)
            }
            if (safe != null) put(key, safe)
        }
    }
}

object VoiceLatencyFeatureFlags {
    private const val PREFERENCES = "galaxyssi_voice_feature_flags"

    fun isEnabled(context: Context): Boolean = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        .getBoolean(VOICE_LATENCY_TRACE_FLAG, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_LATENCY_TRACE_FLAG, enabled)
            .apply()
    }
}

object VoiceLatencyTraceContext {
    private val current = ThreadLocal<String>()

    fun currentTraceId(): String = current.get().orEmpty()

    fun <T> withTrace(traceId: String, operation: () -> T): T {
        val previous = current.get()
        if (traceId.isBlank()) current.remove() else current.set(traceId)
        return try {
            operation()
        } finally {
            if (previous.isNullOrBlank()) current.remove() else current.set(previous)
        }
    }
}

object VoiceLatencyTelemetry {
    private const val SCHEMA = "galaxyssi.voice-latency/1.0"
    private val lock = Any()
    @Volatile private var instance: VoiceLatencyTracer? = null

    fun startSession(context: Context, attributes: Map<String, String> = emptyMap()): String {
        val appContext = context.applicationContext
        if (!VoiceLatencyFeatureFlags.isEnabled(appContext)) return ""
        return tracer(appContext).startSession(deviceAttributes(appContext) + attributes)
    }

    fun record(
        context: Context,
        traceId: String,
        event: String,
        attributes: Map<String, String> = emptyMap(),
        once: Boolean = false
    ): VoiceTraceEvent? = tracer(context).record(traceId, traceId, event, attributes, once)

    fun exportContentFreeDiagnostics(context: Context): File {
        val tracer = tracer(context)
        val events = tracer.snapshot()
        val summary = tracer.diagnosticSummary()
        val output = File(context.cacheDir, "diagnostics/voice_latency_${System.currentTimeMillis()}.json")
        output.parentFile?.mkdirs()
        val root = JSONObject()
            .put("schema", SCHEMA)
            .put("feature_flag", VOICE_LATENCY_TRACE_FLAG)
            .put("content_included", false)
            .put("generated_at_ms", System.currentTimeMillis())
            .put("summary", summary.toJson())
            .put("events", JSONArray().apply { events.forEach { put(it.toJson()) } })
        output.writeText(root.toString(2), Charsets.UTF_8)
        return output
    }

    fun diagnosticSummary(context: Context): VoiceDiagnosticSummary =
        tracer(context.applicationContext).diagnosticSummary()

    private fun tracer(context: Context): VoiceLatencyTracer {
        instance?.let { return it }
        return synchronized(lock) {
            instance ?: VoiceLatencyTracer(
                elapsedSource = VoiceElapsedRealtimeSource(SystemClock::elapsedRealtimeNanos),
                wallClockSource = VoiceWallClockSource(System::currentTimeMillis),
                enabled = { VoiceLatencyFeatureFlags.isEnabled(context.applicationContext) },
                sink = AndroidVoiceTraceEventStore(context.applicationContext)
            ).also { instance = it }
        }
    }

    private fun deviceAttributes(context: Context): Map<String, String> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percent = if (level >= 0 && scale > 0) (level * 100 / scale) else -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        val network = runCatching {
            val manager = context.getSystemService(ConnectivityManager::class.java)
            val capabilities = manager?.getNetworkCapabilities(manager.activeNetwork)
            when {
                capabilities == null -> "offline"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                else -> "other"
            }
        }.getOrDefault("unknown")
        val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.getSystemService(PowerManager::class.java)?.currentThermalStatus ?: -1
        } else {
            -1
        }
        val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else Build.HARDWARE
        return mapOf(
            "device_model" to Build.MODEL.orEmpty(),
            "soc" to soc.orEmpty(),
            "android_api" to Build.VERSION.SDK_INT.toString(),
            "app_version" to runCatching {
                context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty()
            }.getOrDefault("unknown"),
            "network_type" to network,
            "thermal_status" to thermal.toString(),
            "battery_percent" to percent.toString(),
            "is_charging" to charging.toString()
        )
    }
}

private class AndroidVoiceTraceEventStore(context: Context) : VoiceTraceEventSink {
    private val lock = Any()
    private val file = File(context.filesDir, "diagnostics/voice_latency_v1.jsonl")
    private val rotated = File(context.filesDir, "diagnostics/voice_latency_v1.previous.jsonl")
    private val pending = ArrayDeque<VoiceTraceEvent>()
    private val writer = Executors.newSingleThreadExecutor { operation ->
        Thread(operation, "voice-latency-writer").apply {
            isDaemon = true
            priority = Thread.MIN_PRIORITY
        }
    }

    override fun append(event: VoiceTraceEvent) {
        synchronized(lock) {
            pending.addLast(event)
            while (pending.size > 8_000) pending.removeFirst()
        }
        writer.execute {
            synchronized(lock) {
                file.parentFile?.mkdirs()
                if (file.exists() && file.length() >= 2L * 1024L * 1024L) {
                    rotated.delete()
                    file.renameTo(rotated)
                }
                file.appendText(event.toJson().toString() + "\n", Charsets.UTF_8)
                pending.remove(event)
            }
        }
    }

    override fun snapshot(): List<VoiceTraceEvent> = synchronized(lock) {
        val persisted = sequenceOf(rotated, file)
            .filter(File::isFile)
            .flatMap { source -> source.useLines { lines -> lines.toList().asSequence() } }
            .mapNotNull { line -> runCatching { JSONObject(line).toVoiceTraceEvent() }.getOrNull() }
            .toList()
        (persisted + pending)
            .distinctBy { event -> "${event.traceId}:${event.event}:${event.elapsedRealtimeNs}" }
            .takeLast(8_000)
    }
}

private fun VoiceTraceEvent.toJson(): JSONObject = JSONObject()
    .put("trace_id", traceId)
    .put("session_id", sessionId)
    .put("event", event)
    .put("elapsed_realtime_ns", elapsedRealtimeNs)
    .put("wall_clock_ms", wallClockMs)
    .put("attributes", JSONObject(attributes))

private fun JSONObject.toVoiceTraceEvent(): VoiceTraceEvent {
    val rawAttributes = optJSONObject("attributes") ?: JSONObject()
    val attributes = buildMap {
        rawAttributes.keys().forEach { key -> put(key, rawAttributes.optString(key)) }
    }
    return VoiceTraceEvent(
        traceId = getString("trace_id"),
        sessionId = optString("session_id").ifBlank { getString("trace_id") },
        event = getString("event"),
        elapsedRealtimeNs = getLong("elapsed_realtime_ns"),
        wallClockMs = getLong("wall_clock_ms"),
        attributes = VoiceTracePrivacy.sanitizeAttributes(attributes)
    )
}

private fun VoiceDiagnosticSummary.toJson(): JSONObject = JSONObject()
    .put("trace_count", traceCount)
    .put("event_count", eventCount)
    .put("completed_count", completedCount)
    .put("cancelled_count", cancelledCount)
    .put("failed_count", failedCount)
    .put("success_rate", successRate)
    .put("cancellation_rate", cancellationRate)
    .put("failure_rate", failureRate)
    .put("fallback_rate", fallbackRate)
    .put("oom_count", oomCount)
    .put("native_crash_count", nativeCrashCount)
    .put("thermal_degrade_count", thermalDegradeCount)
    .put("model_verification_failure_count", modelVerificationFailureCount)
    .put("metrics", JSONObject().apply {
        metrics.forEach { (name, value) ->
            put(name, JSONObject()
                .put("count", value.count)
                .put("p50_ms", value.p50Ms)
                .put("p90_ms", value.p90Ms)
                .put("p95_ms", value.p95Ms)
                .put("p99_ms", value.p99Ms)
            )
        }
    })
