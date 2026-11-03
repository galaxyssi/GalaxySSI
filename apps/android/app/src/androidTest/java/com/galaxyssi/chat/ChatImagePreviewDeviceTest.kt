package com.galaxyssi.chat

import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.view.View
import android.view.inspector.WindowInspector
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ChatImagePreviewDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun sentAgentImageCanSaveAnExactCopyWithoutLosingPrivateSource() = withImage { activity, file, uri ->
        val original = file.readBytes()
        instrumentation.runOnMainSync {
            activity.agentUserAttachmentBlock(AgentRichBlock("fixture", AgentRichBlockType.IMAGE,
                title = file.name, uri = uri.toString(), mimeType = "image/png")).performClick()
        }
        saveAndCheck(activity, file.name, original, uri)
    }

    @Test fun sentPeerImageUsesTheSameViewerAndSurvivesPublicCopyDeletion() = withImage { activity, file, uri ->
        instrumentation.runOnMainSync {
            activity.openPeerAttachment(PeerChatAttachment(file.name, "image/png", file.length(), uri.toString()))
        }
        saveAndCheck(activity, file.name, file.readBytes(), uri)
    }

    @Test fun legacyReadableFileImageCanAlsoBeSaved() = withImage { activity, file, _ ->
        instrumentation.runOnMainSync { activity.showAgentImagePreview(Uri.fromFile(file), file.name) }
        saveAndCheck(activity, file.name, file.readBytes(), Uri.fromFile(file))
    }

    @Test fun saveFailureReenablesRetryAndSavingDoesNotBlockUi() = withImage { activity, file, uri ->
        val attempts = AtomicInteger()
        val release = CountDownLatch(1)
        lateinit var dialog: ChatImagePreviewDialog
        instrumentation.runOnMainSync {
            dialog = ChatImagePreviewDialog(activity, uri, file.name, "image/png", file.length()) {
                check(Looper.myLooper() != Looper.getMainLooper())
                if (attempts.incrementAndGet() == 1) Result.failure(IllegalStateException("fixture save failure"))
                else {
                    check(release.await(10, TimeUnit.SECONDS))
                    Result.success("Download/GalaxySSI/${file.name}")
                }
            }
            dialog.show()
        }
        try {
            awaitMain { tagged<Button>("save")?.isEnabled == true }
            instrumentation.runOnMainSync { tagged<Button>("save")!!.performClick() }
            awaitMain { attempts.get() == 1 && tagged<Button>("save")?.isEnabled == true }
            instrumentation.runOnMainSync {
                val button = tagged<Button>("save")!!
                assertEquals(activity.getString(R.string.peer_attachment_save), button.text)
                button.performClick(); button.performClick()
            }
            awaitMain { attempts.get() == 2 }
            instrumentation.runOnMainSync {
                assertFalse(tagged<Button>("save")!!.isEnabled)
                assertEquals(activity.getString(R.string.image_preview_saving), tagged<Button>("save")!!.text)
            }
            release.countDown()
            awaitMain { tagged<Button>("save")?.text == activity.getString(R.string.rich_output_saved) }
            assertEquals(2, attempts.get())
        } finally { release.countDown(); instrumentation.runOnMainSync { dialog.dismiss() } }
    }

    @Test fun missingSourceDoesNotPublishAnEmptyDownload() = withImage { activity, file, uri ->
        instrumentation.runOnMainSync { activity.showAgentImagePreview(uri, file.name, "image/png") }
        awaitMain { tagged<ImageView>("image")?.drawable != null }
        assertTrue(file.delete())
        instrumentation.runOnMainSync { tagged<Button>("save")!!.performClick() }
        awaitMain { tagged<Button>("save")?.isEnabled == true }
        assertNull(exported(file.name))
        instrumentation.runOnMainSync { assertEquals(activity.getString(R.string.peer_attachment_save), tagged<Button>("save")!!.text) }
    }

    @Test fun closingAndStoppingReleaseDecodedImage() = withImage { activity, file, uri ->
        lateinit var dialog: ChatImagePreviewDialog
        instrumentation.runOnMainSync { dialog = ChatImagePreviewDialog(activity, uri, file.name, "image/png"); dialog.show() }
        awaitMain { tagged<ImageView>("image")?.drawable != null }
        var decoded: Bitmap? = null
        instrumentation.runOnMainSync {
            decoded = (tagged<ImageView>("image")!!.drawable as BitmapDrawable).bitmap
            activity.finish()
        }
        awaitMain { !dialog.isShowing && decoded?.isRecycled == true }
        assertTrue(file.exists())
    }

    private fun saveAndCheck(activity: MainActivity, name: String, expected: ByteArray, source: Uri) {
        awaitMain { tagged<Button>("save")?.isEnabled == true && tagged<ImageView>("image")?.drawable != null }
        assertNull(exported(name))
        instrumentation.runOnMainSync {
            val button = tagged<Button>("save")!!
            val detail = tagged<TextView>("details")!!
            assertTrue(detail.text.startsWith("PNG"))
            val buttonBounds = Rect(); val detailBounds = Rect()
            button.getGlobalVisibleRect(buttonBounds); detail.getGlobalVisibleRect(detailBounds)
            assertTrue(detailBounds.right <= buttonBounds.left)
            assertTrue(buttonBounds.height() >= (48 * activity.resources.displayMetrics.density).toInt())
            button.performClick(); button.performClick()
        }
        awaitMain { tagged<Button>("save")?.text == activity.getString(R.string.rich_output_saved) }
        val saved = requireNotNull(exported(name))
        try {
            assertArrayEquals(expected, context.contentResolver.openInputStream(saved)!!.use { it.readBytes() })
            context.contentResolver.query(saved, arrayOf(MediaStore.Downloads.RELATIVE_PATH), null, null, null)!!.use {
                assertTrue(it.moveToFirst()); assertEquals("Download/GalaxySSI", it.getString(0).trimEnd('/'))
            }
            context.contentResolver.delete(saved, null, null)
            assertArrayEquals(expected, context.contentResolver.openInputStream(source)!!.use { it.readBytes() })
            instrumentation.runOnMainSync {
                assertNotNull(tagged<ImageView>("image")!!.drawable)
                assertFalse(tagged<Button>("save")!!.isEnabled)
                tagged<View>("back")!!.performClick()
                assertNull(tagged<View>("image"))
            }
        } finally { context.contentResolver.delete(saved, null, null) }
    }

    private fun exported(name: String): Uri? = context.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
        arrayOf(MediaStore.Downloads._ID), "${MediaStore.Downloads.DISPLAY_NAME} = ?", arrayOf(name), null)!!.use {
        assertTrue("Repeated taps exported multiple copies", it.count <= 1)
        if (it.moveToFirst()) ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, it.getLong(0)) else null
    }

    private fun <T : View> tagged(suffix: String): T? = WindowInspector.getGlobalWindowViews().firstNotNullOfOrNull {
        it.findViewWithTag<T>("chat-image-preview-$suffix")
    }

    private fun awaitMain(condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < until) {
            var done = false
            instrumentation.runOnMainSync { done = condition() }
            if (done) return
            SystemClock.sleep(30)
        }
        fail("Timed out waiting for image preview")
    }

    private fun withImage(test: (MainActivity, File, Uri) -> Unit) {
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)) as MainActivity
        val file = File(context.filesDir, "composer-attachments-v1/image-save-${UUID.randomUUID()}.png")
        file.parentFile!!.mkdirs()
        Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888).apply {
            eraseColor(Color.rgb(18, 155, 134))
            file.outputStream().use { compress(Bitmap.CompressFormat.PNG, 100, it) }
            recycle()
        }
        try { test(activity, file, LocalAttachmentUris.forFile(context, file, file.name, "image/png")) }
        finally {
            instrumentation.runOnMainSync { activity.finish() }
            exported(file.name)?.let { context.contentResolver.delete(it, null, null) }
            file.delete()
        }
    }
}
