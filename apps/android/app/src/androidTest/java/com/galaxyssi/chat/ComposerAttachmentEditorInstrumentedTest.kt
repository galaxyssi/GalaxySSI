package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.canhub.cropper.CropImageView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.MessageDigest
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ComposerAttachmentEditorInstrumentedTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val fixtures = mutableListOf<File>()

    @Test fun previewAndCancelCropPreserveOriginalAndDoNotCreateOutput() = withEditor { editor, original ->
        val before = digest(original)
        assertFalse(state(editor).getBoolean("cropping"))
        click(editor, R.string.composer_crop)
        await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
        instrumentation.waitForIdleSync()
        android.os.SystemClock.sleep(300)
        instrumentation.uiAutomation.takeScreenshot()?.let { screenshot ->
            File(context.getExternalFilesDir(null), "composer-crop-ui.png").outputStream().use {
                screenshot.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            screenshot.recycle()
        }
        assertTrue(state(editor).getBoolean("cropping"))
        onMain { editor.onBackPressed() }
        assertFalse(state(editor).getBoolean("cropping"))
        assertEquals(before, digest(original))
        assertTrue(state(editor).getStringArrayList("created").isNullOrEmpty())
    }

    @Test fun realCropWritesSeparateFilePreservesOriginalAndCanBeEditedAgain() = withEditor { editor, original ->
        val before = digest(original)
        click(editor, R.string.composer_crop)
        await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
        onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect = Rect(120, 160, 680, 840) }
        click(editor, R.string.composer_crop_done)
        await { !state(editor).getBoolean("cropping") }
        val cropped = ComposerAttachmentItem.decode(state(editor).getString(ComposerAttachmentEditorActivity.ITEMS)!!).single()
        assertTrue(cropped.isCropped)
        assertEquals(before, digest(original))
        val bitmap = context.contentResolver.openInputStream(android.net.Uri.parse(cropped.uri))!!.use { BitmapFactory.decodeStream(it) }
        assertEquals(560, bitmap.width)
        assertEquals(680, bitmap.height)
        bitmap.recycle()
        click(editor, R.string.composer_crop)
        await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
        assertEquals(cropped.source, onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).imageUri.toString() })
    }

    @Test fun rotationFlipRatioAndResetRemainInteractive() = withEditor { editor, _ ->
        click(editor, R.string.composer_crop)
        await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
        click(editor, R.string.composer_crop_rotate)
        assertEquals(270, onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).rotatedDegrees })
        click(editor, R.string.composer_crop_flip)
        assertTrue(onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).isFlippedHorizontally })
        onMain { findText(editor.window.decorView, "1:1")!!.performClick() }
        assertTrue(onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).isFixAspectRatio })
        click(editor, R.string.composer_crop_reset)
        assertFalse(onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).isFixAspectRatio })
        assertFalse(onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).isFlippedHorizontally })
        assertEquals(0, onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).rotatedDegrees })
    }

    @Test fun documentPreviewDoesNotOfferImageCrop() {
        val file = File(context.filesDir, "composer-attachments-v1/test-${UUID.randomUUID()}.pdf").apply {
            parentFile!!.mkdirs(); writeText("%PDF-1.4\n% test fixture\n")
        }
        fixtures.add(file)
        val item = ComposerAttachmentItem("pdf", LocalAttachmentUris.forFile(context, file, "test.pdf", "application/pdf").toString(),
            "test.pdf", "application/pdf", file.length())
        val editor = launch(listOf(item))
        try {
            assertNull(onMain { findText(editor.window.decorView, context.getString(R.string.composer_crop)) })
            assertEquals(View.GONE, onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).visibility })
        } finally { close(editor) }
    }

    @Test fun recreationPreservesCropModeAndTargetIdentity() = withEditor { editor, _ ->
        click(editor, R.string.composer_crop)
        await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
        val monitor = instrumentation.addMonitor(ComposerAttachmentEditorActivity::class.java.name, null, false)
        try {
            onMain { editor.recreate() }
            val replacement = instrumentation.waitForMonitorWithTimeout(monitor, 15_000) as ComposerAttachmentEditorActivity
            try {
                assertTrue(state(replacement).getBoolean("cropping"))
                assertEquals("test-conversation", replacement.intent.getStringExtra(ComposerAttachmentEditorActivity.TARGET))
                await { onMain { replacement.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
            } finally { close(replacement) }
        } finally { instrumentation.removeMonitor(monitor) }
    }

    private fun withEditor(test: (ComposerAttachmentEditorActivity, File) -> Unit) {
        val file = File(context.filesDir, "composer-attachments-v1/test-${UUID.randomUUID()}.jpg")
        file.parentFile!!.mkdirs()
        fixtures.add(file)
        val bitmap = Bitmap.createBitmap(800, 1000, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.rgb(245, 245, 242))
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.DKGRAY; textSize = 36f }
        canvas.drawText("GalaxySSI 图片裁剪测试", 80f, 100f, paint)
        for (line in 1..8) canvas.drawText("$line.  12 + 8 = ______", 80f, 150f + line * 80f, paint)
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 96, it) }
        bitmap.recycle()
        val item = ComposerAttachmentItem("test-photo", LocalAttachmentUris.forFile(context, file, "test.jpg", "image/jpeg").toString(),
            "test.jpg", "image/jpeg", file.length())
        val editor = launch(listOf(item))
        try {
            await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
            test(editor, file)
        } finally { close(editor) }
    }

    private fun launch(items: List<ComposerAttachmentItem>): ComposerAttachmentEditorActivity =
        instrumentation.startActivitySync(Intent(context, ComposerAttachmentEditorActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(ComposerAttachmentEditorActivity.ITEMS, ComposerAttachmentItem.encode(items))
            .putExtra(ComposerAttachmentEditorActivity.ROUTE, "agent")
            .putExtra(ComposerAttachmentEditorActivity.TARGET, "test-conversation")) as ComposerAttachmentEditorActivity

    private fun close(activity: Activity) {
        onMain { if (!activity.isDestroyed) activity.finish() }
        instrumentation.waitForIdleSync()
        fixtures.forEach(File::delete)
        fixtures.clear()
    }
    private fun state(activity: Activity): Bundle = onMain { Bundle().also { instrumentation.callActivityOnSaveInstanceState(activity, it) } }
    private fun click(activity: Activity, resource: Int) = onMain {
        val text = context.getString(resource)
        val view = findText(activity.window.decorView, text)
        if (view != null && view.isClickable) view.performClick()
        else findDescription(activity.window.decorView, text)!!.performClick()
    }
    private fun findText(view: View, text: String): TextView? =
        (view as? TextView)?.takeIf { it.text.toString() == text } ?: (view as? ViewGroup)?.let { group ->
            (0 until group.childCount).firstNotNullOfOrNull { findText(group.getChildAt(it), text) }
        }
    private fun findDescription(view: View, text: String): View? =
        view.takeIf { it.contentDescription?.toString() == text && it.isClickable } ?: (view as? ViewGroup)?.let { group ->
            (0 until group.childCount).firstNotNullOfOrNull { findDescription(group.getChildAt(it), text) }
        }
    private fun digest(file: File) = MessageDigest.getInstance("SHA-256").digest(file.readBytes()).toList()
    private fun await(condition: () -> Boolean) {
        val end = android.os.SystemClock.elapsedRealtime() + 20_000
        while (android.os.SystemClock.elapsedRealtime() < end) { if (condition()) return; Thread.sleep(100) }
        error("Editor did not reach expected state")
    }
    private fun <T> onMain(block: () -> T): T {
        var value: T? = null
        instrumentation.runOnMainSync { value = block() }
        @Suppress("UNCHECKED_CAST") return value as T
    }
}
