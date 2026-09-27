package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ScreenAssistantPageCaptureDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private fun snapshot(index: Int = 0): PhoneUiSnapshot {
        val parent = PhoneUiNode("0/0", "", "", "scroll", "ScrollView", "0,0,100,200", false, false, false, true, true, null, false)
        return PhoneUiSnapshot(77, "fixture.page", "revision-$index", listOf(parent,
            parent.copy(path = "0/0/0", text = "Segment $index <script>unsafe()</script>", scrollable = false)), false)
    }
    private fun image(index: Int): File {
        val file = File(context.filesDir, "agent-rich-output-v2/screen-assistant/test-${UUID.randomUUID()}.jpg")
        file.parentFile!!.mkdirs()
        val bitmap = Bitmap.createBitmap(80, 160, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.rgb(index * 20 % 255, 60, 80))
        try { file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) } }
        finally { bitmap.recycle() }
        return file
    }
    private fun cleanup(id: String) {
        val dir = ScreenAssistantPageStore(context).directory(id).canonicalFile
        val expected = File(context.filesDir, "agent-rich-output-v2/screen-assistant/pages").canonicalFile
        assertEquals(expected, dir.parentFile)
        dir.deleteRecursively()
    }
    @Test fun capturesEverySegmentFromTopRestoresPositionAndExportsBothFormats() {
        var index = 2
        val request = ScreenAssistantAnalysisRequest()
        val session = ScreenAssistantPageCollection(request)
        val collector = ScreenAssistantPageCollector(context, { snapshot(index) }, { _, _, forward ->
            if (forward && index < 7) { index++; true }
            else if (!forward && index > 0) { index--; true } else false
        }, { image(index) })
        val id = collector.collect(session) { _, _ -> }
        try {
            val store = ScreenAssistantPageStore(context)
            val meta = store.manifest(id)
            assertTrue(meta.toString(), meta.getBoolean("complete"))
            assertEquals(8, meta.getInt("pages"))
            assertEquals(2, index)
            assertFalse(request.isCancelled)
            val html = File(store.directory(id), "page.html").readText()
            assertTrue(html.contains("Segment 7"))
            assertTrue(html.contains("&lt;script&gt;"))
            assertFalse(html.contains("<script>unsafe"))
            val pdf = store.exportPdf(id)
            assertTrue(pdf.length() > 100)
            assertEquals("%PDF", pdf.inputStream().use { String(it.readNBytes(4)) })
            assertTrue(File(store.directory(id), "page.txt").readText().contains("Segment 7"))
        } finally { cleanup(id) }
    }
    @Test fun userFinishIsPartialAndDoesNotSubmitOrCancelTheAnalysisRequest() {
        var index = 0
        val session = ScreenAssistantPageCollection(ScreenAssistantAnalysisRequest())
        val id = ScreenAssistantPageCollector(context, { snapshot(index) }, { _, _, forward ->
            if (forward) { index++; true } else if (index > 0) { index--; true } else false
        }, { image(index) }).collect(session) { count, _ -> if (count == 2) session.finish() }
        try {
            val meta = ScreenAssistantPageStore(context).manifest(id)
            assertFalse(meta.getBoolean("complete"))
            assertEquals("user_finish", meta.getString("reason"))
            assertEquals(2, meta.getInt("pages"))
            assertTrue(session.request.turnIds.isEmpty())
            assertFalse(session.request.isCancelled)
        } finally { cleanup(id) }
    }
    @Test fun cancellationStopsWithoutRenderingOrModelSubmission() {
        val session = ScreenAssistantPageCollection(ScreenAssistantAnalysisRequest())
        val id = ScreenAssistantPageCollector(context, { snapshot() }, { _, _, _ -> false }, { image(0) })
            .collect(session) { _, _ -> session.request.cancel() }
        try {
            assertEquals("cancelled", ScreenAssistantPageStore(context).manifest(id).getString("reason"))
            assertFalse(File(ScreenAssistantPageStore(context).directory(id), "page.html").exists())
            assertTrue(session.request.turnIds.isEmpty())
        } finally { cleanup(id) }
    }
    @Test fun changingTargetStopsAndNeverClaimsComplete() {
        var changed = false
        val session = ScreenAssistantPageCollection(ScreenAssistantAnalysisRequest())
        val id = ScreenAssistantPageCollector(context, { snapshot().let { if (changed) it.copy(windowId = 88) else it } },
            { _, _, forward -> if (forward) changed = true; forward }, { image(0) }).collect(session) { _, _ -> }
        try {
            assertEquals("target_changed", ScreenAssistantPageStore(context).manifest(id).getString("reason"))
            assertFalse(ScreenAssistantPageStore(context).manifest(id).getBoolean("complete"))
        } finally { cleanup(id) }
    }
    @Test fun stalledScrollCannotBeReportedAsComplete() {
        val id = ScreenAssistantPageCollector(context, { snapshot() }, { _, _, _ -> true }, { image(0) })
            .collect(ScreenAssistantPageCollection(ScreenAssistantAnalysisRequest())) { _, _ -> }
        try {
            assertEquals("stalled", ScreenAssistantPageStore(context).manifest(id).getString("reason"))
        } finally { cleanup(id) }
    }
    @Test fun pausedCaptureDoesNotScrollAndCancellationReleasesIt() {
        var scrolls = 0
        val session = ScreenAssistantPageCollection(ScreenAssistantAnalysisRequest())
        session.request.setPaused(true)
        val result = AtomicReference<String>()
        val thread = Thread {
            result.set(ScreenAssistantPageCollector(context, { snapshot() }, { _, _, _ -> scrolls++; false },
                { image(0) }).collect(session) { _, _ -> })
        }
        thread.start()
        SystemClock.sleep(350)
        assertEquals(0, scrolls)
        assertTrue(thread.isAlive)
        session.request.cancel()
        thread.join(5_000)
        assertFalse(thread.isAlive)
        cleanup(requireNotNull(result.get()))
    }
    @Test fun escapedTextPagingPreservesAllCharactersWithinObservationBudget() {
        val store = ScreenAssistantPageStore(context)
        val id = store.create()
        val text = "\\\"\n".repeat(3_000)
        try {
            store.checkpoint(id, org.json.JSONObject().put("pages", 1).put("complete", false).put("reason", "user_finish"))
            File(store.directory(id), "0.json").writeText(org.json.JSONObject().put("text", text).toString())
            var offset = 0
            val rebuilt = StringBuilder()
            do {
                val result = store.read(id, 0, offset, 2_000)
                assertTrue(AgentNativeJsonCodec.stringify(result).length <= 3_500)
                rebuilt.append(result["text"])
                val next = result["next_offset"] as? Int
                if (next == null) break
                assertTrue(next > offset)
                offset = next
            } while (true)
            assertEquals(text, rebuilt.toString())
        } finally { cleanup(id) }
    }
    @Test fun pagedReadIsBoundToTheOwningTurnAndRejectsOtherTurns() {
        val session = ScreenAssistantPageCollection(ScreenAssistantAnalysisRequest())
        val id = ScreenAssistantPageCollector(context, { snapshot() }, { _, _, _ -> false }, { image(0) })
            .collect(session) { _, _ -> }
        val turn = UUID.randomUUID().toString()
        session.request.pageCaptureId = id
        PhoneAssistantTaskControl.bind(turn, session.request)
        try {
            val registry = AgentNativeToolRegistry().registerAll(AgentPhoneUiNativeTools.definitions(context))
            val invocation = AgentNativeToolInvocationContext(sessionId = turn, conversationId = turn, turnId = turn, idempotencyKey = "page-read")
            val result = registry.invoke(AgentPhoneUiNativeTools.PAGE_READ, mapOf("limit" to 4), invocation)
            assertTrue(result.message, result.isSuccess)
            assertFalse(registry.invoke(AgentPhoneUiNativeTools.PAGE_READ, emptyMap(), invocation.copy(turnId = "other", idempotencyKey = "other")).isSuccess)
            assertEquals(4, (ScreenAssistantPageStore(context).read(id, 0, 0, 4)["text"] as String).length)
            assertThrows(IllegalArgumentException::class.java) { ScreenAssistantPageStore(context).directory("../../escape") }
            assertThrows(IllegalArgumentException::class.java) { ScreenAssistantPageStore(context).page(id, 100) }
        } finally { PhoneAssistantTaskControl.release(turn, session.request); cleanup(id) }
    }
    @Test fun realLongFixtureCapturesFirstAndLastRowsWithOverlayExcluded() {
        SystemClock.sleep(3_000)
        val ready = SystemClock.elapsedRealtime() + 20_000
        while (!GalaxySSIAccessibilityService.isActive() && SystemClock.elapsedRealtime() < ready) SystemClock.sleep(100)
        requireNotNull(GalaxySSIAccessibilityService.targetService())
        instrumentation.context.startActivity(Intent().setClassName(instrumentation.context.packageName,
            PhoneUiFixtureActivity::class.java.name).putExtra("page_capture", true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        SystemClock.sleep(800)
        val session = ScreenAssistantPageCollection(ScreenAssistantAnalysisRequest())
        val id = ScreenAssistantPageCollector(context).collect(session) { _, _ -> }
        try {
            val store = ScreenAssistantPageStore(context)
            val meta = store.manifest(id)
            assertTrue(meta.toString(), meta.getInt("pages") >= 3)
            val text = File(store.directory(id), "page.txt").readText()
            assertTrue(text, text.contains("Fixture row 1\n"))
            assertTrue(text, text.contains("Fixture row 80"))
            assertFalse(text.contains("test-secret-never-export"))
            assertFalse(text.contains("Assistant panel must not be observed"))
            assertTrue(meta.toString(), meta.optBoolean("bottom_reached"))
            assertTrue(meta.toString(), meta.optBoolean("complete"))
        } finally { cleanup(id) }
    }
}
