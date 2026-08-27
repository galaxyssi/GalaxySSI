package com.signalasi.chat.voice.audio

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Process
import android.os.SystemClock
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt

internal data class PeerVoiceOpusResult(
    val encodedOggOpus: ByteArray,
    val durationMillis: Long,
    val measuredLufs: Double?,
    val appliedGainDb: Double,
    val noiseSuppressorEnabled: Boolean,
    val echoCancelerEnabled: Boolean
)

internal class PeerVoiceOpusRecorder(context: Context) {
    private val appContext = context.applicationContext
    private val running = AtomicBoolean(false)
    private val currentPeak = AtomicInteger(0)
    private val samples = ShortArray(PeerVoiceMessageAudio.SAMPLE_RATE_HZ * MAX_DURATION_SECONDS)
    private var sampleCount = 0
    private var audioRecord: AudioRecord? = null
    private var captureThread: Thread? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var gainControl: AutomaticGainControl? = null
    private var noiseSuppressorWasEnabled = false
    private var echoCancelerWasEnabled = false
    private var terminalFailure: Throwable? = null

    @SuppressLint("MissingPermission")
    fun start() {
        check(appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            "Microphone permission is required"
        }
        check(!running.get()) { "Peer voice recording is already active" }
        val minBuffer = AudioRecord.getMinBufferSize(
            PeerVoiceMessageAudio.SAMPLE_RATE_HZ,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        check(minBuffer > 0) { "48 kHz mono PCM capture is unavailable" }
        val manager = appContext.getSystemService(AudioManager::class.java)
        val speakerPlayback = speakerPlaybackActive(manager)
        val source = if (speakerPlayback) {
            MediaRecorder.AudioSource.VOICE_COMMUNICATION
        } else {
            MediaRecorder.AudioSource.VOICE_RECOGNITION
        }
        val record = AudioRecord.Builder()
            .setAudioSource(source)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(PeerVoiceMessageAudio.SAMPLE_RATE_HZ)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(minBuffer, PeerVoiceMessageAudio.SAMPLE_RATE_HZ / 2))
            .build()
        check(record.state == AudioRecord.STATE_INITIALIZED) {
            record.release()
            "Peer voice recorder could not initialize"
        }
        configureEffects(record.audioSessionId, speakerPlayback)
        try {
            record.startRecording()
            check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                "Peer voice recorder could not start"
            }
        } catch (error: Throwable) {
            releaseEffects()
            record.release()
            throw error
        }
        sampleCount = 0
        terminalFailure = null
        currentPeak.set(0)
        audioRecord = record
        running.set(true)
        captureThread = thread(name = "signalasi-peer-opus-capture", start = true) {
            capture(record)
        }
    }

    fun currentAmplitude(): Int = currentPeak.get()

    fun stopAndEncode(): PeerVoiceOpusResult {
        stopCapture()
        terminalFailure?.let { throw it }
        val count = sampleCount
        require(count > 0) { "Peer voice recording is empty" }
        return try {
            val dsp = PeerVoiceDsp.processInPlace(samples, count)
            val encoded = PeerVoiceOpusEncoder.encode(samples, count)
            PeerVoiceOpusResult(
                encodedOggOpus = encoded,
                durationMillis = count.toLong() * 1_000L / PeerVoiceMessageAudio.SAMPLE_RATE_HZ,
                measuredLufs = dsp.measuredLufs,
                appliedGainDb = dsp.appliedGainDb,
                noiseSuppressorEnabled = noiseSuppressorWasEnabled,
                echoCancelerEnabled = echoCancelerWasEnabled
            )
        } finally {
            samples.fill(0)
            sampleCount = 0
        }
    }

    fun cancel() {
        stopCapture()
        samples.fill(0)
        sampleCount = 0
    }

    private fun capture(record: AudioRecord) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        val frameSamples = PeerVoiceMessageAudio.SAMPLE_RATE_HZ * FRAME_MILLIS / 1_000
        try {
            while (running.get() && sampleCount < samples.size) {
                val requested = minOf(frameSamples, samples.size - sampleCount)
                val read = record.read(samples, sampleCount, requested, AudioRecord.READ_BLOCKING)
                when {
                    read > 0 -> {
                        var peak = 0
                        repeat(read) { index ->
                            peak = maxOf(peak, abs(samples[sampleCount + index].toInt()))
                        }
                        currentPeak.set(peak)
                        sampleCount += read
                    }
                    read == 0 -> Unit
                    !running.get() -> Unit
                    else -> error("Peer voice PCM capture failed with code $read")
                }
            }
        } catch (error: Throwable) {
            if (running.get()) terminalFailure = error
        } finally {
            running.set(false)
            currentPeak.set(0)
            runCatching {
                if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) record.stop()
            }
            releaseEffects()
            record.release()
            audioRecord = null
            captureThread = null
        }
    }

    private fun stopCapture() {
        running.set(false)
        runCatching { audioRecord?.stop() }
        captureThread?.join(STOP_JOIN_MILLIS)
        if (captureThread?.isAlive == true) {
            runCatching { audioRecord?.release() }
            captureThread?.join(STOP_FORCE_JOIN_MILLIS)
        }
    }

    private fun configureEffects(sessionId: Int, speakerPlayback: Boolean) {
        noiseSuppressor = if (NoiseSuppressor.isAvailable()) {
            runCatching { NoiseSuppressor.create(sessionId)?.apply { enabled = true } }.getOrNull()
        } else null
        noiseSuppressorWasEnabled = noiseSuppressor?.enabled == true
        echoCanceler = if (speakerPlayback && AcousticEchoCanceler.isAvailable()) {
            runCatching { AcousticEchoCanceler.create(sessionId)?.apply { enabled = true } }.getOrNull()
        } else null
        echoCancelerWasEnabled = echoCanceler?.enabled == true
        gainControl = if (AutomaticGainControl.isAvailable()) {
            runCatching { AutomaticGainControl.create(sessionId)?.apply { enabled = false } }.getOrNull()
        } else null
    }

    private fun releaseEffects() {
        runCatching { noiseSuppressor?.release() }
        runCatching { echoCanceler?.release() }
        runCatching { gainControl?.release() }
        noiseSuppressor = null
        echoCanceler = null
        gainControl = null
    }

    @Suppress("DEPRECATION")
    private fun speakerPlaybackActive(manager: AudioManager?): Boolean {
        manager ?: return false
        if (!manager.isMusicActive && manager.mode == AudioManager.MODE_NORMAL) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.communicationDevice?.type == android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
        } else {
            manager.isSpeakerphoneOn
        }
    }

    private companion object {
        const val FRAME_MILLIS = 20
        const val MAX_DURATION_SECONDS = 60
        const val STOP_JOIN_MILLIS = 1_000L
        const val STOP_FORCE_JOIN_MILLIS = 500L
    }
}

internal data class PeerVoiceDspResult(
    val measuredLufs: Double?,
    val appliedGainDb: Double,
    val outputPeakDbfs: Double
)

internal object PeerVoiceDsp {
    private const val ABSOLUTE_GATE_LUFS = -70.0
    private const val RELATIVE_GATE_LU = 10.0
    private const val LOUDNESS_OFFSET = -0.691

    fun processInPlace(samples: ShortArray, count: Int): PeerVoiceDspResult {
        require(count in 1..samples.size)
        applyHighPass(samples, count, PeerVoiceMessageAudio.HIGH_PASS_HZ.toDouble())
        val measured = integratedLufs(samples, count)
        val requestedGainDb = measured?.let { PeerVoiceMessageAudio.TARGET_LUFS - it } ?: 0.0
        val requestedGain = 10.0.pow(requestedGainDb / 20.0)
        var peak = 0
        repeat(count) { index -> peak = maxOf(peak, abs(samples[index].toInt())) }
        val peakLimit = Short.MAX_VALUE * 10.0.pow(PeerVoiceMessageAudio.PEAK_DBFS / 20.0)
        val peakSafeGain = if (peak > 0) peakLimit / peak else requestedGain
        val appliedGain = minOf(requestedGain, peakSafeGain).coerceAtLeast(0.0)
        var outputPeak = 0
        repeat(count) { index ->
            val value = (samples[index] * appliedGain)
                .roundToInt()
                .coerceIn(-peakLimit.toInt(), peakLimit.toInt())
            samples[index] = value.toShort()
            outputPeak = maxOf(outputPeak, abs(value))
        }
        return PeerVoiceDspResult(
            measuredLufs = measured,
            appliedGainDb = if (appliedGain > 0.0) 20.0 * log10(appliedGain) else -120.0,
            outputPeakDbfs = if (outputPeak > 0) {
                20.0 * log10(outputPeak / Short.MAX_VALUE.toDouble())
            } else {
                -120.0
            }
        )
    }

    internal fun applyHighPass(samples: ShortArray, count: Int, cutoffHz: Double) {
        val dt = 1.0 / PeerVoiceMessageAudio.SAMPLE_RATE_HZ
        val rc = 1.0 / (2.0 * PI * cutoffHz)
        val alpha = rc / (rc + dt)
        var previousInput = 0.0
        var previousOutput = 0.0
        repeat(count) { index ->
            val input = samples[index].toDouble()
            val output = alpha * (previousOutput + input - previousInput)
            samples[index] = output.roundToInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
            previousInput = input
            previousOutput = output
        }
    }

    internal fun integratedLufs(samples: ShortArray, count: Int): Double? {
        val blockSamples = PeerVoiceMessageAudio.SAMPLE_RATE_HZ * 400 / 1_000
        val stepSamples = PeerVoiceMessageAudio.SAMPLE_RATE_HZ * 100 / 1_000
        if (count < blockSamples) return ungatedLufs(samples, count)
        val energies = ArrayList<Double>((count - blockSamples) / stepSamples + 1)
        val weightedSquares = DoubleArray(blockSamples)
        val shelf = Biquad(
            1.53512485958697,
            -2.69169618940638,
            1.19839281085285,
            -1.69065929318241,
            0.73248077421585
        )
        val highPass = Biquad(
            1.0,
            -2.0,
            1.0,
            -1.99004745483398,
            0.99007225036621
        )
        var windowSum = 0.0
        repeat(count) { index ->
            val normalized = samples[index] / Short.MAX_VALUE.toDouble()
            val weighted = highPass.process(shelf.process(normalized))
            val square = weighted * weighted
            val slot = index % blockSamples
            windowSum -= weightedSquares[slot]
            weightedSquares[slot] = square
            windowSum += square
            if (index + 1 >= blockSamples && (index + 1 - blockSamples) % stepSamples == 0) {
                energies += (windowSum / blockSamples).coerceAtLeast(0.0)
            }
        }
        weightedSquares.fill(0.0)
        val absolute = energies.filter { energy -> loudness(energy) > ABSOLUTE_GATE_LUFS }
        if (absolute.isEmpty()) return null
        val preliminary = loudness(absolute.average())
        val relativeThreshold = preliminary - RELATIVE_GATE_LU
        val gated = absolute.filter { energy -> loudness(energy) > relativeThreshold }
        return gated.takeIf(List<Double>::isNotEmpty)?.average()?.let(::loudness)
    }

    private fun ungatedLufs(samples: ShortArray, count: Int): Double? {
        var sum = 0.0
        repeat(count) { index ->
            val normalized = samples[index] / Short.MAX_VALUE.toDouble()
            sum += normalized * normalized
        }
        val energy = sum / count
        return loudness(energy).takeIf { it > ABSOLUTE_GATE_LUFS }
    }

    private fun loudness(energy: Double): Double =
        if (energy <= 0.0) -120.0 else LOUDNESS_OFFSET + 10.0 * log10(energy)

    private class Biquad(
        private val b0: Double,
        private val b1: Double,
        private val b2: Double,
        private val a1: Double,
        private val a2: Double
    ) {
        private var x1 = 0.0
        private var x2 = 0.0
        private var y1 = 0.0
        private var y2 = 0.0

        fun process(input: Double): Double {
            val output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = input
            y2 = y1
            y1 = output
            return output
        }
    }
}

internal object PeerVoiceOpusEncoder {
    private const val MIME = MediaFormat.MIMETYPE_AUDIO_OPUS
    private const val FRAME_SAMPLES = 960
    private const val DEQUEUE_TIMEOUT_US = 10_000L
    private const val ENCODE_TIMEOUT_MILLIS = 15_000L

    fun isAvailable(): Boolean = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
        info.isEncoder && info.supportedTypes.any { it.equals(MIME, ignoreCase = true) }
    }

    fun encode(samples: ShortArray, count: Int): ByteArray {
        require(count in 1..samples.size)
        check(isAvailable()) { "This device does not provide an Opus encoder" }
        val codec = MediaCodec.createEncoderByType(MIME)
        val packets = mutableListOf<OpusPacket>()
        var opusHead: ByteArray? = null
        try {
            val format = MediaFormat.createAudioFormat(
                MIME,
                PeerVoiceMessageAudio.SAMPLE_RATE_HZ,
                PeerVoiceMessageAudio.CHANNEL_COUNT
            ).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, PeerVoiceMessageAudio.OPUS_BIT_RATE_BPS)
                setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR)
                setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, FRAME_SAMPLES * 2)
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var inputOffset = 0
            var inputEnded = false
            var outputEnded = false
            val startedAt = SystemClock.elapsedRealtime()
            while (!outputEnded) {
                check(SystemClock.elapsedRealtime() - startedAt < ENCODE_TIMEOUT_MILLIS) {
                    "Opus encoding timed out"
                }
                if (!inputEnded) {
                    val inputIndex = codec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                    if (inputIndex >= 0) {
                        val input = requireNotNull(codec.getInputBuffer(inputIndex)).apply {
                            clear()
                            order(ByteOrder.LITTLE_ENDIAN)
                        }
                        if (inputOffset < count) {
                            val frameCount = minOf(FRAME_SAMPLES, count - inputOffset)
                            repeat(frameCount) { index -> input.putShort(samples[inputOffset + index]) }
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                frameCount * 2,
                                inputOffset.toLong() * 1_000_000L / PeerVoiceMessageAudio.SAMPLE_RATE_HZ,
                                0
                            )
                            inputOffset += frameCount
                        } else {
                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                inputOffset.toLong() * 1_000_000L / PeerVoiceMessageAudio.SAMPLE_RATE_HZ,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputEnded = true
                        }
                    }
                }
                when (val outputIndex = codec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        opusHead = codec.outputFormat.getByteBuffer("csd-0")?.copyRemaining()
                    }
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    else -> if (outputIndex >= 0) {
                        val output = codec.getOutputBuffer(outputIndex)
                        if (info.size > 0 && output != null) {
                            output.position(info.offset)
                            output.limit(info.offset + info.size)
                            val data = ByteArray(info.size).also(output::get)
                            if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                                opusHead?.fill(0)
                                opusHead = data
                            } else {
                                packets += OpusPacket(data)
                            }
                        }
                        outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        codec.releaseOutputBuffer(outputIndex, false)
                    }
                }
            }
        } finally {
            runCatching { codec.stop() }
            codec.release()
        }
        require(packets.isNotEmpty()) { "Opus encoder produced no audio" }
        return try {
            OggOpusWriter.write(packets, count, opusHead)
        } finally {
            opusHead?.fill(0)
            packets.forEach { it.data.fill(0) }
        }
    }

    private fun ByteBuffer.copyRemaining(): ByteArray {
        val copy = duplicate()
        return ByteArray(copy.remaining()).also(copy::get)
    }
}

internal data class OpusPacket(val data: ByteArray)

internal object OggOpusWriter {
    private const val PRE_SKIP = 312
    private const val PACKETS_PER_PAGE = 20
    private val random = SecureRandom()

    fun write(packets: List<OpusPacket>, inputSampleCount: Int, codecHead: ByteArray?): ByteArray {
        val sink = WipeableByteSink()
        val serial = random.nextInt()
        var sequence = 0
        val head = validOpusHead(codecHead) ?: defaultOpusHead()
        try {
            writePage(sink, serial, sequence++, 0L, 0x02, listOf(head))
            writePage(sink, serial, sequence++, 0L, 0x00, listOf(opusTags()))
            var consumedSamples = 0L
            packets.chunked(PACKETS_PER_PAGE).forEachIndexed { pageIndex, pagePackets ->
                val remaining = (inputSampleCount - consumedSamples).coerceAtLeast(0L)
                val pageSamples = minOf(
                    remaining,
                    pagePackets.size.toLong() * 960L
                )
                consumedSamples += pageSamples
                val isLast = pageIndex == (packets.size - 1) / PACKETS_PER_PAGE
                writePage(
                    sink,
                    serial,
                    sequence++,
                    PRE_SKIP + consumedSamples,
                    if (isLast) 0x04 else 0x00,
                    pagePackets.map(OpusPacket::data)
                )
            }
            return sink.toByteArrayAndWipe()
        } finally {
            if (head !== codecHead) head.fill(0)
            sink.wipe()
        }
    }

    private fun writePage(
        sink: WipeableByteSink,
        serial: Int,
        sequence: Int,
        granulePosition: Long,
        headerType: Int,
        packets: List<ByteArray>
    ) {
        val lacing = ArrayList<Int>()
        packets.forEach { packet ->
            var remaining = packet.size
            while (remaining >= 255) {
                lacing += 255
                remaining -= 255
            }
            lacing += remaining
        }
        require(lacing.size <= 255) { "Ogg page contains too many segments" }
        val pageSize = 27 + lacing.size + packets.sumOf(ByteArray::size)
        val page = ByteArray(pageSize)
        var offset = 0
        "OggS".toByteArray(Charsets.US_ASCII).copyInto(page, offset).also { offset += 4 }
        page[offset++] = 0
        page[offset++] = headerType.toByte()
        writeLongLe(page, offset, granulePosition).also { offset += 8 }
        writeIntLe(page, offset, serial).also { offset += 4 }
        writeIntLe(page, offset, sequence).also { offset += 4 }
        offset += 4
        page[offset++] = lacing.size.toByte()
        lacing.forEach { page[offset++] = it.toByte() }
        packets.forEach { packet ->
            packet.copyInto(page, offset)
            offset += packet.size
        }
        writeIntLe(page, 22, oggCrc(page))
        sink.write(page)
        page.fill(0)
    }

    private fun validOpusHead(candidate: ByteArray?): ByteArray? = candidate?.takeIf { bytes ->
        val signature = "OpusHead".toByteArray(Charsets.US_ASCII)
        bytes.size >= 19 && signature.indices.all { index -> bytes[index] == signature[index] }
    }

    private fun defaultOpusHead(): ByteArray = ByteArray(19).also { head ->
        "OpusHead".toByteArray(Charsets.US_ASCII).copyInto(head)
        head[8] = 1
        head[9] = PeerVoiceMessageAudio.CHANNEL_COUNT.toByte()
        head[10] = (PRE_SKIP and 0xff).toByte()
        head[11] = (PRE_SKIP ushr 8).toByte()
        writeIntLe(head, 12, PeerVoiceMessageAudio.SAMPLE_RATE_HZ)
    }

    private fun opusTags(): ByteArray {
        val vendor = "SignalASI".toByteArray(Charsets.UTF_8)
        return ByteArray(8 + 4 + vendor.size + 4).also { tags ->
            "OpusTags".toByteArray(Charsets.US_ASCII).copyInto(tags)
            writeIntLe(tags, 8, vendor.size)
            vendor.copyInto(tags, 12)
            writeIntLe(tags, 12 + vendor.size, 0)
            vendor.fill(0)
        }
    }

    private fun oggCrc(bytes: ByteArray): Int {
        var crc = 0
        bytes.forEach { value ->
            crc = crc xor ((value.toInt() and 0xff) shl 24)
            repeat(8) {
                crc = if (crc and Int.MIN_VALUE != 0) (crc shl 1) xor 0x04c11db7 else crc shl 1
            }
        }
        return crc
    }

    private fun writeIntLe(target: ByteArray, offset: Int, value: Int) {
        repeat(4) { index -> target[offset + index] = (value ushr (index * 8)).toByte() }
    }

    private fun writeLongLe(target: ByteArray, offset: Int, value: Long) {
        repeat(8) { index -> target[offset + index] = (value ushr (index * 8)).toByte() }
    }
}

private class WipeableByteSink(initialCapacity: Int = 8 * 1024) {
    private var buffer = ByteArray(initialCapacity)
    private var size = 0

    fun write(bytes: ByteArray) {
        ensureCapacity(size + bytes.size)
        bytes.copyInto(buffer, size)
        size += bytes.size
    }

    fun toByteArrayAndWipe(): ByteArray = buffer.copyOf(size).also { wipe() }

    fun wipe() {
        buffer.fill(0)
        size = 0
    }

    private fun ensureCapacity(required: Int) {
        if (required <= buffer.size) return
        val expanded = ByteArray(maxOf(required, buffer.size * 2))
        buffer.copyInto(expanded, endIndex = size)
        buffer.fill(0)
        buffer = expanded
    }
}
