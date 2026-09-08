package com.galaxyssi.chat.voice

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/** Volatile, content-free counters for diagnosing the local wake capture path. */
internal data class LocalWakeDiagnostics(
    val listenAttempts: Long = 0,
    val readyCallbacks: Long = 0,
    val speechStarts: Long = 0,
    val speechEnds: Long = 0,
    val rmsSamples: Long = 0,
    val peakRmsDb: Float? = null,
    val resultCallbacks: Long = 0,
    val wakeMatches: Long = 0,
    val recognitionErrors: Long = 0,
    val lastRecognitionError: Int? = null,
    val serviceFailures: Long = 0,
    val lastServiceError: Int? = null
)

/** Foreground-only, opt-in local ASR wake. Never falls back to a network recognizer. */
internal class ForegroundChineseWake(
    private val context: Context,
    private val onState: (LocalWakeSnapshot) -> Unit,
    private val onWake: (String) -> Unit
) {
    var snapshot = LocalWakeSnapshot()
        private set
    var diagnostics = LocalWakeDiagnostics()
        private set
    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var generation = 0L
    private var enabled = false
    private var downloadChecks = 0
    private var busyRetries = 0

    fun setEnabled(value: Boolean) {
        requireMainThread()
        if (!value) { stop(); return }
        if (enabled) return
        enabled = true
        checkSupport()
    }

    fun stop() {
        requireMainThread()
        enabled = false
        downloadChecks = 0
        release()
        if (snapshot.availability == LocalWakeAvailability.LISTENING) {
            publish(snapshot.copy(availability = LocalWakeAvailability.READY))
        } else if (snapshot.availability == LocalWakeAvailability.CHECKING) {
            publish(snapshot.copy(availability = LocalWakeAvailability.UNCHECKED))
        }
    }

    fun checkSupport() {
        requireMainThread()
        release()
        if (Build.VERSION.SDK_INT < 33 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) {
            publish(LocalWakeSnapshot(LocalWakeAvailability.UNAVAILABLE))
            return
        }
        val token = generation
        publish(snapshot.copy(availability = LocalWakeAvailability.CHECKING, errorCode = null))
        runCatching {
            recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context).apply {
                setRecognitionListener(Listener(token))
                checkRecognitionSupport(intent(), context.mainExecutor, object : RecognitionSupportCallback {
                    override fun onSupportResult(support: RecognitionSupport) {
                        if (token != generation) return
                        release()
                        val result = ChineseWakePolicy.languageSupport(
                            support.installedOnDeviceLanguages,
                            support.pendingOnDeviceLanguages,
                            support.supportedOnDeviceLanguages
                        )
                        publish(result)
                        if (result.availability == LocalWakeAvailability.READY) {
                            downloadChecks = 0
                            if (enabled) beginListening()
                        } else if (downloadChecks > 0 && result.availability in setOf(
                                LocalWakeAvailability.NEEDS_DOWNLOAD, LocalWakeAvailability.DOWNLOAD_PENDING
                            )) {
                            // API 33 has no download progress callback. Re-query real installed state.
                            publish(result.copy(availability = LocalWakeAvailability.DOWNLOAD_PENDING))
                            downloadChecks--
                            if (downloadChecks > 0) handler.postDelayed({ checkSupport() }, 5_000L)
                        }
                    }

                    override fun onError(error: Int) {
                        if (token == generation) fail(error)
                    }
                })
            }
            handler.postDelayed({
                if (generation == token && snapshot.availability == LocalWakeAvailability.CHECKING) {
                    fail(SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT)
                }
            }, 10_000L)
        }.onFailure { fail(SpeechRecognizer.ERROR_CLIENT) }
    }

    fun requestModelDownload() {
        requireMainThread()
        if (Build.VERSION.SDK_INT < 33 || snapshot.availability !in setOf(
                LocalWakeAvailability.NEEDS_DOWNLOAD, LocalWakeAvailability.DOWNLOAD_PENDING
            )) return
        release()
        runCatching {
            recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context).apply {
                setRecognitionListener(Listener(generation))
                triggerModelDownload(intent())
            }
            downloadChecks = 24
            publish(snapshot.copy(availability = LocalWakeAvailability.DOWNLOAD_PENDING, errorCode = null))
            handler.postDelayed({ checkSupport() }, 2_000L)
        }.onFailure { fail(SpeechRecognizer.ERROR_CLIENT) }
    }

    private fun intent() = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE, snapshot.languageTag)
        .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
        .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)

    private fun beginListening() {
        if (!enabled || Build.VERSION.SDK_INT < 33) return
        release()
        val token = generation
        diagnostics = diagnostics.copy(listenAttempts = diagnostics.listenAttempts + 1)
        runCatching {
            recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context).apply {
                setRecognitionListener(Listener(token))
                startListening(intent())
            }
            // A dead service must not hold the microphone or UI in a false listening state.
            handler.postDelayed({ if (token == generation) fail(SpeechRecognizer.ERROR_SERVER_DISCONNECTED) }, 60_000L)
        }.onFailure { fail(SpeechRecognizer.ERROR_CLIENT) }
    }

    private fun restart(delayMs: Long = 750L) {
        release()
        publish(snapshot.copy(availability = LocalWakeAvailability.READY))
        if (enabled) handler.postDelayed({ beginListening() }, delayMs)
    }

    private fun fail(error: Int) {
        diagnostics = diagnostics.copy(serviceFailures = diagnostics.serviceFailures + 1, lastServiceError = error)
        release()
        enabled = false
        downloadChecks = 0
        publish(snapshot.copy(availability = LocalWakeAvailability.FAILED, errorCode = error))
    }

    private fun release() {
        generation++
        handler.removeCallbacksAndMessages(null)
        runCatching { recognizer?.cancel() }
        runCatching { recognizer?.destroy() }
        recognizer = null
    }

    private fun publish(value: LocalWakeSnapshot) {
        snapshot = value
        onState(value)
    }

    private fun requireMainThread() = check(Looper.myLooper() == Looper.getMainLooper())

    private inner class Listener(private val token: Long) : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            if (token == generation && enabled) {
                diagnostics = diagnostics.copy(readyCallbacks = diagnostics.readyCallbacks + 1)
                publish(snapshot.copy(availability = LocalWakeAvailability.LISTENING))
            }
        }
        override fun onBeginningOfSpeech() {
            if (token == generation && enabled) diagnostics = diagnostics.copy(speechStarts = diagnostics.speechStarts + 1)
        }
        override fun onRmsChanged(rmsdB: Float) {
            if (token == generation && enabled && rmsdB.isFinite()) diagnostics = diagnostics.copy(
                rmsSamples = diagnostics.rmsSamples + 1,
                peakRmsDb = diagnostics.peakRmsDb?.let { maxOf(it, rmsdB) } ?: rmsdB
            )
        }
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() {
            if (token == generation && enabled) diagnostics = diagnostics.copy(speechEnds = diagnostics.speechEnds + 1)
        }
        override fun onPartialResults(partialResults: Bundle?) = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onResults(results: Bundle?) {
            if (token != generation || !enabled) return
            busyRetries = 0
            val command = ChineseWakePolicy.commandAfterWake(
                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
            )
            diagnostics = diagnostics.copy(resultCallbacks = diagnostics.resultCallbacks + 1,
                wakeMatches = diagnostics.wakeMatches + if (command == null) 0 else 1)
            if (command == null) restart() else {
                stop()
                onWake(command)
            }
        }

        override fun onError(error: Int) {
            if (token != generation) return
            diagnostics = diagnostics.copy(recognitionErrors = diagnostics.recognitionErrors + 1, lastRecognitionError = error)
            if (!enabled) { fail(error); return }
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                    busyRetries = 0
                    restart()
                }
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> {
                    if (++busyRetries <= 3) restart(2_500L) else fail(error)
                }
                else -> fail(error)
            }
        }
    }
}
