package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast

internal object ContactReminderSettings {
    fun show(activity: Activity) {
        val prefs = ContactReminders.preferences(activity)
        val keys = arrayOf("enabled", "silent_sound", "background_panel", "lockscreen")
        val labels = arrayOf(R.string.contact_reminder_enable, R.string.contact_reminder_silent_sound,
            R.string.contact_reminder_background, R.string.contact_reminder_lockscreen)
            .map(activity::getString).toTypedArray()
        AlertDialog.Builder(activity).setTitle(R.string.contact_reminder_settings)
            .setMultiChoiceItems(labels, keys.map { prefs.getBoolean(it, true) }.toBooleanArray()) { _, which, checked ->
                prefs.edit().putBoolean(keys[which], checked).apply()
                if (checked && which == 2 && !Settings.canDrawOverlays(activity)) overlay(activity)
                if (checked && which == 3 && !Settings.canDrawOverlays(activity) && Build.VERSION.SDK_INT >= 34 &&
                    !activity.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()) {
                    open(activity, Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                        Uri.parse("package:${activity.packageName}")))
                }
            }.setPositiveButton(android.R.string.ok, null)
            .setNeutralButton(R.string.contact_reminder_panel_permissions) { _, _ -> permissions(activity) }
            .show()
    }

    private fun permissions(activity: Activity) {
        val manager = activity.getSystemService(NotificationManager::class.java)
        val choices = mutableListOf<Pair<String, () -> Unit>>()
        fun label(res: Int, allowed: Boolean) = activity.getString(res) + " \u00b7 " +
            activity.getString(if (allowed) R.string.contact_reminder_allowed else R.string.contact_reminder_not_allowed)
        choices.add(label(R.string.contact_reminder_overlay_permission, Settings.canDrawOverlays(activity)) to { overlay(activity) })
        if (Build.VERSION.SDK_INT >= 34) choices.add(label(R.string.contact_reminder_fullscreen_permission,
            manager.canUseFullScreenIntent()) to {
            open(activity, Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:${activity.packageName}")))
        })
        choices.add(label(R.string.contact_reminder_system_settings, manager.areNotificationsEnabled()) to {
            open(activity, Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
        })
        AlertDialog.Builder(activity).setTitle(R.string.contact_reminder_panel_permissions)
            .setItems(choices.map { it.first }.toTypedArray()) { _, index -> choices[index].second() }
            .setNegativeButton(android.R.string.cancel, null).show()
    }

    private fun overlay(activity: Activity) = open(activity,
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}")))

    private fun open(activity: Activity, intent: Intent) {
        runCatching { activity.startActivity(intent) }.onFailure {
            Toast.makeText(activity, R.string.contact_reminder_settings_unavailable, Toast.LENGTH_LONG).show()
        }
    }
}
