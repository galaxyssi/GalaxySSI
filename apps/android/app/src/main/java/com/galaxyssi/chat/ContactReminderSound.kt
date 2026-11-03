package com.galaxyssi.chat

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/** One bounded reminder sound, independent of notification/ringer volume and panel lifetime. */
internal object ContactReminderSound {
    private val main = Handler(Looper.getMainLooper())
    private var id = ""
    private var ringtone: Ringtone? = null
    private var focus: AudioFocusRequest? = null
    private var audio: AudioManager? = null

    internal fun isPlaying(reminderId: String): Boolean = id == reminderId && ringtone?.isPlaying == true

    private fun diagnostic(message: String) {
        if (BuildConfig.DEBUG) android.util.Log.d("GalaxySSIReminderAudio", message)
    }

    fun start(context: Context, value: ContactReminder) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (value.id == id) return
        if (value.terminal || value.status in setOf("muted", "quiet") || value.expiresAt <= System.currentTimeMillis()) {
            diagnostic("Skipped: inactive reminder")
            return
        }
        if (ContactReminderNotifications.callActive(context)) {
            diagnostic("Skipped: call or recording active")
            return
        }
        stop(reason = "replaced")
        val app = context.applicationContext
        val manager = app.getSystemService(AudioManager::class.java)
        val alarm = ContactReminders.preferences(app).getBoolean("silent_sound", true)
        if (!alarm && manager.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
            diagnostic("Skipped: silent-mode sound disabled")
            return
        }
        val attributes = AudioAttributes.Builder().setUsage(if (alarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(attributes).setOnAudioFocusChangeListener { change -> if (change < 0) stop(value.id, "focus_loss:$change") }.build()
        if (manager.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            diagnostic("Skipped: audio focus denied")
            return
        }
        id = value.id; audio = manager; focus = request
        runCatching {
            ringtone = RingtoneManager.getRingtone(app, RingtoneManager.getDefaultUri(
                if (alarm) RingtoneManager.TYPE_ALARM else RingtoneManager.TYPE_NOTIFICATION))?.apply {
                audioAttributes = attributes
                if (Build.VERSION.SDK_INT >= 28) isLooping = true
                play()
            }
        }.onFailure { diagnostic("Playback error: ${it.javaClass.simpleName}"); stop(reason = "playback_error") }
        diagnostic("Playback started=${ringtone?.isPlaying == true} usage=${attributes.usage} ringer=${manager.ringerMode} alarmVolume=${manager.getStreamVolume(AudioManager.STREAM_ALARM)}")
        val end = minOf(value.expiresAt, System.currentTimeMillis() + ContactReminderPolicy.SOUND_MS)
        val watch = object : Runnable {
            override fun run() {
                if (id != value.id) return
                if (System.currentTimeMillis() >= end) stop(value.id, "timeout")
                else if (ContactReminderNotifications.callActive(app)) stop(value.id, "call_or_recording")
                else main.postDelayed(this, 500)
            }
        }
        main.post(watch)
    }

    fun stop(reminderId: String = id, reason: String = "explicit_action") {
        if (id != reminderId) return
        if (id.isNotEmpty()) diagnostic("Stopped: $reason")
        main.removeCallbacksAndMessages(null)
        ringtone?.stop(); ringtone = null
        focus?.let { audio?.abandonAudioFocusRequest(it) }
        focus = null; audio = null; id = ""
    }
}
