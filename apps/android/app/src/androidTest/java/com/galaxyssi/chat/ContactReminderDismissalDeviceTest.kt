package com.galaxyssi.chat

import android.content.Intent
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/** UI-only reminders: no message history, sound, notification, or MQTT publication. */
@RunWith(AndroidJUnit4::class)
class ContactReminderDismissalDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    private fun fixture(outgoing: Boolean, block: (ContactReminderActivity, ContactReminder, ContactReminderStore) -> Unit) {
        val contacts = AppStore.contacts(context)
        val contactId = (0 until contacts.length()).mapNotNull { contacts.optJSONObject(it)?.let { row ->
            row.optString("galaxyssi_id").ifBlank { row.optString("hermes_id") }.ifBlank { row.optString("id") }
        } }.firstOrNull { AppStore.isPersonContact(context, it) }
        assumeTrue("A paired phone is required", contactId != null)
        val now = System.currentTimeMillis()
        val value = ContactReminder(UUID.randomUUID().toString(), contactId!!, outgoing, now, now + 120_000,
            if (outgoing) "queued" else "received")
        val store = ContactReminderStore(context)
        store.put(value)
        val activity = instrumentation.startActivitySync(Intent(context, ContactReminderActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("reminder_id", value.id)) as ContactReminderActivity
        try {
            instrumentation.runOnMainSync {
                activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
            }
            SystemClock.sleep(250)
            instrumentation.waitForIdleSync()
            block(activity, value, store)
        } finally {
            instrumentation.runOnMainSync { if (!activity.isDestroyed) activity.finish() }
            store.writableDatabase.delete("reminders", "id=?", arrayOf(value.id))
            store.close()
        }
    }

    @Test fun everyTerminalReceiptClosesBothIncomingAndOutgoingPanels() {
        for (outgoing in listOf(false, true)) for (state in ContactReminderPolicy.terminal) {
            fixture(outgoing) { activity, value, store ->
                val ended = value.copy(status = state)
                store.put(ended)
                instrumentation.runOnMainSync {
                    assertFalse("Active reminder must remain visible", activity.isFinishing)
                    ContactReminders.observers.toList().forEach { it(ended) }
                    assertTrue("Terminal state $state must close the panel", activity.isFinishing)
                }
            }
        }
    }

    @Test fun silencingAndUnrelatedReceiptsDoNotCompleteTheCurrentReminder() {
        fixture(false) { activity, value, _ ->
            instrumentation.runOnMainSync {
                ContactReminders.observers.toList().forEach { it(value.copy(status = "muted")) }
                assertFalse("Silencing is not acknowledgement", activity.isFinishing)
                ContactReminders.observers.toList().forEach {
                    it(value.copy(id = UUID.randomUUID().toString(), status = "cancelled"))
                }
                assertFalse("Another reminder must not close this panel", activity.isFinishing)
            }
        }
    }
}
