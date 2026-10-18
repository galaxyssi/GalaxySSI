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

    fun start(context: Context, value: ContactReminder) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (value.id == id || value.terminal || value.status in setOf("muted", "quiet") ||
            value.expiresAt <= System.currentTimeMillis() || ContactReminderNotifications.callActive(context)) return
        stop()
        val app = context.applicationContext
        val manager = app.getSystemService(AudioManager::class.java)
        val alarm = ContactReminders.preferences(app).getBoolean("silent_sound", true)
        if (!alarm && manager.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val attributes = AudioAttributes.Builder().setUsage(if (alarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(attributes).setOnAudioFocusChangeListener { change -> if (change < 0) stop(value.id) }.build()
        if (manager.requestAudioFocus(request) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) return
        id = value.id; audio = manager; focus = request
        runCatching {
            ringtone = RingtoneManager.getRingtone(app, RingtoneManager.getDefaultUri(
                if (alarm) RingtoneManager.TYPE_ALARM else RingtoneManager.TYPE_NOTIFICATION))?.apply {
                audioAttributes = attributes
                if (Build.VERSION.SDK_INT >= 28) isLooping = true
                play()
            }
        }.onFailure { stop() }
        val end = minOf(value.expiresAt, System.currentTimeMillis() + ContactReminderPolicy.SOUND_MS)
        val watch = object : Runnable {
            override fun run() {
                if (id != value.id) return
                if (System.currentTimeMillis() >= end || ContactReminderNotifications.callActive(app)) stop(value.id)
                else main.postDelayed(this, 500)
            }
        }
        main.post(watch)
    }

    fun stop(reminderId: String = id) {
        if (id != reminderId) return
        main.removeCallbacksAndMessages(null)
        ringtone?.stop(); ringtone = null
        focus?.let { audio?.abandonAudioFocusRequest(it) }
        focus = null; audio = null; id = ""
    }
}
