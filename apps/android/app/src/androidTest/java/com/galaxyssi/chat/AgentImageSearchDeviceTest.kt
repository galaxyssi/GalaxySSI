package com.galaxyssi.chat

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.graphics.drawable.BitmapDrawable
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.MediaStore
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.ImageView
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentImageSearchDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val arguments = InstrumentationRegistry.getArguments()

    private fun optIn() {
        assumeTrue(arguments.getString("live_images") == "true")
        assertEquals("Operate S26U only", "SM-S9480", Build.MODEL)
    }

    @Test fun actualImageSourcesReturnRelevantDownloadableCandidates() {
        optIn()
        val fetcher = AgentBoundedWebIntelligenceFetcher(AgentBoundedWebService(AgentPinnedOkHttpWebTransport()))
        val coordinator = AgentWebIntelligenceSearchCoordinator(fetcher)
        val reports = JSONArray()
        for (query in listOf("\u82b1\u4ed9\u9c7c", "\u5c0f\u4e11\u9c7c", "clownfish")) {
            val start = SystemClock.elapsedRealtime()
            val response = coordinator.search(query, limit = 6, engineFanout = 3,
                verticals = setOf(AgentWebIntelligenceVertical.IMAGE), profile = "fast",
                timeoutMillis = AgentWebIntelligenceSearchProfile.FAST.defaultTimeoutMillis)
            val report = JSONObject().put("query", query).put("source_elapsed_ms", SystemClock.elapsedRealtime() - start)
                .put("response", JSONObject(AgentNativeJsonCodec.stringify(response.publicValue())))
            reports.put(report)
            reportFile("image-source-probes.json").writeText(reports.toString(2))
            val candidate = response.results.firstOrNull { it.imageUrl.isNotBlank() && it.title.contains(query, true) }
            assertNotNull("No title-matching actual image for $query", candidate)
            val downloadStart = SystemClock.elapsedRealtime()
            val downloaded = AgentMarkdownImageStore.load(context, candidate!!.imageUrl)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(downloaded.path, bounds)
            report.put("download_elapsed_ms", SystemClock.elapsedRealtime() - downloadStart)
                .put("image_width", bounds.outWidth).put("image_height", bounds.outHeight)
                .put("image_bytes", downloaded.length()).put("selected_title", candidate.title)
                .put("selected_url", candidate.imageUrl)
            reportFile("image-source-probes.json").writeText(reports.toString(2))
            assertTrue("Image data must decode", bounds.outWidth > 0 && bounds.outHeight > 0)
        }
    }

    @Test fun appImageSearchServiceWithoutSearchCache() {
        optIn()
        val reports = JSONArray()
        val setupStart = SystemClock.elapsedRealtime()
        val service = AgentWebIntelligenceService.android(context,
            AgentBoundedWebService(AgentPinnedOkHttpWebTransport()))
        val setupMillis = SystemClock.elapsedRealtime() - setupStart
        for (query in listOf("花仙鱼", "小丑鱼", "clownfish")) {
            val start = SystemClock.elapsedRealtime()
            val output = service.invoke("search", mapOf("query" to query, "limit" to 6,
                "profile" to "fast", "verticals" to listOf("image"), "engine_fanout" to 3, "use_cache" to false))
            assertEquals("Cold probe must not consume a search-cache hit", false, (output["cache"] as? Map<*, *>)?.get("hit"))
            val encoded = CloudWebGrounding.boundedModelJson(CloudImageSearchEvidence.prepare(output))
            val report = JSONObject().put("query", query).put("search_cache_enabled", false)
                .put("search_cache_hit", false).put("service_setup_ms", setupMillis)
                .put("service_elapsed_ms", SystemClock.elapsedRealtime() - start)
            reports.put(report)
            val pack = JSONObject(encoded).getJSONObject("evidence_pack")
            report.put("receipts", pack.optJSONArray("receipts"))
            val imageUrl = pack.getJSONArray("items").getJSONObject(0)
                .getJSONArray("images").getJSONObject(0).getString("url")
            val imageStart = SystemClock.elapsedRealtime()
            val loaded = AgentMarkdownImageStore.load(context, imageUrl)
            report.put("image_load_ms", SystemClock.elapsedRealtime() - imageStart)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(loaded.path, bounds)
            report.put("width", bounds.outWidth).put("height", bounds.outHeight)
            reportFile("image-service-uncached.json").writeText(reports.toString(2))
            assertTrue(bounds.outWidth > 0 && bounds.outHeight > 0)
        }
    }

    @Test fun realDeepSeekUiShowsRequestedImagesAndFinishes() {
        optIn()
        val target = AppStoreAgentConnectorRegistry(context).availableTargets().firstOrNull {
            it.kind == AgentConnectorKind.MODEL && it.status == AgentConnectorStatus.AVAILABLE &&
                (it.title.contains("deepseek", true) || it.invocationProfile.normalizedModelId("").contains("deepseek", true))
        } ?: error("No configured available DeepSeek model; do not modify credentials")
        val key = "image-live-${UUID.randomUUID()}"
        val store = AgentTranscriptStore(context, key)
        val conversation = store.createConversation("\u56fe\u7247\u68c0\u7d22\u771f\u673a\u9a8c\u8bc1 ${BuildConfig.VERSION_NAME}", privateMode = true)
        store.append(AgentTranscriptRole.PROCESS, "\u771f\u5b9e\u6a21\u578b\u56fe\u7247\u68c0\u7d22\u9a8c\u8bc1", conversationId = conversation.id)
        AgentModelSelectionSettings.selectManual(context, conversation.id, target.id,
            target.invocationProfile.normalizedModelId(""), target.title, rememberAsDefault = false)
        val monitor = instrumentation.addMonitor(ConversationWindowActivity::class.java.name, null, false)
        try {
            context.startActivity(Intent(context, ConversationWindowActivity::class.java)
                .setData(Uri.parse("galaxyssi://conversation-window/$key"))
                .putExtra(AgentConversationWindows.WINDOW_KEY, key)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT or Intent.FLAG_ACTIVITY_NEW_TASK))
            val activity = instrumentation.waitForMonitorWithTimeout(monitor, 60_000) as? MainActivity
                ?: error("Image verification window did not launch")
            await(60_000) { !activity.initialAgentHydrationPending && activity.conversationWindow.conversationId.isNotBlank() }
            val query = arguments.getString("image_query") ?: "\u7ed9\u51fa\u82b1\u4ed9\u9c7c\u7684\u56fe\u7247"
            val contextSamples = JSONArray()
            repeat(6) {
                val contextStart = SystemClock.elapsedRealtimeNanos()
                val loadedContext = store.context(conversation.id, excludeTurnId = "absent-benchmark-turn")
                contextSamples.put((SystemClock.elapsedRealtimeNanos() - contextStart) / 1_000_000.0)
                assertEquals(conversation.id, loadedContext.conversationId)
            }
            val start = SystemClock.elapsedRealtime()
            var firstImageObservedMillis = -1L
            var observedImage: ImageView? = null
            var observedDrawable: android.graphics.drawable.Drawable? = null
            var imageViewReplacements = 0
            var imageDrawableResets = 0
            val imageRebinds = JSONArray()
            var previousRender = JSONArray()
            fun renderSnapshot() = JSONArray(activity.renderedAgentTranscriptSourceEntries
                .filter { it.role == AgentTranscriptRole.ASSISTANT }.map { item ->
                    val blocks = AgentRichContentCodec.decode(item.richOutputJson)
                        .ifEmpty { AgentRichContentCodec.fromText(item.text) }
                    JSONObject().put("id", item.id).put("identity", AgentTranscriptRenderPolicy.identity(item))
                        .put("conversation", item.conversationId).put("turn", item.turnId).put("task", item.taskId)
                        .put("text_chunks", item.textChunkCount).put("rich_chunks", item.richOutputChunkCount)
                        .put("types", JSONArray(blocks.map { it.type.name }))
                        .put("sections", JSONArray(AgentResponseSectionOrganizer.organize(blocks).sections.map { it.kind.name }))
                })
            fun observeImageReuse() {
                val previous = observedImage ?: return
                val current = children(activity.agentOutputList).filterIsInstance<ImageView>()
                    .firstOrNull { it.isClickable && it.contentDescription == previous.contentDescription } ?: return
                if (current !== previous) {
                    imageViewReplacements++
                    val latest = renderSnapshot()
                    imageRebinds.put(JSONObject().put("before", previousRender).put("after", latest))
                    previousRender = latest
                }
                if (current.drawable !== observedDrawable) imageDrawableResets++
                observedImage = current
                observedDrawable = current.drawable
            }
            fun visibleImage() = children(activity.agentOutputList).filterIsInstance<ImageView>()
                .firstOrNull { image ->
                    val bitmap = (image.drawable as? BitmapDrawable)?.bitmap
                    val visible = Rect()
                    image.isShown && image.isClickable && bitmap != null && bitmap.width > 64 && bitmap.height > 64 &&
                        image.contentDescription != activity.getString(R.string.rich_output_load_failed) &&
                        image.getGlobalVisibleRect(visible) && visible.width() > 200 && visible.height() > 100
                }
            instrumentation.runOnMainSync {
                activity.agentGoalInput.setText(query)
                assertTrue(activity.agentSubmitButton.performClick())
            }
            await(30_000) {
                AgentTaskRuntime.supervisor(context).activeWorkspaces().any { it.conversationId == conversation.id }
            }
            await(180_000) {
                if (firstImageObservedMillis < 0 && visibleImage() != null) {
                    firstImageObservedMillis = SystemClock.elapsedRealtime() - start
                    observedImage = visibleImage()
                    observedDrawable = observedImage?.drawable
                    previousRender = renderSnapshot()
                }
                observeImageReuse()
                store.list(conversation.id).any { it.role == AgentTranscriptRole.ASSISTANT } &&
                    AgentTaskRuntime.supervisor(context).activeWorkspaces().none { it.conversationId == conversation.id }
            }
            val answer = store.list(conversation.id).filter { it.role == AgentTranscriptRole.ASSISTANT }
            val sources = answer.flatMap { entry ->
                Regex("!\\[[^]]*]\\((https?://[^\\s)]+)").findAll(entry.text).map { it.groupValues[1] }.toList() +
                    AgentRichContentCodec.decode(entry.richOutputJson).filter { it.type == AgentRichBlockType.IMAGE }.map { it.uri }
            }.distinct()
            val report = JSONObject().put("conversation_id", conversation.id).put("window_key", key)
                .put("query", query).put("elapsed_ms", SystemClock.elapsedRealtime() - start)
                .put("answer", answer.joinToString("\n") { it.text }).put("images", JSONArray(sources))
                .put("indexed_context_ms", contextSamples)
            reportFile("image-ui-latest.json").writeText(report.toString(2))
            assertTrue("Actual UI answer did not contain an image", sources.isNotEmpty())
            assertFalse("Simple image answer must not expose duplicate rich JSON",
                answer.any { it.text.contains("```galaxyssi-rich") })
            sources.take(3).forEach { AgentMarkdownImageStore.load(context, it) }
            instrumentation.runOnMainSync {
                activity.agentTranscriptAutoFollow = false
                activity.agentOutputLayout.scrollToPositionWithOffset(0, 0)
            }
            instrumentation.waitForIdleSync()
            await(20_000, onMain = false) {
                val bounds = Rect()
                var found = false
                instrumentation.runOnMainSync { found = visibleImage()?.getGlobalVisibleRect(bounds) == true }
                found && hasPhotoPixels(bounds)
            }
            report.put("drawable_observed_ms", firstImageObservedMillis)
            report.put("visible_image_observed_ms", SystemClock.elapsedRealtime() - start)
            report.put("visible_image_check", "viewport_drawable_and_screen_color_distribution")
            val processingLabel = activity.getString(R.string.agent_trace_processing, "", "").trim()
            val processedLabel = activity.getString(R.string.agent_trace_processed, "", "").trim()
            var completedClock = ""
            fun clockLabels() = children(activity.agentOutputList).filterIsInstance<TextView>()
                .filter { it.isShown }.map { it.text.toString() }
            await(5_000) {
                observeImageReuse()
                val labels = clockLabels()
                report.put("clock_labels_wait", JSONArray(labels.filter {
                    it.startsWith(processedLabel) || it.startsWith(processingLabel)
                })).put("image_view_replacements_after_first_draw", imageViewReplacements)
                    .put("image_drawable_resets_after_first_draw", imageDrawableResets)
                    .put("image_rebinds", imageRebinds)
                reportFile("image-ui-latest.json").writeText(report.toString(2))
                if (labels.none { it.startsWith(processedLabel) || it.startsWith(processingLabel) }) {
                    activity.agentOutputLayout.scrollToPositionWithOffset(0, 0)
                }
                completedClock = labels.firstOrNull { it.startsWith(processedLabel) }.orEmpty()
                completedClock.isNotBlank() && labels.none { it.startsWith(processingLabel) }
            }
            report.put("completed_clock", completedClock)
                .put("completed_clock_observed_ms", SystemClock.elapsedRealtime() - start)
            SystemClock.sleep(1_200)
            instrumentation.runOnMainSync {
                observeImageReuse()
                val labels = clockLabels()
                report.put("clock_labels_after_delay", JSONArray(labels.filter {
                    it.startsWith(processedLabel) || it.startsWith(processingLabel)
                })).put("image_view_replacements_after_first_draw", imageViewReplacements)
                    .put("image_drawable_resets_after_first_draw", imageDrawableResets)
                    .put("image_rebinds", imageRebinds)
                    .put("clock_window_focused", activity.hasWindowFocus())
                reportFile("image-ui-latest.json").writeText(report.toString(2))
                assertTrue("Completed clock must remain frozen", completedClock in labels)
                assertFalse("Completed task must not resume processing", labels.any { it.startsWith(processingLabel) })
            }
            report.put("completed_clock_stable", true)
                .put("image_view_replacements_after_first_draw", imageViewReplacements)
                .put("image_drawable_resets_after_first_draw", imageDrawableResets)
                .put("image_rebinds", imageRebinds)
            capture("image-ui-latest.png")
            instrumentation.runOnMainSync { assertTrue(visibleImage()!!.performClick()) }
            val saveLabel = activity.getString(R.string.peer_attachment_save)
            await(10_000, onMain = false) { findNode(instrumentation.uiAutomation.rootInActiveWindow, saveLabel) != null }
            capture("image-fullscreen-latest.png")
            val resolver = context.contentResolver
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val before = resolver.query(collection, arrayOf(MediaStore.Downloads._ID), null, null,
                "${MediaStore.Downloads._ID} DESC")?.use { if (it.moveToFirst()) it.getLong(0) else 0L } ?: 0L
            assertTrue(findNode(instrumentation.uiAutomation.rootInActiveWindow, saveLabel)!!
                .performAction(AccessibilityNodeInfo.ACTION_CLICK))
            val expected = sources.take(3).map { AgentMarkdownImageStore.load(context, it).readBytes() }
            var saved: Uri? = null
            await(15_000, onMain = false) {
                resolver.query(collection, arrayOf(MediaStore.Downloads._ID),
                    "${MediaStore.Downloads._ID} > ? AND ${MediaStore.Downloads.IS_PENDING} = 0",
                    arrayOf(before.toString()), null)?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val uri = android.content.ContentUris.withAppendedId(collection, cursor.getLong(0))
                        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: continue
                        if (expected.any { it.contentEquals(bytes) }) { saved = uri; break }
                    }
                }
                saved != null
            }
            instrumentation.uiAutomation.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
            report.put("visible_image", true).put("fullscreen_save_control", true)
                .put("save_bytes_verified", true).put("saved_uri", saved.toString())
            reportFile("image-ui-latest.json").writeText(report.toString(2))
        } finally { instrumentation.removeMonitor(monitor) }
    }

    private fun capture(name: String) {
        instrumentation.uiAutomation.takeScreenshot().let { bitmap ->
            reportFile(name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }

    private fun hasPhotoPixels(bounds: Rect): Boolean {
        val screen = instrumentation.uiAutomation.takeScreenshot() ?: return false
        try {
            if (!bounds.intersect(0, 0, screen.width, screen.height)) return false
            val colors = hashMapOf<Int, Int>()
            for (y in 0 until 20) for (x in 0 until 20) {
                val pixel = screen.getPixel(bounds.left + x * bounds.width() / 20,
                    bounds.top + y * bounds.height() / 20)
                val bucket = ((pixel shr 12) and 0xf00) or ((pixel shr 8) and 0xf0) or ((pixel shr 4) and 0xf)
                colors[bucket] = (colors[bucket] ?: 0) + 1
            }
            return colors.size >= 24 && (colors.values.maxOrNull() ?: 400) < 340
        } finally { screen.recycle() }
    }

    private fun children(view: View): List<View> = buildList {
        add(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) addAll(children(view.getChildAt(index)))
    }

    private fun findNode(node: AccessibilityNodeInfo?, label: String): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.contentDescription == label) return node
        for (index in 0 until node.childCount) {
            findNode(node.getChild(index), label)?.let { return it }
        }
        return null
    }

    private fun reportFile(name: String) = File(context.getExternalFilesDir("reports"), name)

    private fun await(timeout: Long, onMain: Boolean = true, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < deadline) {
            var done = false
            if (onMain) instrumentation.runOnMainSync { done = predicate() } else done = predicate()
            if (done) return
            SystemClock.sleep(100)
        }
        fail("Timed out waiting for actual image task state")
    }
}
