package com.galaxyssi.chat

import android.content.Intent
import android.media.AudioManager
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/** Explicit opt-in: this test plays a reminder, but never sends or records audio. */
@RunWith(AndroidJUnit4::class)
class ContactReminderAudioDeviceTest {
    @Test fun playbackSurvivesPanelReopenBackgroundAndDestruction() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("Pass -e reminderAudioProbe true to enable audible device testing",
            args.getString("reminderAudioProbe") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).mapNotNull { contacts.optJSONObject(it)?.let { row ->
            row.optString("galaxyssi_id").ifBlank { row.optString("hermes_id") }.ifBlank { row.optString("id") }
        } }.firstOrNull { AppStore.isPersonContact(context, it) }
        assumeTrue("A paired phone is required", contact != null)
        val audio = context.getSystemService(AudioManager::class.java)
        val ringer = audio.ringerMode
        val volume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        assumeTrue("Alarm volume must be audible", volume > 0)
        assumeTrue("No call or recording may be active", !ContactReminderNotifications.callActive(context))
        val now = System.currentTimeMillis()
        val value = ContactReminder(UUID.randomUUID().toString(), contact!!, false, now, now + 120_000, "received")
        val store = ContactReminderStore(context)
        store.put(value)
        val activity = instrumentation.startActivitySync(Intent(context, ContactReminderActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("reminder_id", value.id)) as ContactReminderActivity
        fun assertPlaying(stage: String) = instrumentation.runOnMainSync {
            assertTrue(stage, ContactReminderSound.isPlaying(value.id))
            assertEquals("Do not change the phone ringer", ringer, audio.ringerMode)
            assertEquals("Do not raise the alarm volume", volume, audio.getStreamVolume(AudioManager.STREAM_ALARM))
        }
        try {
            SystemClock.sleep(750)
            instrumentation.runOnMainSync { ContactReminderSound.start(context, value) }
            SystemClock.sleep(750)
            assertPlaying("Initial reminder must play")
            instrumentation.runOnMainSync { activity.startActivity(ContactReminderActivity.intent(context, value.id)) }
            SystemClock.sleep(750)
            assertPlaying("Reopening the same panel must not silence it")
            instrumentation.runOnMainSync { activity.moveTaskToBack(true) }
            SystemClock.sleep(750)
            assertPlaying("Backgrounding the panel must not silence it")
            instrumentation.runOnMainSync { activity.finish() }
            SystemClock.sleep(750)
            assertPlaying("Destroying a transient panel must not silence it")
            val probeSeconds = args.getString("probeSeconds")?.toLongOrNull()?.coerceIn(0, 15) ?: 0
            SystemClock.sleep(probeSeconds * 1_000)
            assertPlaying("Sound must remain active until an explicit action or its deadline")
            instrumentation.runOnMainSync {
                ContactReminderSound.stop(value.id)
                assertFalse(ContactReminderSound.isPlaying(value.id))
            }
        } finally {
            instrumentation.runOnMainSync { ContactReminderSound.stop(value.id); activity.finish() }
            store.writableDatabase.delete("reminders", "id=?", arrayOf(value.id))
            store.close()
        }
    }
}
