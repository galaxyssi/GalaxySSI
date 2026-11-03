package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ContactReminderInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun encryptedRowsSurviveReopenAndKeepTerminalTombstones() {
        val name = "reminder-verification.db"
        context.deleteDatabase(name)
        val id = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        val value = ContactReminder(id, "private-contact", false, now, now + 120_000, "received")
        try {
            ContactReminderStore(context, name).use { store ->
                store.put(value)
                assertEquals(listOf(id), store.activeIds())
                store.readableDatabase.rawQuery("SELECT payload FROM reminders WHERE id=?", arrayOf(id)).use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertFalse(cursor.getString(0).contains("private-contact"))
                }
                store.put(value.copy(status = "acknowledged"))
                assertTrue(store.activeIds().isEmpty())
            }
            ContactReminderStore(context, name).use { reopened ->
                assertEquals("acknowledged", reopened.get(id)?.status)
                reopened.prune(now + 120_001)
                assertNotNull(reopened.get(id))
                reopened.prune(now + 86_600_000)
                assertNull(reopened.get(id))
            }
        } finally { context.deleteDatabase(name) }
    }

    @Test fun contactLayoutContainsIndependentReminderEntry() {
        instrumentation.runOnMainSync {
            val themed = android.view.ContextThemeWrapper(context, R.style.Theme_GalaxySSI)
            val layout = android.view.LayoutInflater.from(themed).inflate(R.layout.activity_main, null)
            val entry = layout.findViewById<ImageButton>(R.id.contactReminderButton)
            assertNotNull(entry)
            assertEquals(context.getString(R.string.contact_reminder_send), entry.contentDescription)
            assertEquals(View.GONE, entry.visibility)
            assertNotNull(layout.findViewById<View>(R.id.messageInput))
            assertNotNull(layout.findViewById<View>(R.id.sendButton))
        }
    }

    @Test fun reminderPanelHasItsOwnTaskAndDeclaresOverlayAuthorization() {
        val component = android.content.ComponentName(context, ContactReminderActivity::class.java)
        val info = context.packageManager.getActivityInfo(component, 0)
        val main = context.packageManager.getActivityInfo(android.content.ComponentName(context, MainActivity::class.java), 0)
        assertEquals("com.galaxyssi.chat.reminder", info.taskAffinity)
        assertNotEquals(main.taskAffinity, info.taskAffinity)
        val permissions = context.packageManager.getPackageInfo(context.packageName,
            android.content.pm.PackageManager.GET_PERMISSIONS).requestedPermissions.orEmpty()
        assertTrue(permissions.contains(android.Manifest.permission.SYSTEM_ALERT_WINDOW))
    }

    @Test fun incomingPanelUsesTopFifthAndExpiresWithoutSendingAnything() {
        val contacts = AppStore.contacts(context)
        val contactId = (0 until contacts.length()).mapNotNull { contacts.optJSONObject(it)?.let { row ->
            row.optString("galaxyssi_id").ifBlank { row.optString("hermes_id") }.ifBlank { row.optString("id") }
        } }
            .firstOrNull { AppStore.isPersonContact(context, it) ||
                (AppStore.isDesktopDeviceContact(context, it) && GalaxySSILinkProtocol.serverLink(context,
                    AppStore.desktopIdForContact(context, it))?.paired == true) }
        assumeTrue("A paired contact is required for the real panel test", contactId != null)
        val id = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        val store = ContactReminderStore(context)
        // A UI-only reminder: no history row, notification, audio, or transport publication.
        store.put(ContactReminder(id, contactId!!, false, now, now + 6_000, "received"))
        val activity = instrumentation.startActivitySync(Intent(context, ContactReminderActivity::class.java)
            .putExtra("reminder_id", id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as ContactReminderActivity
        try {
            // This synthetic expiry fixture must not publish receipts when the live device is touched.
            instrumentation.runOnMainSync {
                activity.window.addFlags(android.view.WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
            }
            SystemClock.sleep(750)
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                assertTrue("A visible reminder must accept a subsequent reminder in the foreground",
                    AppForegroundTracker.isActivityForeground(activity))
                val root = activity.findViewById<ViewGroup>(android.R.id.content)
                val logo = activity.findViewById<ImageView>(R.id.contact_reminder_logo)
                assertNotNull(logo.drawable)
                assertNull(logo.imageTintList)
                val productLogo = activity.getDrawable(R.drawable.galaxyssi_mark_large) as BitmapDrawable
                assertTrue("The reminder shares the actual product logo",
                    (logo.drawable as BitmapDrawable).bitmap.sameAs(productLogo.bitmap))
                assertEquals(activity.getString(R.string.contact_reminder_subtitle),
                    activity.findViewById<TextView>(R.id.contact_reminder_header_subtitle).text.toString())
                assertTrue(descendants(root).filterIsInstance<TextView>().none {
                    it.text.toString() == activity.getString(R.string.contact_reminder_message)
                })
                assertTrue(descendants(root).filterIsInstance<ImageButton>().any {
                    it.contentDescription == activity.getString(R.string.contact_reminder_settings)
                })
                val buttons = descendants(root).filterIsInstance<Button>()
                buttons.forEach { it.isEnabled = false }
                assertEquals(3, buttons.size)
                assertTrue(buttons.any { it.text == activity.getString(R.string.contact_reminder_confirm) })
                val fraction = activity.window.attributes.height.toFloat() / activity.resources.displayMetrics.heightPixels
                assertTrue("Panel height: $fraction", fraction in .14f.. .29f)
                assertEquals(0f, activity.window.attributes.dimAmount)
            }
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                val file = File(context.getExternalFilesDir(null), "reminder-panel-verification.png")
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
            }
            SystemClock.sleep(6_200)
            instrumentation.waitForIdleSync()
            assertEquals("expired", store.get(id)?.status)
            instrumentation.runOnMainSync {
                assertTrue("Expired reminders close without an extra tap", activity.isFinishing || activity.isDestroyed)
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
            store.writableDatabase.delete("reminders", "id=?", arrayOf(id))
            store.close()
        }
    }

    private fun descendants(view: View): List<View> = listOf(view) +
        if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
