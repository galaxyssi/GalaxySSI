package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ScreenAssistantVisualPageDeviceTest {
    @Test fun opaquePageCollectsAllViewportsAndDoesNotClaimVerifiedFullText() = collectFixture(false, false)
    @Test fun targetSwitchStopsFurtherScrolling() = collectFixture(true, false)
    @Test fun cancellationStopsFurtherScrolling() = collectFixture(false, true)

    private fun collectFixture(changeTarget: Boolean, cancel: Boolean) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val request = ScreenAssistantAnalysisRequest()
        val session = ScreenAssistantPageCollection(request)
        val store = ScreenAssistantPageStore(context)
        val id = store.create()
        val lock = "page-capture:$id"
        val first = PhoneUiSnapshot(42, "fixture.article", "opaque", emptyList(), false)
        var position = 2
        var moves = 0
        var switched = false
        PhoneAssistantTaskControl.bind(lock, request)
        val collector = ScreenAssistantVisualPageCollector(context,
            read = { if (switched) first.copy(windowId = 43) else first },
            screenshot = {
                val bitmap = Bitmap.createBitmap(320, 640, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                canvas.drawColor(Color.WHITE)
                val paint = Paint().apply { color = Color.rgb(position * 45, 100, 220); textSize = 32f }
                canvas.drawRect(30f, 180f + position * 30, 280f, 380f + position * 30, paint)
                paint.color = Color.BLACK
                canvas.drawText("Page $position", 30f, 140f, paint)
                File(context.cacheDir, "page-fixture-${UUID.randomUUID()}.jpg").also { file ->
                    try { file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) } }
                    finally { bitmap.recycle() }
                }
            }, gesture = { _, forward, checkpoint ->
                checkpoint()
                moves++
                position = (position + if (forward) 1 else -1).coerceIn(0, 4)
                if (changeTarget && moves == 2) switched = true
                if (cancel && moves == 2) request.cancel()
                true
            }, settleMillis = 0, extractText = { listOf("Fixture page $position") })
        try {
            if (changeTarget) {
                assertThrows(PageCaptureInterruptedException::class.java) {
                    collector.collect(first, session, store, id, JSONObject(), 1_000_000) { _, _ -> }
                }
                assertEquals(2, moves)
            } else if (cancel) {
                assertThrows(AgentNativeToolCancelledException::class.java) {
                    collector.collect(first, session, store, id, JSONObject(), 1_000_000) { _, _ -> }
                }
                assertEquals(2, moves)
            } else {
                val meta = collector.collect(first, session, store, id, JSONObject(), 1_000_000) { _, _ -> }
                assertEquals(5, session.pages)
                assertTrue(meta.optBoolean("top_verified"))
                assertTrue(meta.optBoolean("bottom_reached"))
                assertTrue(meta.optBoolean("visual_traversal_finished"))
                assertFalse(meta.optBoolean("complete"))
                assertTrue(meta.optBoolean("position_restored"))
                assertEquals(2, position)
                repeat(5) { assertTrue(File(store.directory(id), "$it.jpg").isFile) }
                assertTrue(File(store.directory(id), "4.json").readText().contains("Fixture page 4"))
            }
        } finally {
            PhoneAssistantTaskControl.release(lock, request)
            store.directory(id).deleteRecursively()
        }
    }
}
