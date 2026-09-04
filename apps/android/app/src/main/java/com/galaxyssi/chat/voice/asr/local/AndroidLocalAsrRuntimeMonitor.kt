package com.galaxyssi.chat.voice.asr.local

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import com.galaxyssi.chat.voice.reliability.VoiceThermalController
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

internal interface LocalAsrRuntimeMonitor : AutoCloseable {
    fun onAppForegroundChanged(foreground: Boolean)
    fun onMicrophonePermissionChanged(granted: Boolean)
}

internal class AndroidLocalAsrRuntimeMonitor(
    context: Context,
    private val engine: LocalAsrEngine,
    private val scope: CoroutineScope,
    private val elapsedRealtimeMs: () -> Long = SystemClock::elapsedRealtime
) : LocalAsrRuntimeMonitor {
    private val appContext = context.applicationContext
    private val closed = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor(mainHandler::post)
    private val lifecycle = LocalAsrLifecycleCoordinator(engine)
    private val environment = LocalAsrRuntimeEnvironmentController(
        engine = engine,
        lifecycle = lifecycle,
        elapsedRealtimeMs = elapsedRealtimeMs
    )
    private val thermalController = VoiceThermalController(elapsedRealtimeMs)
    private val powerManager = appContext.getSystemService(PowerManager::class.java)
    private val audioManager = appContext.getSystemService(AudioManager::class.java)
    private val telephonyManager = appContext.getSystemService(TelephonyManager::class.java)
    private val stateJob: Job
    private val policyJob: Job
    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null
    private var telephonyCallback: TelephonyCallback? = null
    @Suppress("DEPRECATION")
    private var phoneStateListener: PhoneStateListener? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioFocusRequested = false
    private var audioFocusHeld = false
    private var focusRetryJob: Job? = null
    private var powerReceiverRegistered = false

    private val powerSaveReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) refreshPowerAndThermal()
        }
    }

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                audioFocusHeld = true
                lifecycle.onAudioFocusChanged(true)
            }
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                audioFocusHeld = false
                lifecycle.onAudioFocusChanged(false)
                if (change == AudioManager.AUDIOFOCUS_LOSS) {
                    audioFocusRequested = false
                    scheduleAudioFocusRetry()
                }
            }
        }
    }

    init {
        registerPowerSaveReceiver()
        registerThermalListener()
        refreshPowerAndThermal()
        refreshTelephonyRegistration()
        stateJob = scope.launch {
            engine.state.collect { state ->
                environment.onEngineStateChanged(state)
                reconcileAudioFocus(state)
            }
        }
        policyJob = scope.launch {
            while (isActive && !closed.get()) {
                delay(POLICY_TICK_MS)
                refreshPowerAndThermal()
                environment.tick()
                reconcileAudioFocus(engine.state.value)
            }
        }
    }

    override fun onAppForegroundChanged(foreground: Boolean) {
        if (!closed.get()) lifecycle.onAppForegroundChanged(foreground)
    }

    override fun onMicrophonePermissionChanged(granted: Boolean) {
        if (closed.get()) return
        lifecycle.onMicrophonePermissionChanged(granted)
        refreshTelephonyRegistration()
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        stateJob.cancel()
        policyJob.cancel()
        focusRetryJob?.cancel()
        releaseAudioFocus(clearBlocker = false)
        unregisterTelephony()
        thermalListener?.let { listener ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                runCatching { powerManager?.removeThermalStatusListener(listener) }
            }
        }
        thermalListener = null
        if (powerReceiverRegistered) {
            runCatching { appContext.unregisterReceiver(powerSaveReceiver) }
            powerReceiverRegistered = false
        }
        thermalController.reset()
    }

    private fun refreshPowerAndThermal() {
        if (closed.get()) return
        val observed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            powerManager?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE
        } else {
            PowerManager.THERMAL_STATUS_NONE
        }
        val effective = thermalController.evaluate(observed).effectiveStatus
        environment.onThermalStatusChanged(effective)
        environment.onSystemPowerSaveModeChanged(powerManager?.isPowerSaveMode == true)
    }

    private fun registerThermalListener() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || powerManager == null) return
        val listener = PowerManager.OnThermalStatusChangedListener { observed ->
            val effective = thermalController.evaluate(observed).effectiveStatus
            environment.onThermalStatusChanged(effective)
        }
        runCatching { powerManager.addThermalStatusListener(mainExecutor, listener) }
            .onSuccess { thermalListener = listener }
    }

    private fun registerPowerSaveReceiver() {
        val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                appContext.registerReceiver(powerSaveReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                appContext.registerReceiver(powerSaveReceiver, filter)
            }
        }.onSuccess { powerReceiverRegistered = true }
    }

    private fun refreshTelephonyRegistration() {
        if (closed.get() || telephonyManager == null) return
        val granted = appContext.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            unregisterTelephony()
            lifecycle.onPhoneCallChanged(false)
            return
        }
        if (telephonyCallback != null || phoneStateListener != null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = AsrTelephonyCallback { state ->
                lifecycle.onPhoneCallChanged(state != TelephonyManager.CALL_STATE_IDLE)
            }
            runCatching { telephonyManager.registerTelephonyCallback(mainExecutor, callback) }
                .onSuccess { telephonyCallback = callback }
        } else {
            @Suppress("DEPRECATION")
            val listener = object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    lifecycle.onPhoneCallChanged(state != TelephonyManager.CALL_STATE_IDLE)
                }
            }
            @Suppress("DEPRECATION")
            runCatching { telephonyManager.listen(listener, PhoneStateListener.LISTEN_CALL_STATE) }
                .onSuccess { phoneStateListener = listener }
        }
        @Suppress("DEPRECATION")
        runCatching { telephonyManager.callState }
            .onSuccess { lifecycle.onPhoneCallChanged(it != TelephonyManager.CALL_STATE_IDLE) }
    }

    private fun unregisterTelephony() {
        telephonyCallback?.let { callback ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                runCatching { telephonyManager?.unregisterTelephonyCallback(callback) }
            }
        }
        telephonyCallback = null
        phoneStateListener?.let { listener ->
            @Suppress("DEPRECATION")
            runCatching { telephonyManager?.listen(listener, PhoneStateListener.LISTEN_NONE) }
        }
        phoneStateListener = null
    }

    private fun reconcileAudioFocus(state: LocalAsrState) {
        if (closed.get()) return
        val shouldHold = when (state) {
            is LocalAsrState.Starting,
            is LocalAsrState.Listening,
            is LocalAsrState.Stopping -> true
            is LocalAsrState.Paused -> state.reasons.all { it == LocalAsrPauseReason.AUDIO_FOCUS_LOST }
            else -> false
        }
        if (shouldHold) requestAudioFocus() else releaseAudioFocus(clearBlocker = true)
    }

    private fun requestAudioFocus() {
        if (closed.get() || audioManager == null || audioFocusHeld || audioFocusRequested) return
        val request = audioFocusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAcceptsDelayedFocusGain(true)
            .setOnAudioFocusChangeListener(audioFocusListener, mainHandler)
            .build()
            .also { audioFocusRequest = it }
        when (runCatching { audioManager.requestAudioFocus(request) }
            .getOrDefault(AudioManager.AUDIOFOCUS_REQUEST_FAILED)
        ) {
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> {
                audioFocusRequested = true
                audioFocusHeld = true
                lifecycle.onAudioFocusChanged(true)
            }
            AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> {
                audioFocusRequested = true
                audioFocusHeld = false
                lifecycle.onAudioFocusChanged(false)
            }
            else -> {
                audioFocusRequested = false
                audioFocusHeld = false
                lifecycle.onAudioFocusChanged(false)
                scheduleAudioFocusRetry()
            }
        }
    }

    private fun scheduleAudioFocusRetry() {
        if (closed.get() || focusRetryJob?.isActive == true) return
        focusRetryJob = scope.launch {
            delay(AUDIO_FOCUS_RETRY_MS)
            focusRetryJob = null
            reconcileAudioFocus(engine.state.value)
        }
    }

    private fun releaseAudioFocus(clearBlocker: Boolean) {
        focusRetryJob?.cancel()
        focusRetryJob = null
        if (audioFocusRequested) {
            audioFocusRequest?.let { request -> runCatching { audioManager?.abandonAudioFocusRequest(request) } }
        }
        audioFocusRequested = false
        audioFocusHeld = false
        if (clearBlocker) lifecycle.onAudioFocusChanged(true)
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.S)
    private class AsrTelephonyCallback(
        private val onStateChanged: (Int) -> Unit
    ) : TelephonyCallback(), TelephonyCallback.CallStateListener {
        override fun onCallStateChanged(state: Int) = onStateChanged(state)
    }

    private companion object {
        const val POLICY_TICK_MS = 30_000L
        const val AUDIO_FOCUS_RETRY_MS = 1_000L
    }
}
