package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import java.lang.ref.WeakReference
import java.util.concurrent.CopyOnWriteArraySet

/** Telecom owns the connection and audio. This service never captures or injects SIM audio. */
class GalaxySSIInCallService : InCallService() {
    private val callbacks = mutableMapOf<Call, Call.Callback>()
    override fun onCreate() { super.onCreate(); current = WeakReference(this) }
    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        val callback = object : Call.Callback() {
            override fun onStateChanged(call: Call, state: Int) = changed()
            override fun onDetailsChanged(call: Call, details: Call.Details) = changed()
            override fun onConferenceableCallsChanged(call: Call, conferenceableCalls: MutableList<Call>) = changed()
        }
        callbacks[call] = callback
        call.registerCallback(callback)
        AppVoiceControlBridge.interruptForCall()
        changed()
        if (call.state != Call.STATE_RINGING) bringToForeground()
    }
    override fun onCallRemoved(call: Call) {
        callbacks.remove(call)?.let(call::unregisterCallback)
        super.onCallRemoved(call)
        changed()
    }
    override fun onCallAudioStateChanged(audioState: CallAudioState) { super.onCallAudioStateChanged(audioState); changed() }
    override fun onBringToForeground(showDialpad: Boolean) { bringToForeground(showDialpad) }
    override fun onDestroy() {
        callbacks.forEach { (call, callback) -> call.unregisterCallback(callback) }
        callbacks.clear()
        if (current.get() === this) current.clear()
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        listeners.forEach { it() }
        super.onDestroy()
    }
    private fun bringToForeground(keypad: Boolean = false) {
        startActivity(Intent(this, PhoneAssistantActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("keypad", keypad))
    }
    private fun changed() {
        listeners.forEach { it() }
        val call = calls.firstOrNull { it.state == Call.STATE_RINGING }
            ?: calls.firstOrNull { it.state != Call.STATE_DISCONNECTED }
        val manager = getSystemService(NotificationManager::class.java)
        if (call == null) { manager.cancel(NOTIFICATION_ID); return }
        manager.createNotificationChannel(NotificationChannel(CHANNEL,
            getString(R.string.voice_control_phone_channel), NotificationManager.IMPORTANCE_HIGH).apply {
            // Telecom keeps ownership of ringtone and DND behavior.
            setSound(null, null)
        })
        val intent = PendingIntent.getActivity(this, 0, Intent(this, PhoneAssistantActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val incoming = call.state == Call.STATE_RINGING
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_voice_call_end)
            .setContentTitle(getString(if (incoming) R.string.voice_control_incoming else R.string.voice_control_call_active))
            .setContentIntent(intent).setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true).setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PRIVATE)
        if (incoming) notification.setFullScreenIntent(intent, true)
        manager.notify(NOTIFICATION_ID, notification.build())
    }
    companion object {
        private const val CHANNEL = "phone_calls"
        private const val NOTIFICATION_ID = 6208
        internal var current = WeakReference<GalaxySSIInCallService>(null)
            private set
        internal val listeners = CopyOnWriteArraySet<() -> Unit>()
    }
}
