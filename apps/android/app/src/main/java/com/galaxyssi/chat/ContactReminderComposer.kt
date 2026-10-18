package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
import android.widget.ImageButton
import android.widget.Toast

internal class ContactReminderComposer(private val activity: MainActivity) {
    private val entry = activity.findViewById<ImageButton>(R.id.contactReminderButton)
    private var sending = false
    private val observer: (ContactReminder) -> Unit = { value ->
        if (activity.selectedContact?.id == value.contactId) activity.reloadChatHistoryIfChanged(force = true)
    }
    init {
        entry.tooltipText = activity.getString(R.string.contact_reminder_send)
        entry.setOnClickListener {
            val contact = activity.selectedContact ?: return@setOnClickListener
            if (sending || !AppStore.isDirectPeerContact(activity, contact.id)) return@setOnClickListener
            sending = true; entry.isEnabled = false
            ContactReminders.send(activity, contact.id) { value ->
                sending = false; entry.isEnabled = true
                if (activity.isFinishing || activity.isDestroyed) return@send
                if (value == null) Toast.makeText(activity, R.string.contact_reminder_failed, Toast.LENGTH_LONG).show()
                else activity.startActivity(ContactReminderActivity.intent(activity, value.id))
            }
        }
        entry.setOnLongClickListener { settings(); true }
        ContactReminders.observers.add(observer)
    }
    fun update(visible: Boolean) { entry.visibility = if (visible) View.VISIBLE else View.GONE }
    fun destroy() { ContactReminders.observers.remove(observer) }

    private fun settings() {
        val prefs = ContactReminders.preferences(activity)
        val keys = arrayOf("enabled", "silent_sound", "lockscreen")
        val labels = arrayOf(R.string.contact_reminder_enable, R.string.contact_reminder_silent_sound, R.string.contact_reminder_lockscreen)
            .map(activity::getString).toTypedArray()
        AlertDialog.Builder(activity).setTitle(R.string.contact_reminder_settings)
            .setMultiChoiceItems(labels, keys.map { prefs.getBoolean(it, it != "lockscreen") }.toBooleanArray()) { _, which, checked ->
                prefs.edit().putBoolean(keys[which], checked).apply()
                if (which == 2 && checked && Build.VERSION.SDK_INT >= 34 &&
                    !activity.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()) {
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                        Uri.parse("package:${activity.packageName}")))
                }
            }.setPositiveButton(android.R.string.ok, null)
            .setNeutralButton(R.string.contact_reminder_system_settings) { _, _ ->
                activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
            }.show()
    }
}
