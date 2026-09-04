package com.galaxyssi.chat.voice.audio

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.math.abs

class AndroidPcmRecorder(context: Context) : PcmRecorder {
    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(AudioManager::class.java)
    private val lock = Any()
    private val running = AtomicBoolean(false)
    @Volatile private var state = PcmRecorderState()
    @Volatile private var activeRecord: AudioRecord? = null
    @Volatile private var captureThread: Thread? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var gainControl: AutomaticGainControl? = null
    private var recordingCallback: AudioManager.AudioRecordingCallback? = null
    @Volatile private var terminalFailure: Throwable? = null

    @SuppressLint("MissingPermission")
    override suspend fun start(config: PcmCaptureConfig): Flow<AudioFrame> = withContext(Dispatchers.IO) {
        synchronized(lock) {
            check(state.phase !in setOf(PcmRecorderPhase.STARTING, PcmRecorderPhase.RECORDING, PcmRecorderPhase.STOPPING)) {
                "PCM recorder is already active"
            }
            if (appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                throw PcmCaptureException("microphone_permission_denied", "Microphone permission is required")
            }
            state = PcmRecorderState(phase = PcmRecorderPhase.STARTING)
            terminalFailure = null
        }

        val framePool = PcmFramePool(config.samplesPerFrame, config.framePoolSize)
        val channel = Channel<AudioFrame>(
            capacity = config.outputQueueCapacity,
            onUndeliveredElement = AudioFrame::close
        )
        val opened = try {
            openAudioRecord(config)
        } catch (error: Throwable) {
            state = state.copy(
                phase = PcmRecorderPhase.FAILED,
                stopReason = PcmStopReason.CAPTURE_FAILURE,
                errorCode = (error as? PcmCaptureException)?.code ?: error.javaClass.simpleName
            )
            channel.close(error)
            throw error
        }
        val record = opened.record
        val route = routeLabel(record.routedDevice)
        try {
            activeRecord = record
            configureEffects(record.audioSessionId, config)
            registerSilenceMonitor(record.audioSessionId)
        } catch (error: Throwable) {
            unregisterSilenceMonitor()
            releaseEffects()
            runCatching { record.stop() }
            record.release()
            activeRecord = null
            state = state.copy(
                phase = PcmRecorderPhase.FAILED,
                stopReason = PcmStopReason.CAPTURE_FAILURE,
                errorCode = error.javaClass.simpleName
            )
            channel.close(error)
            throw error
        }
        running.set(true)
        state = PcmRecorderState(
            phase = PcmRecorderPhase.RECORDING,
            audioSource = opened.audioSource,
            audioSessionId = record.audioSessionId,
            inputRoute = route,
            captureSampleRateHz = opened.captureSampleRateHz,
            outputSampleRateHz = config.sampleRateHz
        )
        captureThread = thread(start = true, name = "galaxyssi-pcm-capture") {
            captureLoop(record, opened.captureSampleRateHz, config, framePool, channel)
        }
        channel.receiveAsFlow()
    }

    override fun requestStop(reason: PcmStopReason) {
        val record = synchronized(lock) {
            if (state.phase !in setOf(PcmRecorderPhase.STARTING, PcmRecorderPhase.RECORDING)) return
            state = state.copy(phase = PcmRecorderPhase.STOPPING, stopReason = reason)
            running.set(false)
            activeRecord
        }
        runCatching { record?.stop() }
    }

    override suspend fun stop(reason: PcmStopReason) = withContext(Dispatchers.IO) {
        requestStop(reason)
        captureThread?.join(STOP_JOIN_TIMEOUT_MS)
        if (captureThread?.isAlive == true) {
            runCatching { activeRecord?.release() }
            captureThread?.join(STOP_FORCE_JOIN_TIMEOUT_MS)
        }
    }

    override fun currentState(): PcmRecorderState = state

    @SuppressLint("MissingPermission")
    private fun openAudioRecord(config: PcmCaptureConfig): OpenedAudioRecord {
        var lastFailure: Throwable? = null
        for (source in config.preferredAudioSources.distinct()) {
            for (requestedRate in config.captureSampleRateCandidates()) {
                val minBuffer = AudioRecord.getMinBufferSize(
                    requestedRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                if (minBuffer <= 0) {
                    lastFailure = PcmCaptureException(
                        "unsupported_audio_format",
                        "$requestedRate Hz mono PCM capture is unavailable"
                    )
                    continue
                }
                val candidate = try {
                    AudioRecord.Builder()
                        .setAudioSource(source)
                        .setAudioFormat(
                            AudioFormat.Builder()
                                .setSampleRate(requestedRate)
                                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                                .build()
                        )
                        .setBufferSizeInBytes(maxOf(
                            minBuffer,
                            requestedRate * PCM16_BYTES_PER_SAMPLE * config.audioRecordBufferMs / 1_000
                        ))
                        .build()
                } catch (error: Throwable) {
                    lastFailure = error
                    continue
                }
                if (candidate.state != AudioRecord.STATE_INITIALIZED) {
                    candidate.release()
                    lastFailure = PcmCaptureException(
                        "audio_record_uninitialized",
                        "AudioRecord initialization failed"
                    )
                    continue
                }
                val actualRate = candidate.sampleRate
                if (actualRate !in config.captureSampleRateCandidates()) {
                    candidate.release()
                    lastFailure = PcmCaptureException(
                        "unsupported_capture_rate",
                        "AudioRecord selected unsupported sample rate $actualRate Hz"
                    )
                    continue
                }
                val started = runCatching {
                    candidate.startRecording()
                    candidate.recordingState == AudioRecord.RECORDSTATE_RECORDING
                }.getOrElse {
                    lastFailure = it
                    false
                }
                if (started) return OpenedAudioRecord(candidate, source, actualRate)
                candidate.release()
            }
        }
        throw PcmCaptureException(
            "audio_record_start_failed",
            "No compatible microphone input source could start",
            lastFailure
        )
    }

    private fun captureLoop(
        record: AudioRecord,
        captureSampleRateHz: Int,
        config: PcmCaptureConfig,
        pool: PcmFramePool,
        channel: Channel<AudioFrame>
    ) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
        val captureSamplesPerFrame = config.captureSamplesPerFrame(captureSampleRateHz)
        val captureBuffer = if (captureSampleRateHz == config.sampleRateHz) null else {
            ByteBuffer.allocateDirect(captureSamplesPerFrame * PCM16_BYTES_PER_SAMPLE)
                .order(ByteOrder.LITTLE_ENDIAN)
        }
        var resampler: NativePcm16Resampler? = null
        val discardBuffer = PcmFrameStorage(
            samples = ShortArray(config.samplesPerFrame),
            pcm16 = ByteBuffer.allocateDirect(config.samplesPerFrame * PCM16_BYTES_PER_SAMPLE)
                .order(ByteOrder.LITTLE_ENDIAN)
        )
        var sequence = 0L
        var capturedSamples = 0L
        var shortReads = 0L
        var zeroReads = 0L
        var droppedFrames = 0L
        var suspectedOverruns = 0L
        var routeChanges = 0L
        var route = routeLabel(record.routedDevice)
        var lastFrameAtNs = 0L
        var failure: Throwable? = null
        try {
            if (captureSampleRateHz != config.sampleRateHz) {
                resampler = NativePcm16Resampler.open(captureSampleRateHz)
            }
            while (running.get()) {
                val pooled = pool.acquire()
                val target = pooled ?: discardBuffer
                val input = captureBuffer ?: target.pcm16
                input.clear()
                val bytesRead = record.read(
                    input,
                    captureSamplesPerFrame * PCM16_BYTES_PER_SAMPLE,
                    AudioRecord.READ_BLOCKING
                )
                val capturedAtNs = SystemClock.elapsedRealtimeNanos()
                when {
                    bytesRead > 0 -> {
                        if (bytesRead % PCM16_BYTES_PER_SAMPLE != 0) {
                            pooled?.let(pool::release)
                            throw PcmCaptureException("unaligned_pcm_read", "AudioRecord returned incomplete PCM16 data")
                        }
                        val capturedInputSamples = bytesRead / PCM16_BYTES_PER_SAMPLE
                        input.position(0)
                        input.limit(bytesRead)
                        val activeResampler = resampler
                        val read = if (activeResampler == null) {
                            capturedInputSamples
                        } else {
                            target.pcm16.clear()
                            activeResampler.process(
                                input,
                                capturedInputSamples,
                                target.pcm16,
                                config.samplesPerFrame
                            )
                        }
                        if (read == 0) {
                            pooled?.let(pool::release)
                            zeroReads += 1
                            continue
                        }
                        target.pcm16.position(0)
                        target.pcm16.limit(read * PCM16_BYTES_PER_SAMPLE)
                        target.pcm16.duplicate()
                            .order(ByteOrder.LITTLE_ENDIAN)
                            .asShortBuffer()
                            .get(target.samples, 0, read)
                        if (capturedInputSamples < captureSamplesPerFrame || read < config.samplesPerFrame) {
                            shortReads += 1
                        }
                        if (lastFrameAtNs > 0L && capturedAtNs - lastFrameAtNs > config.frameDurationMs * 3_000_000L) {
                            suspectedOverruns += 1
                        }
                        lastFrameAtNs = capturedAtNs
                        capturedSamples += read
                        val peak = peakAmplitude(target.samples, read)
                        if (pooled == null) {
                            droppedFrames += 1
                        } else {
                            val frame = AudioFrame(
                                sequence = sequence++,
                                captureTimeNanos = capturedAtNs,
                                samples = pooled.samples,
                                validSamples = read,
                                releaseAction = { pool.release(pooled) },
                                directPcm16 = pooled.pcm16
                            )
                            if (channel.trySend(frame).isFailure) {
                                val stale = channel.tryReceive().getOrNull()
                                if (stale != null) {
                                    stale.close()
                                    droppedFrames += 1
                                }
                                if (channel.trySend(frame).isFailure) {
                                    frame.close()
                                    droppedFrames += 1
                                }
                            }
                        }
                        if (sequence % ROUTE_CHECK_FRAME_INTERVAL == 0L) {
                            val nextRoute = routeLabel(record.routedDevice)
                            if (nextRoute != route) {
                                route = nextRoute
                                routeChanges += 1
                            }
                        }
                        state = state.copy(
                            inputRoute = route,
                            currentAmplitude = peak,
                            capturedSamples = capturedSamples,
                            diagnostics = PcmRecorderDiagnostics(
                                shortReadCount = shortReads,
                                zeroReadCount = zeroReads,
                                droppedFrameCount = droppedFrames,
                                suspectedOverrunCount = suspectedOverruns,
                                inputRouteChangeCount = routeChanges
                            )
                        )
                        if (capturedSamples * 1_000L / config.sampleRateHz >= config.maxDurationMs) {
                            state = state.copy(stopReason = PcmStopReason.MAX_DURATION)
                            running.set(false)
                        }
                    }
                    bytesRead == 0 -> {
                        zeroReads += 1
                        pooled?.let(pool::release)
                    }
                    bytesRead == AudioRecord.ERROR_INVALID_OPERATION -> {
                        pooled?.let(pool::release)
                        throw PcmCaptureException("invalid_recording_operation", "AudioRecord rejected the read operation")
                    }
                    bytesRead == AudioRecord.ERROR_BAD_VALUE -> {
                        pooled?.let(pool::release)
                        throw PcmCaptureException("invalid_audio_buffer", "AudioRecord rejected the PCM buffer")
                    }
                    bytesRead == AudioRecord.ERROR_DEAD_OBJECT -> {
                        pooled?.let(pool::release)
                        throw PcmCaptureException("audio_device_disconnected", "The active microphone device disconnected")
                    }
                    else -> {
                        pooled?.let(pool::release)
                        throw PcmCaptureException("audio_read_failed", "AudioRecord read failed with code $bytesRead")
                    }
                }
            }
        } catch (error: Throwable) {
            if (running.get()) failure = error
        } finally {
            failure = failure ?: terminalFailure
            running.set(false)
            runCatching { resampler?.close() }
            unregisterSilenceMonitor()
            releaseEffects()
            runCatching {
                if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) record.stop()
            }
            runCatching { record.release() }
            activeRecord = null
            captureThread = null
            val previous = state
            val interrupted = previous.errorCode != null || previous.stopReason == PcmStopReason.AUDIO_INTERRUPTED
            state = previous.copy(
                phase = if (failure == null && !interrupted) PcmRecorderPhase.STOPPED else PcmRecorderPhase.FAILED,
                currentAmplitude = 0,
                stopReason = previous.stopReason ?: if (failure == null) PcmStopReason.USER_CANCEL else PcmStopReason.CAPTURE_FAILURE,
                errorCode = (failure as? PcmCaptureException)?.code ?: failure?.javaClass?.simpleName
                    ?: previous.errorCode
            )
            channel.close(failure)
        }
    }

    private fun configureEffects(sessionId: Int, config: PcmCaptureConfig) {
        echoCanceler = if (config.enableAcousticEchoCanceler && AcousticEchoCanceler.isAvailable()) {
            runCatching { AcousticEchoCanceler.create(sessionId)?.apply { enabled = true } }.getOrNull()
        } else null
        noiseSuppressor = if (config.enableNoiseSuppressor && NoiseSuppressor.isAvailable()) {
            runCatching { NoiseSuppressor.create(sessionId)?.apply { enabled = true } }.getOrNull()
        } else null
        gainControl = if (config.enableAutomaticGainControl && AutomaticGainControl.isAvailable()) {
            runCatching { AutomaticGainControl.create(sessionId)?.apply { enabled = true } }.getOrNull()
        } else null
    }

    private fun releaseEffects() {
        runCatching { echoCanceler?.release() }
        runCatching { noiseSuppressor?.release() }
        runCatching { gainControl?.release() }
        echoCanceler = null
        noiseSuppressor = null
        gainControl = null
    }

    private fun registerSilenceMonitor(sessionId: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val manager = audioManager ?: return
        val callback = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>?) {
                val active = configs.orEmpty().firstOrNull { it.clientAudioSessionId == sessionId } ?: return
                if (active.isClientSilenced) {
                    synchronized(lock) {
                        terminalFailure = PcmCaptureException(
                            "audio_input_silenced",
                            "Android audio policy interrupted microphone capture"
                        )
                        state = state.copy(
                            phase = PcmRecorderPhase.FAILED,
                            stopReason = PcmStopReason.AUDIO_INTERRUPTED,
                            errorCode = "audio_input_silenced"
                        )
                    }
                    running.set(false)
                    thread(name = "galaxyssi-pcm-interrupt") { runCatching { activeRecord?.stop() } }
                }
            }
        }
        recordingCallback = callback
        manager.registerAudioRecordingCallback(callback, Handler(Looper.getMainLooper()))
    }

    private fun unregisterSilenceMonitor() {
        val callback = recordingCallback ?: return
        runCatching { audioManager?.unregisterAudioRecordingCallback(callback) }
        recordingCallback = null
    }

    private fun peakAmplitude(samples: ShortArray, count: Int): Int {
        var peak = 0
        repeat(count.coerceAtMost(samples.size)) { peak = maxOf(peak, abs(samples[it].toInt())) }
        return peak.coerceAtMost(Short.MAX_VALUE.toInt())
    }

    private fun routeLabel(device: AudioDeviceInfo?): String = when (device?.type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "built_in_mic"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth_sco"
        AudioDeviceInfo.TYPE_BLE_HEADSET -> "bluetooth_le"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired_headset"
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "usb"
        null -> "default"
        else -> "type_${device.type}"
    }

    private companion object {
        const val ROUTE_CHECK_FRAME_INTERVAL = 25L
        const val STOP_JOIN_TIMEOUT_MS = 500L
        const val STOP_FORCE_JOIN_TIMEOUT_MS = 250L
        const val PCM16_BYTES_PER_SAMPLE = 2
    }

    private data class OpenedAudioRecord(
        val record: AudioRecord,
        val audioSource: Int,
        val captureSampleRateHz: Int
    )
}
