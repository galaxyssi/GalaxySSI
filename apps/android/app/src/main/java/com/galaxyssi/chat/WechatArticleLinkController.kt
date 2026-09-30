package com.galaxyssi.chat

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.KeyguardManager
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions

/** Explicit, local-only WeChat menu action. Screenshots never leave memory or reach an Agent. */
internal class WechatArticleLinkController(private val service: GalaxySSIAccessibilityService) {
    private val handler = Handler(Looper.getMainLooper())
    private val recognizerDelegate = lazy { TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build()) }
    private val recognizer by recognizerDelegate
    private var generation = 0
    private var running = false
    private var awaitingCopy = false
    private var copyAttempts = 0
    private var systemCopyConfirmed = false
    private var hidden = false
    private var closed = false
    private var addedToastEvents = false

    fun start() {
        if (running || closed) return
        if (PhoneAssistantTaskControl.hasActiveTask()) { toast(R.string.wechat_link_busy); return }
        if (!isTarget()) { toast(R.string.wechat_link_open_article); return }
        running = true
        awaitingCopy = false
        copyAttempts = 0
        systemCopyConfirmed = false
        val token = ++generation
        val info = service.serviceInfo
        addedToastEvents = info.eventTypes and AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED == 0
        if (addedToastEvents) {
            info.eventTypes = info.eventTypes or AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED
            service.serviceInfo = info
        }
        Log.i(TAG, "Copy link started")
        // A progress Toast covers WeChat's second-row labels in screenshots.
        // Keep this visual action unobstructed; report only its final outcome.
        handler.postDelayed({ if (valid(token)) finish(R.string.wechat_link_failed) }, 20_000)
        inspect(token, 0, false)
    }

    fun onEvent(event: AccessibilityEvent?) {
        if (!running || !awaitingCopy || event == null ||
            event.eventType != AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) return
        if (event.packageName?.toString() == "com.android.systemui" && isTarget() &&
            event.text.any { WechatArticleLinkPolicy.isSystemConfirmation(it.toString()) }) {
            // A system copy toast is provisional until the WeChat menu has also closed.
            systemCopyConfirmed = true
            return
        }
        if (event.packageName?.toString() != PACKAGE) return
        if (event.text.any { WechatArticleLinkPolicy.isConfirmation(it.toString()) }) {
            Log.i(TAG, "WeChat confirmed clipboard copy")
            finish(R.string.wechat_link_copied)
        }
    }

    fun close() {
        closed = true
        running = false
        generation++
        handler.removeCallbacksAndMessages(null)
        restoreEvents()
        restore()
        if (recognizerDelegate.isInitialized()) recognizer.close()
    }

    private fun isTarget() = ScreenAssistantSettings.enabled(service) &&
        !service.getSystemService(KeyguardManager::class.java).isKeyguardLocked &&
        service.targetRoot()?.packageName?.toString() == PACKAGE
    private fun valid(token: Int) = !closed && running && token == generation
    private fun restore() { if (hidden) { hidden = false; service.restoreAssistantAfterCapture() } }
    private fun restoreEvents() {
        if (!addedToastEvents) return
        addedToastEvents = false
        val info = service.serviceInfo
        info.eventTypes = info.eventTypes and AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED.inv()
        service.serviceInfo = info
    }
    private fun toast(message: Int) = Toast.makeText(service, message, Toast.LENGTH_SHORT).show()
    private fun finish(message: Int) {
        if (!running) return
        running = false
        awaitingCopy = false
        generation++
        handler.removeCallbacksAndMessages(null)
        restoreEvents()
        restore()
        Log.i(TAG, "Copy link finished status=$message")
        toast(message)
    }

    private fun inspect(token: Int, swipes: Int, opened: Boolean, retries: Int = 0) {
        if (!valid(token)) return
        if (!isTarget()) { finish(R.string.wechat_link_interrupted); return }
        hidden = true
        service.captureWithoutAssistant {
            if (!valid(token)) { restore(); return@captureWithoutAssistant }
            runCatching {
                service.takeScreenshot(Display.DEFAULT_DISPLAY, service.mainExecutor,
                    object : AccessibilityService.TakeScreenshotCallback {
                        override fun onFailure(errorCode: Int) {
                            restore()
                            if (valid(token)) finish(R.string.wechat_link_failed)
                        }
                        override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                            val bitmap = runCatching { try {
                                Bitmap.wrapHardwareBuffer(result.hardwareBuffer, result.colorSpace)
                                    ?.copy(Bitmap.Config.ARGB_8888, false)
                            } finally { result.hardwareBuffer.close() } }.getOrNull()
                            restore()
                            if (!valid(token)) { bitmap?.recycle(); return }
                            if (bitmap == null) { finish(R.string.wechat_link_failed); return }
                            // Isolate the bottom sheet from article text and improve small gray labels.
                            val cropTop = if (opened) bitmap.height * 53 / 100 else 0
                            val cropped = if (cropTop > 0) Bitmap.createBitmap(bitmap, 0, cropTop, bitmap.width, bitmap.height - cropTop) else bitmap
                            val scale = if (cropTop > 0) 2 else 1
                            val ocrImage = if (scale == 2) Bitmap.createScaledBitmap(cropped, cropped.width * 2, cropped.height * 2, true) else cropped
                            recognizer.process(InputImage.fromBitmap(ocrImage, 0))
                                .addOnSuccessListener { text ->
                                    if (!valid(token)) return@addOnSuccessListener
                                    if (!isTarget()) { finish(R.string.wechat_link_interrupted); return@addOnSuccessListener }
                                    val lines = text.textBlocks.flatMap { it.lines }
                                    val labels = lines.map { it.text }
                                    val buttons = lines.flatMap { line ->
                                        val elements = line.elements
                                        val joined = elements.joinToString("") { it.text.filterNot(Char::isWhitespace).lowercase() }
                                        WechatArticleMenuLayout.labels.mapNotNull { label ->
                                            val start = joined.indexOf(label)
                                            if (start < 0) null else {
                                                var offset = 0
                                                val bounds = Rect()
                                                elements.forEach { element ->
                                                    val end = offset + element.text.filterNot(Char::isWhitespace).length
                                                    if (offset < start + label.length && end > start) element.boundingBox?.let(bounds::union)
                                                    offset = end
                                                }
                                                if (bounds.isEmpty) null else WechatMenuLabel(label, bounds.left / scale,
                                                    bounds.top / scale + cropTop, bounds.right / scale, bounds.bottom / scale + cropTop)
                                            }
                                        }
                                    }
                                    val menu = WechatArticleMenuLayout.resolve(buttons, bitmap.width, bitmap.height)
                                    Log.i(TAG, "Observed ${bitmap.width}x${bitmap.height} menu=$menu buttons=$buttons swipe=$swipes")
                                    val menuVisible = WechatArticleLinkPolicy.isMenu(labels)
                                    if (awaitingCopy) {
                                        val confirmed = lines.any { line ->
                                            (line.boundingBox?.centerY() ?: 0) / scale + cropTop > bitmap.height * .65 &&
                                                WechatArticleLinkPolicy.isConfirmation(line.text)
                                        }
                                        val systemToast = lines.any { line ->
                                            (line.boundingBox?.centerY() ?: 0) / scale + cropTop > bitmap.height * .65 &&
                                                WechatArticleLinkPolicy.isSystemConfirmation(line.text)
                                        }
                                        if ((confirmed || systemCopyConfirmed || systemToast) && !menuVisible) {
                                            Log.i(TAG, "WeChat confirmed clipboard copy visually")
                                            finish(R.string.wechat_link_copied)
                                        } else if (WechatArticleLinkPolicy.shouldRetryCopy(menuVisible,
                                                menu?.copyX != null && menu.copyLabelY != null, copyAttempts)) {
                                            Log.i(TAG, "Copy menu remains open; retrying freshly located label")
                                            copy(token, requireNotNull(menu), swipes)
                                        } else if (retries < 2) later(token) { inspect(token, swipes, true, retries + 1) }
                                        else finish(R.string.wechat_link_unconfirmed)
                                        return@addOnSuccessListener
                                    }
                                    if (menuVisible) {
                                        if (menu == null) {
                                            if (retries < 2) later(token) { inspect(token, swipes, true, retries + 1) }
                                            else finish(R.string.wechat_link_failed)
                                        } else if (menu.copyX != null) {
                                            copy(token, menu, swipes)
                                        } else if (swipes < 3) {
                                            gesture(token, bitmap.width * .80f, menu.iconY.toFloat(),
                                                bitmap.width * .35f, menu.iconY.toFloat(), 380) {
                                                later(token) { inspect(token, swipes + 1, true) }
                                            }
                                        } else finish(R.string.wechat_link_failed)
                                    } else if (!opened && WechatArticleLinkPolicy.isArticle(labels)) {
                                        val more = WechatArticleLinkPolicy.moreButton(bitmap.width, bitmap.height, bitmap::getPixel)
                                        if (more == null) finish(R.string.wechat_link_failed)
                                        else tap(token, Rect(more.first - 2, more.second - 2, more.first + 2, more.second + 2)) {
                                            later(token) { inspect(token, 0, true) }
                                        }
                                    } else if (opened && retries < 2) later(token) { inspect(token, swipes, true, retries + 1) }
                                    else finish(R.string.wechat_link_open_article)
                                }.addOnFailureListener { if (valid(token)) finish(R.string.wechat_link_failed) }
                                .addOnCompleteListener {
                                    if (ocrImage !== cropped) ocrImage.recycle()
                                    if (cropped !== bitmap) cropped.recycle()
                                    bitmap.recycle()
                                }
                        }
                    })
            }.onFailure { restore(); if (valid(token)) finish(R.string.wechat_link_failed) }
        }
    }

    private fun later(token: Int, action: () -> Unit) = handler.postDelayed({ if (valid(token)) action() }, 650)
    private fun copy(token: Int, menu: WechatArticleMenu, swipes: Int) {
        val x = menu.copyX ?: return
        val y = menu.copyLabelY ?: return
        awaitingCopy = true
        copyAttempts++
        tap(token, Rect(x - 2, y - 2, x + 2, y + 2)) {
            later(token) { inspect(token, swipes, true) }
        }
    }
    private fun tap(token: Int, rect: Rect, completed: () -> Unit) = gesture(token,
        rect.centerX().toFloat(), rect.centerY().toFloat(), rect.centerX().toFloat(), rect.centerY().toFloat(), 80, completed)
    private fun gesture(token: Int, x: Float, y: Float, endX: Float, endY: Float, duration: Long, completed: () -> Unit) {
        if (!valid(token)) return
        if (!isTarget()) { finish(R.string.wechat_link_interrupted); return }
        // Restoring an overlay after OCR must not intercept the next injected gesture.
        hidden = true
        service.captureWithoutAssistant {
            if (!valid(token)) { restore(); return@captureWithoutAssistant }
            if (!isTarget()) { finish(R.string.wechat_link_interrupted); return@captureWithoutAssistant }
            dispatchGesture(token, x, y, endX, endY, duration, completed)
        }
    }

    private fun dispatchGesture(token: Int, x: Float, y: Float, endX: Float, endY: Float,
        duration: Long, completed: () -> Unit) {
        Log.i(TAG, "Gesture from=($x,$y) to=($endX,$endY)")
        val path = Path().apply { moveTo(x, y); lineTo(endX, endY) }
        val accepted = service.dispatchGesture(GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, duration)).build(),
            object : AccessibilityService.GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription) {
                    if (valid(token)) { restore(); completed() }
                }
                override fun onCancelled(gestureDescription: GestureDescription) {
                    if (valid(token)) finish(R.string.wechat_link_interrupted)
                }
            }, handler)
        if (!accepted) finish(R.string.wechat_link_failed)
    }

    companion object {
        private const val PACKAGE = "com.tencent.mm"
        private const val TAG = "WechatArticleLink"
    }
}
