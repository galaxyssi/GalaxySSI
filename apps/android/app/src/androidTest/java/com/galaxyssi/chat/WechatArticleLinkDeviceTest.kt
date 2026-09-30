package com.galaxyssi.chat

import android.app.UiAutomation
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class WechatArticleLinkDeviceTest {
    @Test fun recognizesLiveMenuWhenExplicitlyRequested() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("wechat_live_menu") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val automation = instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        val image = requireNotNull(automation.takeScreenshot())
        val top = image.height * 53 / 100
        val crop = Bitmap.createBitmap(image, 0, top, image.width, image.height - top)
        val scaled = Bitmap.createScaledBitmap(crop, crop.width * 2, crop.height * 2, true)
        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        try {
            for ((name, bitmap) in listOf("original" to image, "scaled" to scaled)) {
                val text = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)), 15, TimeUnit.SECONDS)
                for (line in text.textBlocks.flatMap { it.lines }) {
                    if (name == "scaled" || (line.boundingBox?.top ?: 0) > top) {
                        Log.i("WechatMenuFixture", "$name line=${line.text} box=${line.boundingBox} elements=${line.elements.map { it.text to it.boundingBox }}")
                    }
                }
                assertTrue(WechatArticleLinkPolicy.isMenu(text.textBlocks.flatMap { it.lines }.map { it.text }))
            }
        } finally { recognizer.close(); scaled.recycle(); crop.recycle(); image.recycle() }
    }
    @Test fun recognizesExplicitMenuFixture() {
        val path = InstrumentationRegistry.getArguments().getString("wechat_menu_fixture").orEmpty()
        assumeTrue(path.matches(Regex("/sdcard/galaxyssi-[a-z0-9-]+\\.png")))
        val automation = InstrumentationRegistry.getInstrumentation()
            .getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES)
        val image = ParcelFileDescriptor.AutoCloseInputStream(automation.executeShellCommand("cat $path"))
            .use { BitmapFactory.decodeStream(it) }
        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        try {
            val text = Tasks.await(recognizer.process(InputImage.fromBitmap(image, 0)), 15, TimeUnit.SECONDS)
            val lines = text.textBlocks.flatMap { it.lines }
            assertTrue(WechatArticleLinkPolicy.isMenu(lines.map { it.text }))
            val buttons = lines.flatMap { line -> line.elements }.flatMap { element ->
                val bounds = element.boundingBox
                WechatArticleMenuLayout.labels.mapNotNull { label ->
                    if (bounds == null || !element.text.filterNot(Char::isWhitespace).contains(label)) null
                    else WechatMenuLabel(label, bounds.left, bounds.top, bounds.right, bounds.bottom)
                }
            }
            val menu = WechatArticleMenuLayout.resolve(buttons, image.width, image.height)
            Log.i("WechatMenuFixture", "Menu geometry=$menu")
            assertTrue("Second row must be found below the share row", menu != null && menu.iconY > image.height * .7)
            if (path.endsWith("-copy-menu.png")) assertTrue("Copy link must be found", menu?.copyX != null)
        } finally { recognizer.close(); image.recycle() }
    }
}
