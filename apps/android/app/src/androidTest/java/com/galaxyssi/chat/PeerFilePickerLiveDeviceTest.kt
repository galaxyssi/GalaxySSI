package com.galaxyssi.chat

import android.content.Intent
import android.graphics.pdf.PdfDocument
import android.os.SystemClock
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/** Opt-in: sends only a generated PDF to the explicitly selected paired Desktop. */
class PeerFilePickerLiveDeviceTest {
    @Test fun auditRecentAttachmentMetadata() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_peer_audit") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val desktop = requireNotNull(args.getString("live_desktop_id"))
        val contacts = AppStore.contacts(context)
        val contact = (0 until contacts.length()).map { contacts.getJSONObject(it).getString("id") }
            .single { AppStore.isDesktopDeviceContact(context, it) && AppStore.desktopIdForContact(context, it) == desktop }
        val rows = ChatHistoryStore.page(context, contact, pageSize = 10).messages
        rows.filter { (it.optJSONArray("attachments")?.length() ?: 0) > 0 }.forEach { row ->
            Log.i("PeerFileAudit", JSONObject().put("id", row.optLong("id"))
                .put("timestamp", row.optLong("timestamp")).put("status", row.optString("deliveryStatus"))
                .put("trace", row.optJSONArray("deliveryTrace")).put("attachments", row.optJSONArray("attachments"))
                .toString())
        }
    }

    @Test fun selectedDocumentSendsWithoutOpeningEditorAndRetainsRecipient() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_peer_file_send") == "true")
        val desktop = requireNotNull(args.getString("live_desktop_id"))
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        val editor = instrumentation.addMonitor(ComposerAttachmentEditorActivity::class.java.name, null, true)
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val activity = instrumentation.waitForMonitorWithTimeout(monitor, 30_000L) as MainActivity
        val deadline = SystemClock.elapsedRealtime() + 30_000
        while (activity.initialAgentHydrationPending) {
            check(SystemClock.elapsedRealtime() < deadline)
            SystemClock.sleep(100)
        }
        val filename = "GalaxySSI-file-picker-test-${UUID.randomUUID()}.pdf"
        val file = File(context.filesDir, "composer-attachments-v1/$filename")
        file.parentFile!!.mkdirs()
        val pdf = PdfDocument()
        try {
            val page = pdf.startPage(PdfDocument.PageInfo.Builder(595, 842, 1).create())
            page.canvas.drawText("GalaxySSI synthetic file transfer test", 40f, 60f, android.graphics.Paint())
            pdf.finishPage(page)
            file.outputStream().use { pdf.writeTo(it) }
        } finally { pdf.close() }
        file.appendText("\n%" + "x".repeat(2_200_000) + "\n")
        val sha = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
        val uri = LocalAttachmentUris.forFile(context, file, filename, "application/pdf")
        var original: Contact? = null
        lateinit var target: Contact
        try {
            instrumentation.runOnMainSync {
                original = activity.selectedContact
                target = activity.storedContacts().single {
                    AppStore.isDesktopDeviceContact(context, it.id) && AppStore.desktopIdForContact(context, it.id) == desktop
                }
                activity.selectedContact = target
                activity.rememberAttachmentPickerTarget(agent = false)
                activity.previewPickedAttachments(listOf(uri))
                activity.selectedContact = CONTACT_SYSTEM
            }
            var message: ChatMessage? = null
            val importedBy = SystemClock.elapsedRealtime() + 30_000
            while (message == null && SystemClock.elapsedRealtime() < importedBy) {
                instrumentation.runOnMainSync {
                    message = activity.messages[target.id]?.lastOrNull { it.attachments.any { item -> item.name == filename } }
                }
                SystemClock.sleep(100)
            }
            assertNotNull("File picker did not send", message)
            assertEquals(0, editor.hits)
            assertEquals(target.id, message!!.contact.id)
            val report = JSONObject().put("filename", filename).put("sha256", sha).put("size", file.length())
                .put("message_id", message!!.id).put("contact_id", target.id)
            File(context.getExternalFilesDir(null), "peer-file-picker-test.json").writeText(report.toString())
            val deliveredBy = SystemClock.elapsedRealtime() + 120_000
            var complete = false
            while (!complete && SystemClock.elapsedRealtime() < deliveredBy) {
                instrumentation.runOnMainSync {
                    val current = activity.messages[target.id]?.firstOrNull { it.id == message!!.id }
                    assertNotEquals(context.getString(R.string.delivery_status_failed), current?.deliveryStatus)
                    complete = current?.attachments?.all { it.transferState == PeerAttachmentTransferProgress.STATE_COMPLETE } == true
                }
                SystemClock.sleep(250)
            }
            assertTrue("Desktop did not acknowledge complete attachment", complete)
            Log.i("PeerFileAudit", "Synthetic PDF complete $report")
        } finally {
            instrumentation.runOnMainSync { activity.selectedContact = original }
            instrumentation.removeMonitor(monitor)
            instrumentation.removeMonitor(editor)
        }
    }
}
