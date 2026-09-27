package com.galaxyssi.chat

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean

internal object PhoneUiScreenshot {
    fun capture(context: Context, expectedWindowId: Int? = null): File {
        check(Looper.myLooper() != Looper.getMainLooper())
        check(Build.VERSION.SDK_INT >= 30) { "Screen capture requires Android 11 or newer" }
        val service = requireNotNull(GalaxySSIAccessibilityService.targetService()) { "Screen access is not enabled" }
        val window = requireNotNull(GalaxySSIAccessibilityService.targetWindowId()) { "No target App window" }
        check(expectedWindowId == null || window == expectedWindowId) { "Target window changed before capture" }
        val result = AtomicReference<Bitmap?>()
        val error = AtomicReference<String?>()
        val done = CountDownLatch(1)
        val accepting = AtomicBoolean(true)
        val main = Handler(Looper.getMainLooper())
        val callback = object : AccessibilityService.TakeScreenshotCallback {
            override fun onSuccess(value: AccessibilityService.ScreenshotResult) {
                try {
                    val bitmap = Bitmap.wrapHardwareBuffer(value.hardwareBuffer, value.colorSpace)
                        ?.copy(Bitmap.Config.ARGB_8888, false)
                    if (!accepting.get() || !result.compareAndSet(null, bitmap)) bitmap?.recycle()
                    if (!accepting.get()) result.getAndSet(null)?.recycle()
                } finally { value.hardwareBuffer.close(); done.countDown() }
            }
            override fun onFailure(code: Int) { error.set("Target screenshot unavailable ($code)"); done.countDown() }
        }
        main.post {
            runCatching {
                if (Build.VERSION.SDK_INT >= 34) service.takeScreenshotOfWindow(window, { main.post(it) }, callback)
                else service.captureWithoutAssistant {
                    service.takeScreenshot(Display.DEFAULT_DISPLAY, { main.post(it) }, callback)
                }
            }.onFailure { error.set(it.message); done.countDown() }
        }
        try {
            check(done.await(5, TimeUnit.SECONDS)) { "Screenshot timed out" }
            val bitmap = requireNotNull(result.getAndSet(null)) { error.get() ?: "Screenshot contains no image" }
            try {
                val file = File(context.filesDir, "agent-rich-output-v2/screen-assistant/${UUID.randomUUID()}.jpg")
                check(file.parentFile!!.isDirectory || file.parentFile!!.mkdirs())
                file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
                return file
            } finally { bitmap.recycle() }
        } finally {
            accepting.set(false)
            result.getAndSet(null)?.recycle()
            main.post { service.restoreAssistantAfterCapture() }
        }
    }
}
