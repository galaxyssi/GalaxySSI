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
        click(editor, R.string.composer_crop_use)
        await { onMain { editor.isFinishing } }
        val cropped = ComposerAttachmentItem.decode(state(editor).getString(ComposerAttachmentEditorActivity.ITEMS)!!).single()
        assertTrue(cropped.isCropped)
        assertEquals(before, digest(original))
        val bitmap = context.contentResolver.openInputStream(android.net.Uri.parse(cropped.uri))!!.use { BitmapFactory.decodeStream(it) }
        assertEquals(560, bitmap.width)
        assertEquals(680, bitmap.height)
        bitmap.recycle()
        assertTrue(onMain { editor.isFinishing })
        val reopened = launch(listOf(cropped))
        try {
            click(reopened, R.string.composer_crop)
            await { onMain { reopened.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
            assertEquals(cropped.source, onMain { reopened.findViewById<CropImageView>(R.id.composerCropImage).imageUri.toString() })
        } finally {
            onMain { reopened.finish() }
            LocalAttachmentUris.resolve(context, android.net.Uri.parse(cropped.uri))?.delete()
        }
    }

    @Test fun rotationFlipRatioAndResetRemainInteractive() = withEditor { editor, _ ->
        click(editor, R.string.composer_crop)
        await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
        click(editor, R.string.composer_crop_rotate)
        assertEquals(270, onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).rotatedDegrees })
        click(editor, R.string.composer_crop_more)
        clickPopup(context.getString(R.string.composer_crop_flip))
        assertTrue(onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).isFlippedHorizontally })
        click(editor, R.string.composer_crop_ratio)
        clickPopup("1:1")
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
            assertPreviewActionsCentered(editor, 1)
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

    @Test fun originalQualityDefaultsOffAndSurvivesRecreation() = withEditor { editor, original ->
        val checkbox = onMain { editor.window.decorView.findViewWithTag<android.widget.CheckBox>("composer_original_quality") }
        assertFalse(onMain { checkbox.isChecked })
        val hash = digest(original)
        onMain { checkbox.performClick() }
        assertTrue(ComposerAttachmentItem.decode(state(editor).getString(ComposerAttachmentEditorActivity.ITEMS)!!).single().sendOriginal)
        val monitor = instrumentation.addMonitor(ComposerAttachmentEditorActivity::class.java.name, null, false)
        try {
            onMain { editor.recreate() }
            val replacement = instrumentation.waitForMonitorWithTimeout(monitor, 15_000) as ComposerAttachmentEditorActivity
            try {
                assertTrue(onMain { replacement.window.decorView.findViewWithTag<android.widget.CheckBox>("composer_original_quality").isChecked })
                assertEquals(hash, digest(original))
            } finally { onMain { replacement.finish() } }
        } finally { instrumentation.removeMonitor(monitor) }
    }

    @Test fun previewActionsRemainCenteredAfterQualityAndCropChanges() = withEditor { editor, _ ->
        assertPreviewActionsCentered(editor, 3)
        onMain { editor.window.decorView.findViewWithTag<android.widget.CheckBox>("composer_original_quality").performClick() }
        assertPreviewActionsCentered(editor, 3)
        click(editor, R.string.composer_crop)
        await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
        onMain { editor.onBackPressed() }
        assertPreviewActionsCentered(editor, 3)
        instrumentation.uiAutomation.takeScreenshot()?.let { screenshot ->
            File(context.getExternalFilesDir(null), "composer-preview-centered.png").outputStream().use {
                screenshot.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
            screenshot.recycle()
        }
    }

    @Test fun cameraPreviewCentersAllFourActionsIncludingRetake() = withEditor(camera = true) { editor, _ ->
        assertPreviewActionsCentered(editor, 4)
        click(editor, R.string.composer_crop_retake)
        await { onMain { editor.isFinishing } }
    }

    @Test fun centeredDeleteRemovesTheDraftButNotTheSourceFile() = withEditor { editor, original ->
        val before = digest(original)
        click(editor, R.string.agent_attachment_remove)
        await { onMain { editor.isFinishing } }
        assertTrue(ComposerAttachmentItem.decode(state(editor).getString(ComposerAttachmentEditorActivity.ITEMS)!!).isEmpty())
        assertEquals(before, digest(original))
    }

    private fun assertPreviewActionsCentered(editor: Activity, count: Int) {
        instrumentation.waitForIdleSync()
        onMain {
            val row = editor.window.decorView.findViewWithTag<android.widget.LinearLayout>("composer_preview_actions")
            assertNotNull(row)
            val width = row.width
            val direction = row.layoutDirection
            val density = editor.resources.displayMetrics.density
            try {
                for (dpWidth in listOf(320, 360, 412, 800)) {
                    for (rtl in listOf(false, true)) {
                        row.layoutDirection = if (rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
                        row.measure(View.MeasureSpec.makeMeasureSpec((dpWidth * density).toInt(), View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                        row.layout(row.left, row.top, row.left + row.measuredWidth, row.top + row.measuredHeight)
                        assertEquals(count, row.childCount)
                        val cellWidth = (row.width - row.paddingLeft - row.paddingRight).toFloat() / count
                        val centerY = row.paddingTop + (row.height - row.paddingTop - row.paddingBottom) / 2f
                        repeat(count) { index ->
                            val slot = row.getChildAt(index) as android.widget.FrameLayout
                            val button = slot.getChildAt(0)
                            assertEquals("Every preview action has equal space", cellWidth, slot.width.toFloat(), 1f)
                            assertEquals("Action is horizontally centered", slot.width / 2f,
                                button.left + button.width / 2f, 1f)
                            assertEquals("All action centers share the same row", centerY,
                                slot.top + button.top + button.height / 2f, 1f)
                            assertTrue("Action $index has a 48 dp wide touch target at $dpWidth dp (RTL=$rtl): ${button.width}",
                                button.width >= (48 * density).toInt())
                            assertTrue("Action $index has a 48 dp tall touch target",
                                button.height >= (48 * density).toInt())
                            assertTrue(button.left >= 0 && button.right <= slot.width)
                        }
                    }
                }
            } finally {
                row.layoutDirection = direction
                row.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                row.layout(row.left, row.top, row.left + width, row.top + row.measuredHeight)
                row.requestLayout()
            }
        }
    }

    private fun clickPopup(text: String) {
        await {
            instrumentation.uiAutomation.rootInActiveWindow?.findAccessibilityNodeInfosByText(text)
                ?.any { match ->
                    // Popup labels can be non-clickable children of the actual menu row.
                    var node: android.view.accessibility.AccessibilityNodeInfo? = match
                    while (node != null && !node.isClickable) node = node.parent
                    node?.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK) == true
                } == true
        }
        instrumentation.waitForIdleSync()
    }

    private fun withEditor(camera: Boolean = false, test: (ComposerAttachmentEditorActivity, File) -> Unit) {
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
        val editor = launch(listOf(item), camera = camera)
        try {
            await { onMain { editor.findViewById<CropImageView>(R.id.composerCropImage).cropRect != null } }
            test(editor, file)
        } finally { close(editor) }
    }

    private fun launch(items: List<ComposerAttachmentItem>, camera: Boolean = false): ComposerAttachmentEditorActivity =
        instrumentation.startActivitySync(Intent(context, ComposerAttachmentEditorActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(ComposerAttachmentEditorActivity.ITEMS, ComposerAttachmentItem.encode(items))
            .putExtra(ComposerAttachmentEditorActivity.CAMERA, camera)
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
