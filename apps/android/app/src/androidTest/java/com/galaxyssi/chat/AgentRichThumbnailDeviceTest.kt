package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlin.math.abs
import kotlin.math.roundToInt
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRichThumbnailDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun documentAndImagePreviewsKeepAllFourCorners() {
        verify(listOf(1600 to 400), gallery = false)
        verify(listOf(400 to 1600), gallery = false)
        verify(listOf(600 to 600), gallery = false)
    }

    @Test fun galleryPreviewsKeepAllFourCorners() {
        verify(listOf(1600 to 400, 400 to 1600), gallery = true)
    }

    private fun verify(sizes: List<Pair<Int, Int>>, gallery: Boolean) {
        val context = instrumentation.targetContext
        val files = sizes.map { (width, height) ->
            File.createTempFile("thumbnail-corners-", ".png", context.cacheDir).also { file ->
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                canvas.drawColor(Color.WHITE)
                corners.forEach { (x, y, color) ->
                    canvas.drawRect((x - .05f) * width, (y - .05f) * height,
                        (x + .05f) * width, (y + .05f) * height, Paint().apply { this.color = color })
                }
                file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
            }
        }
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var root: View
                var images = emptyList<ImageView>()
                scenario.onActivity { activity ->
                    val block = AgentRichBlock(id = "thumbnail-test", type = if (gallery)
                        AgentRichBlockType.GALLERY else AgentRichBlockType.IMAGE,
                        title = "Preview", uri = if (gallery) "" else Uri.fromFile(files.single()).toString(),
                        mimeType = "image/png", rows = if (gallery) files.mapIndexed { index, file ->
                            listOf(Uri.fromFile(file).toString(), "Preview $index", "image/png")
                        } else emptyList())
                    root = AgentRichContentView(activity, {}, {}, { _, _ -> }).create(AgentTranscriptEntry(
                        id = "thumbnail-test", role = AgentTranscriptRole.ASSISTANT, text = "",
                        timestampMillis = 1L, richOutputJson = AgentRichContentCodec.encode(listOf(block))))
                    activity.findViewById<ViewGroup>(android.R.id.content).addView(root,
                        ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
                }
                val deadline = SystemClock.elapsedRealtime() + 15000
                do {
                    scenario.onActivity {
                        images = descendants(root).filterIsInstance<ImageView>().filter {
                            it.isClickable && it.drawable?.intrinsicWidth in sizes.map(Pair<Int, Int>::first) && it.width > 0
                        }
                    }
                    if (images.size == sizes.size) break
                    SystemClock.sleep(100)
                } while (SystemClock.elapsedRealtime() < deadline)
                assertEquals("All previews must load", sizes.size, images.size)
                SystemClock.sleep(250)
                val points = mutableListOf<Triple<Int, Int, Int>>()
                scenario.onActivity {
                    images.forEach { image ->
                        assertEquals(ImageView.ScaleType.FIT_CENTER, image.scaleType)
                        val drawable = requireNotNull(image.drawable)
                        val bounds = RectF(0f, 0f, drawable.intrinsicWidth.toFloat(), drawable.intrinsicHeight.toFloat())
                        image.imageMatrix.mapRect(bounds)
                        assertTrue("No crop: $bounds in ${image.width}x${image.height}",
                            bounds.left >= -1 && bounds.top >= -1 && bounds.right <= image.width + 1 && bounds.bottom <= image.height + 1)
                        val location = IntArray(2).also(image::getLocationOnScreen)
                        corners.forEach { (x, y, color) ->
                            val point = floatArrayOf(x * drawable.intrinsicWidth, y * drawable.intrinsicHeight)
                            image.imageMatrix.mapPoints(point)
                            points += Triple((point[0] + location[0]).roundToInt(), (point[1] + location[1]).roundToInt(), color)
                        }
                    }
                }
                val screenshot = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
                try {
                    points.forEach { (x, y, expected) ->
                        assertTrue("Corner must be on screen", x in 0 until screenshot.width && y in 0 until screenshot.height)
                        val actual = screenshot.getPixel(x, y)
                        assertTrue("Corner pixel $x,$y: $actual != $expected",
                            abs(Color.red(actual) - Color.red(expected)) < 25 &&
                                abs(Color.green(actual) - Color.green(expected)) < 25 &&
                                abs(Color.blue(actual) - Color.blue(expected)) < 25)
                    }
                } finally { screenshot.recycle() }
                scenario.onActivity { (root.parent as ViewGroup).removeView(root) }
            }
        } finally { files.forEach(File::delete) }
    }

    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()

    private val corners = listOf(Triple(.08f, .08f, Color.RED), Triple(.92f, .08f, Color.BLUE),
        Triple(.08f, .92f, Color.GREEN), Triple(.92f, .92f, Color.MAGENTA))
}
