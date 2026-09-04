package com.galaxyssi.chat.voice.benchmark

import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

data class WhisperBenchmarkKey(
    val manufacturer: String,
    val device: String,
    val soc: String,
    val androidApi: Int,
    val appVersionCode: Int,
    val whisperNativeVersion: String,
    val nativeBuildFingerprint: String,
    val modelProfileId: String,
    val modelSha256: String,
    val benchmarkAudioVersion: String
) {
    init {
        require(manufacturer.isNotBlank())
        require(device.isNotBlank())
        require(soc.isNotBlank())
        require(androidApi > 0)
        require(appVersionCode > 0)
        require(whisperNativeVersion.isNotBlank())
        require(nativeBuildFingerprint.isNotBlank())
        require(modelProfileId.isNotBlank())
        require(SHA256.matches(modelSha256))
        require(benchmarkAudioVersion.isNotBlank())
    }

    val stableId: String
        get() = sha256(canonicalValue())

    fun toJson(): JSONObject = JSONObject()
        .put("manufacturer", manufacturer)
        .put("device", device)
        .put("soc", soc)
        .put("androidApi", androidApi)
        .put("appVersionCode", appVersionCode)
        .put("whisperNativeVersion", whisperNativeVersion)
        .put("nativeBuildFingerprint", nativeBuildFingerprint)
        .put("modelProfileId", modelProfileId)
        .put("modelSha256", modelSha256)
        .put("benchmarkAudioVersion", benchmarkAudioVersion)

    private fun canonicalValue(): String = listOf(
        manufacturer,
        device,
        soc,
        androidApi,
        appVersionCode,
        whisperNativeVersion,
        nativeBuildFingerprint,
        modelProfileId,
        modelSha256,
        benchmarkAudioVersion
    ).joinToString("\u001f")

    companion object {
        private val SHA256 = Regex("[0-9a-f]{64}")

        fun fromJson(value: JSONObject): WhisperBenchmarkKey = WhisperBenchmarkKey(
            manufacturer = value.getString("manufacturer"),
            device = value.getString("device"),
            soc = value.getString("soc"),
            androidApi = value.getInt("androidApi"),
            appVersionCode = value.getInt("appVersionCode"),
            whisperNativeVersion = value.getString("whisperNativeVersion"),
            nativeBuildFingerprint = value.getString("nativeBuildFingerprint"),
            modelProfileId = value.getString("modelProfileId"),
            modelSha256 = value.getString("modelSha256"),
            benchmarkAudioVersion = value.getString("benchmarkAudioVersion")
        )

        private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }
}

enum class WhisperBenchmarkLoadKind {
    COLD,
    HOT
}

data class WhisperBenchmarkMeasurement(
    val threadCount: Int,
    val loadKind: WhisperBenchmarkLoadKind,
    val audioDurationMs: Long,
    val decodeDurationMs: Long,
    val realTimeFactor: Double,
    val loadDurationMs: Long,
    val warmUpDurationMs: Long,
    val peakPssBytes: Long,
    val peakRssBytes: Long,
    val peakNativeAllocatedBytes: Long,
    val cpuTimeMs: Long,
    val energyDeltaNwh: Long?,
    val firstPartialLatencyMs: Long,
    val finalTailLatencyMs: Long,
    val batteryTemperatureStartCelsius: Double?,
    val batteryTemperatureEndCelsius: Double?,
    val thermalStatusStart: Int,
    val thermalStatusEnd: Int,
    val transcriptCorrect: Boolean
) {
    init {
        require(threadCount in 1..16)
        require(audioDurationMs > 0L)
        require(decodeDurationMs >= 0L)
        require(realTimeFactor.isFinite() && realTimeFactor >= 0.0)
        require(loadDurationMs >= 0L && warmUpDurationMs >= 0L)
        require(peakPssBytes >= 0L && peakRssBytes >= 0L && peakNativeAllocatedBytes >= 0L)
        require(cpuTimeMs >= 0L && (energyDeltaNwh == null || energyDeltaNwh >= 0L))
        require(firstPartialLatencyMs >= 0L && finalTailLatencyMs >= 0L)
        require(batteryTemperatureStartCelsius == null || batteryTemperatureStartCelsius.isFinite())
        require(batteryTemperatureEndCelsius == null || batteryTemperatureEndCelsius.isFinite())
    }

    fun toJson(): JSONObject = JSONObject()
        .put("threadCount", threadCount)
        .put("loadKind", loadKind.name)
        .put("audioDurationMs", audioDurationMs)
        .put("decodeDurationMs", decodeDurationMs)
        .put("realTimeFactor", realTimeFactor)
        .put("loadDurationMs", loadDurationMs)
        .put("warmUpDurationMs", warmUpDurationMs)
        .put("peakPssBytes", peakPssBytes)
        .put("peakRssBytes", peakRssBytes)
        .put("peakNativeAllocatedBytes", peakNativeAllocatedBytes)
        .put("cpuTimeMs", cpuTimeMs)
        .put("energyDeltaNwh", energyDeltaNwh)
        .put("firstPartialLatencyMs", firstPartialLatencyMs)
        .put("finalTailLatencyMs", finalTailLatencyMs)
        .put("batteryTemperatureStartCelsius", batteryTemperatureStartCelsius)
        .put("batteryTemperatureEndCelsius", batteryTemperatureEndCelsius)
        .put("thermalStatusStart", thermalStatusStart)
        .put("thermalStatusEnd", thermalStatusEnd)
        .put("transcriptCorrect", transcriptCorrect)

    companion object {
        fun fromJson(value: JSONObject): WhisperBenchmarkMeasurement = WhisperBenchmarkMeasurement(
            threadCount = value.getInt("threadCount"),
            loadKind = runCatching {
                enumValueOf<WhisperBenchmarkLoadKind>(value.optString("loadKind", "HOT"))
            }.getOrDefault(WhisperBenchmarkLoadKind.HOT),
            audioDurationMs = value.getLong("audioDurationMs"),
            decodeDurationMs = value.getLong("decodeDurationMs"),
            realTimeFactor = value.getDouble("realTimeFactor"),
            loadDurationMs = value.getLong("loadDurationMs"),
            warmUpDurationMs = value.getLong("warmUpDurationMs"),
            peakPssBytes = value.optLong("peakPssBytes", 0L),
            peakRssBytes = value.optLong("peakRssBytes", 0L),
            peakNativeAllocatedBytes = value.optLong("peakNativeAllocatedBytes", 0L),
            cpuTimeMs = value.optLong("cpuTimeMs", 0L),
            energyDeltaNwh = if (value.isNull("energyDeltaNwh")) null else value.optLong("energyDeltaNwh"),
            firstPartialLatencyMs = value.optLong("firstPartialLatencyMs", 0L),
            finalTailLatencyMs = value.optLong("finalTailLatencyMs", 0L),
            batteryTemperatureStartCelsius = value.optNullableDouble("batteryTemperatureStartCelsius"),
            batteryTemperatureEndCelsius = value.optNullableDouble("batteryTemperatureEndCelsius"),
            thermalStatusStart = value.optInt("thermalStatusStart", 0),
            thermalStatusEnd = value.optInt("thermalStatusEnd", 0),
            transcriptCorrect = value.optBoolean("transcriptCorrect", false)
        )
    }
}

private fun JSONObject.optNullableDouble(name: String): Double? =
    if (isNull(name) || !has(name)) null else optDouble(name).takeIf(Double::isFinite)

data class WhisperCertification(
    val key: WhisperBenchmarkKey,
    val level: WhisperCertificationLevel,
    val recommendedMode: WhisperExecutionMode,
    val recommendedThreadCount: Int,
    val recommendedPartialIntervalMs: Long,
    val warmRtfP50: Double,
    val warmRtfP95: Double,
    val loadTimeMsP95: Long,
    val peakPssBytes: Long,
    val maxThermalStatus: Int,
    val abortLatencyMsP95: Long,
    val createdAtEpochMs: Long,
    val failureReason: String?
) {
    init {
        require(recommendedThreadCount in 1..16)
        require(recommendedPartialIntervalMs >= 0L)
        require(warmRtfP50.isFinite() && warmRtfP50 >= 0.0)
        require(warmRtfP95.isFinite() && warmRtfP95 >= warmRtfP50)
        require(loadTimeMsP95 >= 0L && peakPssBytes >= 0L && abortLatencyMsP95 >= 0L)
        require(createdAtEpochMs > 0L)
        require(failureReason == null || failureReason.length <= 512)
    }

    val realtimeCertified: Boolean
        get() = level == WhisperCertificationLevel.REALTIME &&
            recommendedMode == WhisperExecutionMode.REALTIME_PARTIAL

    val remoteRecommended: Boolean
        get() = level == WhisperCertificationLevel.REMOTE_RECOMMENDED &&
            recommendedMode == WhisperExecutionMode.REMOTE_NODE

    fun toJson(): JSONObject = JSONObject()
        .put("key", key.toJson())
        .put("level", level.name)
        .put("recommendedMode", recommendedMode.name)
        .put("recommendedThreadCount", recommendedThreadCount)
        .put("recommendedPartialIntervalMs", recommendedPartialIntervalMs)
        .put("warmRtfP50", warmRtfP50)
        .put("warmRtfP95", warmRtfP95)
        .put("loadTimeMsP95", loadTimeMsP95)
        .put("peakPssBytes", peakPssBytes)
        .put("maxThermalStatus", maxThermalStatus)
        .put("abortLatencyMsP95", abortLatencyMsP95)
        .put("createdAtEpochMs", createdAtEpochMs)
        .put("failureReason", failureReason)

    companion object {
        fun fromJson(value: JSONObject): WhisperCertification = WhisperCertification(
            key = WhisperBenchmarkKey.fromJson(value.getJSONObject("key")),
            level = enumValueOf(value.getString("level")),
            recommendedMode = enumValueOf(value.getString("recommendedMode")),
            recommendedThreadCount = value.getInt("recommendedThreadCount"),
            recommendedPartialIntervalMs = value.getLong("recommendedPartialIntervalMs"),
            warmRtfP50 = value.getDouble("warmRtfP50"),
            warmRtfP95 = value.getDouble("warmRtfP95"),
            loadTimeMsP95 = value.getLong("loadTimeMsP95"),
            peakPssBytes = value.getLong("peakPssBytes"),
            maxThermalStatus = value.getInt("maxThermalStatus"),
            abortLatencyMsP95 = value.getLong("abortLatencyMsP95"),
            createdAtEpochMs = value.getLong("createdAtEpochMs"),
            failureReason = if (value.isNull("failureReason")) {
                null
            } else {
                value.optString("failureReason", "").takeIf(String::isNotBlank)
            }
        )
    }
}

data class WhisperBenchmarkRecord(
    val certification: WhisperCertification,
    val measurements: List<WhisperBenchmarkMeasurement>,
    val verificationDurationMs: Long,
    val abortLatenciesMs: List<Long>,
    val highPerformanceCoreCount: Int,
    val threadCandidates: List<Int>
) {
    init {
        require(measurements.size <= MAX_MEASUREMENTS)
        require(verificationDurationMs >= 0L)
        require(abortLatenciesMs.size <= MAX_ABORT_SAMPLES && abortLatenciesMs.all { it >= 0L })
        require(highPerformanceCoreCount > 0)
        require(threadCandidates.isNotEmpty() && threadCandidates.all { it in 1..16 })
    }

    fun toJson(): JSONObject = JSONObject()
        .put("certification", certification.toJson())
        .put("measurements", JSONArray().apply { measurements.forEach { put(it.toJson()) } })
        .put("verificationDurationMs", verificationDurationMs)
        .put("abortLatenciesMs", JSONArray().apply { abortLatenciesMs.forEach(::put) })
        .put("highPerformanceCoreCount", highPerformanceCoreCount)
        .put("threadCandidates", JSONArray().apply { threadCandidates.forEach(::put) })

    companion object {
        private const val MAX_MEASUREMENTS = 256
        private const val MAX_ABORT_SAMPLES = 16

        fun fromJson(value: JSONObject): WhisperBenchmarkRecord {
            val values = value.optJSONArray("measurements") ?: JSONArray()
            val abortValues = value.optJSONArray("abortLatenciesMs") ?: JSONArray()
            val candidateValues = value.optJSONArray("threadCandidates") ?: JSONArray()
            return WhisperBenchmarkRecord(
                certification = WhisperCertification.fromJson(value.getJSONObject("certification")),
                measurements = buildList {
                    repeat(values.length().coerceAtMost(MAX_MEASUREMENTS)) { index ->
                        add(WhisperBenchmarkMeasurement.fromJson(values.getJSONObject(index)))
                    }
                },
                verificationDurationMs = value.optLong("verificationDurationMs", 0L),
                abortLatenciesMs = buildList {
                    repeat(abortValues.length().coerceAtMost(MAX_ABORT_SAMPLES)) { index ->
                        add(abortValues.getLong(index).coerceAtLeast(0L))
                    }
                },
                highPerformanceCoreCount = value.optInt("highPerformanceCoreCount", 1).coerceAtLeast(1),
                threadCandidates = buildList {
                    repeat(candidateValues.length()) { index ->
                        candidateValues.optInt(index).takeIf { it in 1..16 }?.let(::add)
                    }
                }.ifEmpty { listOf(1) }
            )
        }
    }
}

internal fun percentile(values: List<Double>, percentile: Double): Double {
    if (values.isEmpty()) return 0.0
    val sorted = values.sorted()
    val index = ((sorted.lastIndex * percentile.coerceIn(0.0, 1.0)) + 0.5).toInt()
        .coerceIn(0, sorted.lastIndex)
    return sorted[index]
}

internal fun percentileLong(values: List<Long>, percentile: Double): Long {
    if (values.isEmpty()) return 0L
    val sorted = values.sorted()
    val index = ((sorted.lastIndex * percentile.coerceIn(0.0, 1.0)) + 0.5).toInt()
        .coerceIn(0, sorted.lastIndex)
    return sorted[index]
}
