package com.galaxyssi.chat.voice.audio

import android.app.Activity
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.media.AudioDeviceCallback
import android.os.Handler
import android.os.Looper
import com.galaxyssi.chat.R

/** Owns communication routing only while this foreground voice call is active. */
internal class VoiceCommunicationAudioSession(private val activity: Activity) {
    private val manager = activity.getSystemService(AudioManager::class.java)
    private var acquired = false
    private var previousMode = AudioManager.MODE_NORMAL
    private var previousSpeaker = false
    private var previousVolumeStream = AudioManager.USE_DEFAULT_STREAM_TYPE
    private var previousDevice: AudioDeviceInfo? = null
    private var selectedDeviceId: Int? = null
    var onRouteChanged: (() -> Unit)? = null
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) { onRouteChanged?.invoke() }
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) { onRouteChanged?.invoke() }
    }
    private val routeListener = if (Build.VERSION.SDK_INT >= 31)
        AudioManager.OnCommunicationDeviceChangedListener { onRouteChanged?.invoke() } else null

    fun choices(): List<AudioDeviceInfo> = if (Build.VERSION.SDK_INT >= 31)
        manager.availableCommunicationDevices else emptyList()

    fun select(device: AudioDeviceInfo): Boolean = Build.VERSION.SDK_INT >= 31 && active &&
        choices().any { it.id == device.id } && manager.setCommunicationDevice(device).also {
            if (it) selectedDeviceId = device.id
        }

    fun label(device: AudioDeviceInfo? = if (Build.VERSION.SDK_INT >= 31) manager.communicationDevice else null): String {
        val resource = when (device?.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_BLE_HEADSET -> R.string.voice_control_bluetooth
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> R.string.voice_control_wired
            AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> R.string.voice_control_usb
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> R.string.voice_control_earpiece
            else -> if (Build.VERSION.SDK_INT < 31 && manager.isBluetoothScoOn) R.string.voice_control_bluetooth
                else if (Build.VERSION.SDK_INT < 31 && manager.isWiredHeadsetOn) R.string.voice_control_wired
                else R.string.voice_control_speaker
        }
        return activity.getString(resource)
    }

    val active: Boolean get() = acquired && manager.mode == AudioManager.MODE_IN_COMMUNICATION

    fun acquire(): Boolean {
        if (active) return true
        if (acquired) release()
        if (manager.mode != AudioManager.MODE_NORMAL) return false
        previousMode = manager.mode
        previousSpeaker = manager.isSpeakerphoneOn
        previousVolumeStream = activity.volumeControlStream
        if (Build.VERSION.SDK_INT >= 31) previousDevice = manager.communicationDevice
        acquired = true
        return runCatching {
            manager.registerAudioDeviceCallback(deviceCallback, Handler(Looper.getMainLooper()))
            if (Build.VERSION.SDK_INT >= 31 && routeListener != null)
                manager.addOnCommunicationDeviceChangedListener(activity.mainExecutor, routeListener)
            manager.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= 31) {
                val devices = manager.availableCommunicationDevices
                val headset = devices.firstOrNull { it.type in HEADSET_TYPES }
                val selected = headset ?: devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                check(selected != null && manager.setCommunicationDevice(selected))
                selectedDeviceId = selected.id
            } else {
                manager.isSpeakerphoneOn = !manager.isWiredHeadsetOn && !manager.isBluetoothScoOn
            }
            activity.volumeControlStream = AudioManager.STREAM_VOICE_CALL
            check(active)
            true
        }.getOrElse { release(); false }
    }

    fun release() {
        if (!acquired) return
        acquired = false
        runCatching {
            manager.unregisterAudioDeviceCallback(deviceCallback)
            if (Build.VERSION.SDK_INT >= 31 && routeListener != null)
                manager.removeOnCommunicationDeviceChangedListener(routeListener)
            if (manager.mode == AudioManager.MODE_IN_COMMUNICATION) {
                if (Build.VERSION.SDK_INT >= 31) {
                    if (manager.communicationDevice?.id == selectedDeviceId) {
                        val old = previousDevice?.takeIf { previous ->
                            manager.availableCommunicationDevices.any { it.id == previous.id }
                        }
                        if (old != null) manager.setCommunicationDevice(old) else manager.clearCommunicationDevice()
                    }
                } else manager.isSpeakerphoneOn = previousSpeaker
                manager.mode = previousMode
            }
            activity.volumeControlStream = previousVolumeStream
        }
        selectedDeviceId = null
        previousDevice = null
    }

    companion object {
        private val HEADSET_TYPES = setOf(AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET)

        fun playbackAttributes(communication: Boolean): AudioAttributes = AudioAttributes.Builder()
            .setUsage(if (communication) AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_ASSISTANT)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
    }
}
