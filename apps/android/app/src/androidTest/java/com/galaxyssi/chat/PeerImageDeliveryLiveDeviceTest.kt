package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import kotlin.random.Random

/** Opt-in: sends generated pixels only, never a user's existing image. */
class PeerImageDeliveryLiveDeviceTest {
    @Test fun imageAndConcurrentTextReachPairedDesktop() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_peer_image_send") == "true")
        val desktop = requireNotNull(args.getString("live_desktop_id"))
        val context = instrumentation.targetContext
        val monitor = instrumentation.addMonitor(MainActivity::class.java.name, null, false)
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val activity = instrumentation.waitForMonitorWithTimeout(monitor, 30_000) as MainActivity
        try {
            val readyBy = SystemClock.elapsedRealtime() + 60_000
            while (activity.initialAgentHydrationPending || !GalaxySSIMqttClient.isRequestReplyReady()) {
                assertTrue("No ready activity and authenticated route", SystemClock.elapsedRealtime() < readyBy)
                SystemClock.sleep(200)
            }
            lateinit var target: Contact
            instrumentation.runOnMainSync {
                target = activity.storedContacts().single {
                    AppStore.isDesktopDeviceContact(context, it.id) && AppStore.desktopIdForContact(context, it.id) == desktop
                }
                activity.openContactMessaging(target)
            }
            var historyReady = false
            val historyBy = SystemClock.elapsedRealtime() + 30_000
            while (!historyReady) {
                instrumentation.runOnMainSync { historyReady = activity.loadedHistoryContacts.contains(target.id) }
                assertTrue("Contact history did not load", SystemClock.elapsedRealtime() < historyBy)
                SystemClock.sleep(100)
            }
            val filename = "image-delivery-${UUID.randomUUID()}.jpg"
            val bitmap = Bitmap.createBitmap(900, 700, Bitmap.Config.ARGB_8888)
            val random = Random(812)
            val pixels = IntArray(bitmap.width * bitmap.height) { random.nextInt() or (0xff shl 24) }
            bitmap.setPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            pixels.fill(0)
            val bytes = ByteArrayOutputStream().use { output ->
                assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output))
                output.toByteArray()
            }
            bitmap.recycle()
            assertTrue(bytes.size > 256 * 1024)
            val hash = AgentAttachmentTransferProtocol.sha256(bytes)
            val file = File(context.filesDir, "composer-attachments-v1/$filename")
            AttachmentLocalStore.storeBytes(bytes, file)
            val size = bytes.size
            bytes.fill(0)
            val uri = LocalAttachmentUris.forFile(context, file, filename, "image/jpeg")
            val attachment = AgentInputAttachment(UUID.randomUUID().toString(), uri, filename,
                "image/jpeg", size.toLong(), sendOriginal = true)
            var messageId = 0L
            val started = SystemClock.elapsedRealtime()
            instrumentation.runOnMainSync {
                activity.sendPeerAttachments(target, listOf(uri), "\u56fe\u7247\u4f20\u8f93\u56de\u5f52\u6d4b\u8bd5", listOf(attachment))
                messageId = activity.messages[target.id]!!.last().id
                val image = activity.messages[target.id]!!.last().attachments.single()
                assertEquals("uploading", image.transferState)
                val view = PeerImageAttachmentView(context)
                view.layoutParams = android.widget.FrameLayout.LayoutParams(200, 240)
                view.bind(image, {}, {})
                assertEquals(android.view.View.VISIBLE, view.getChildAt(2).visibility)
            }
            SystemClock.sleep(1000)
            Log.i("ImageDeliveryLive", JSONObject().put("phase", "sent").put("message_id", messageId)
                .put("filename", filename).put("sha256", hash).put("size_bytes", size).toString())
            val textId = ChatHistoryStore.appendOutgoing(context, target.id, "\u56fe\u7247\u4e0a\u4f20\u671f\u95f4\u7684\u6587\u5b57\u6d4b\u8bd5")
            assertTrue(GalaxySSIMqttClient.publishPeerMessageResult("\u56fe\u7247\u4e0a\u4f20\u671f\u95f4\u7684\u6587\u5b57\u6d4b\u8bd5",
                target.id, clientMessageId = textId).accepted)
            var completed = false
            var textElapsed = 0L
            while (SystemClock.elapsedRealtime() - started < 180_000) {
                instrumentation.runOnMainSync {
                    completed = activity.messages[target.id]?.firstOrNull { it.id == messageId }
                        ?.attachments?.singleOrNull()?.transferState == PeerAttachmentTransferProgress.STATE_COMPLETE
                }
                if (textElapsed == 0L && !GalaxySSILinkDeliveryStore.hasPendingClientSourceMessageId(context, textId))
                    textElapsed = SystemClock.elapsedRealtime() - started
                if (completed && textElapsed > 0L && !GalaxySSILinkDeliveryStore.hasPendingClientSourceMessageId(context, messageId)) break
                SystemClock.sleep(250)
            }
            assertTrue("Receiver did not confirm complete image", completed)
            assertFalse("Chat message still waiting", GalaxySSILinkDeliveryStore.hasPendingClientSourceMessageId(context, messageId))
            assertTrue("Concurrent text was not delivered", textElapsed > 0L)
            val report = JSONObject().put("message_id", messageId).put("text_id", textId).put("filename", filename)
                .put("sha256", hash).put("size_bytes", size).put("text_elapsed_ms", textElapsed)
                .put("elapsed_ms", SystemClock.elapsedRealtime() - started)
            Log.i("ImageDeliveryLive", report.toString())
        } finally {
            instrumentation.removeMonitor(monitor)
        }
    }
}
