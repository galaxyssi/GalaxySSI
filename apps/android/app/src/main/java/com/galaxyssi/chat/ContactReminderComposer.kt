package com.galaxyssi.chat

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
        entry.setOnLongClickListener { ContactReminderSettings.show(activity); true }
        ContactReminders.observers.add(observer)
    }
    fun update(visible: Boolean) { entry.visibility = if (visible) View.VISIBLE else View.GONE }
    fun destroy() { ContactReminders.observers.remove(observer) }

}
