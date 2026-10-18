package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.BitmapDrawable
import android.view.ViewGroup
import android.widget.ImageView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PeerImageThumbnailDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private lateinit var directory: File

    @Before fun setUp() {
        directory = File(context.filesDir, "composer-attachments-v1/thumbnail-test-${UUID.randomUUID()}")
        check(directory.mkdirs())
        PeerImageThumbnailRepository.clearRuntimeCache()
    }

    @After fun tearDown() {
        PeerImageThumbnailRepository.clearRuntimeCache()
        directory.deleteRecursively()
    }

    @Test fun sharedDirectoryIgnoresLegacyThumbnailAndSurvivesMemoryClear() {
        val red = image("first.png", Color.RED)
        val blue = image("second.png", Color.BLUE)
        val green = image("third.png", Color.GREEN)
        val legacy = File(directory, PeerImageThumbnailPolicy.LEGACY_FILE_NAME)
        storeColor(legacy, Color.MAGENTA)
        val originals = listOf(red, blue, green).map { File(directory, it.name).readBytes() }
        try {
            listOf(red, blue, green).zip(listOf(Color.RED, Color.BLUE, Color.GREEN)).forEach { (item, color) ->
                assertColor(color, load(item))
                assertTrue(AttachmentLocalStore.isStored(PeerImageThumbnailPolicy.storedFile(File(directory, item.name), item)))
            }
            assertFalse("Ambiguous legacy thumbnail must be retired", legacy.exists())
            PeerImageThumbnailRepository.clearRuntimeCache()
            listOf(green, red, blue).zip(listOf(Color.GREEN, Color.RED, Color.BLUE)).forEach { (item, color) ->
                assertColor(color, load(item))
            }
            listOf(red, blue, green).zip(originals).forEach { (item, bytes) ->
                assertArrayEquals("Original attachment must not change", bytes, File(directory, item.name).readBytes())
            }
        } finally { originals.forEach { it.fill(0) } }
    }

    @Test fun simultaneousImagesDoNotShareInFlightResults() {
        val items = listOf(image("red.png", Color.RED), image("blue.png", Color.BLUE))
        val done = CountDownLatch(items.size)
        val results = arrayOfNulls<Bitmap>(items.size)
        instrumentation.runOnMainSync {
            items.forEachIndexed { index, item ->
                PeerImageThumbnailRepository.load(context, item, 96, 96) {
                    results[index] = it
                    done.countDown()
                }
            }
        }
        assertTrue("Thumbnails must finish", done.await(10, TimeUnit.SECONDS))
        assertColor(Color.RED, results[0])
        assertColor(Color.BLUE, results[1])
    }

    @Test fun removingOneImageDoesNotChangeItsNeighbour() {
        val first = image("first.png", Color.RED)
        val second = image("second.png", Color.BLUE)
        load(first)
        val secondBitmap = load(second)
        PeerImageThumbnailRepository.remove(listOf(first))
        File(directory, first.name).delete()
        assertSame(secondBitmap, load(second))
        PeerImageThumbnailRepository.clearRuntimeCache()
        assertColor(Color.BLUE, load(second))
    }

    @Test fun reboundViewRejectsThePreviousImageResult() {
        val first = image("first.png", Color.RED)
        val second = image("second.png", Color.BLUE)
        lateinit var view: PeerImageAttachmentView
        instrumentation.runOnMainSync {
            view = PeerImageAttachmentView(context).apply {
                layoutParams = ViewGroup.LayoutParams(96, 96)
                bind(first, {}, {})
                bind(second, {}, {})
            }
        }
        val previewSize = (AGENT_IMAGE_THUMBNAIL_HEIGHT_DP * 2 * context.resources.displayMetrics.density).toInt()
        load(first, previewSize)
        load(second, previewSize)
        instrumentation.runOnMainSync {
            val drawable = (view.getChildAt(0) as ImageView).drawable as BitmapDrawable
            assertColor(Color.BLUE, drawable.bitmap)
        }
    }

    @Test fun unreadableStoredThumbnailIsRebuiltAndPersisted() {
        val item = image("photo.png", Color.GREEN)
        val thumbnail = PeerImageThumbnailPolicy.storedFile(File(directory, item.name), item)
        AttachmentLocalStore.storeBytes(byteArrayOf(1, 2, 3), thumbnail)
        assertColor(Color.GREEN, load(item))
        PeerImageThumbnailRepository.clearRuntimeCache()
        val thumbnailUri = LocalAttachmentUris.forFile(context, thumbnail, "thumbnail.jpg", "image/jpeg")
        assertColor(Color.GREEN, AgentImagePipeline.loadPreview(context, thumbnailUri, 96, 96))
    }

    private fun image(name: String, color: Int): PeerChatAttachment {
        val original = File(directory, name)
        storeColor(original, color)
        return PeerChatAttachment(name, "image/png", original.length(),
            uri = LocalAttachmentUris.forFile(context, original, name, "image/png").toString())
    }

    private fun storeColor(file: File, color: Int) {
        val bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
        val output = ByteArrayOutputStream()
        try {
            bitmap.eraseColor(color)
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
            val bytes = output.toByteArray()
            try { AttachmentLocalStore.storeBytes(bytes, file) } finally { bytes.fill(0) }
        } finally { bitmap.recycle(); output.close() }
    }

    private fun load(item: PeerChatAttachment, size: Int = 96): Bitmap? {
        val done = CountDownLatch(1)
        var bitmap: Bitmap? = null
        instrumentation.runOnMainSync {
            PeerImageThumbnailRepository.load(context, item, size, size) { bitmap = it; done.countDown() }
        }
        assertTrue("Thumbnail must finish", done.await(10, TimeUnit.SECONDS))
        return bitmap
    }

    private fun assertColor(expected: Int, bitmap: Bitmap?) {
        assertNotNull("Thumbnail must decode", bitmap)
        val actual = requireNotNull(bitmap).getPixel(bitmap.width / 2, bitmap.height / 2)
        assertTrue("Wrong thumbnail: $actual instead of $expected",
            abs(Color.red(expected) - Color.red(actual)) <= 5 &&
                abs(Color.green(expected) - Color.green(actual)) <= 5 &&
                abs(Color.blue(expected) - Color.blue(actual)) <= 5)
    }
}
