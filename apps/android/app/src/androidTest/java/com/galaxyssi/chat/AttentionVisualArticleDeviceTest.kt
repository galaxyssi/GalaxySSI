package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.view.ContextThemeWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AttentionVisualArticleDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val prose = "研究人员表示，产品目前仍在测试阶段，预计未来公布进一步数据。".repeat(8)
    private val document get() = AttentionArticleDocument(listOf(AttentionArticleBlock("heading", "研究进展"),
        AttentionArticleBlock("paragraph", prose), AttentionArticleBlock("image", "设备照片", "https://example.com/photo.jpg", 800, 600)))
    private fun store(test: (AttentionArticleStore, String) -> Unit) {
        val name = "visual-article-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            store.enqueue(AttentionFeedArticle("one", "topic", "新闻", "", "https://example.com/one", "Example", 1, 2), "主题")
            test(store, name)
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun metadataDoesNotReadFullDocumentAndExpandedBodyRetainsImages() = store { store, _ ->
        store.ready("one", AttentionChineseArticle("新闻", document.body, "", document))
        assertNull(store.presentation("one", false)!!.document)
        assertEquals(document.cover!!.url, store.presentation("one", false)!!.cover!!.url)
        assertEquals(document, store.presentation("one", true)!!.document)
        assertEquals(document.body, store.body("one"))
    }

    @Test fun enrichingPublishedArticleDoesNotRepublishOrLoseIdentity() = store { store, _ ->
        store.ready("one", AttentionChineseArticle("新闻", prose, "")); store.published("one")
        assertTrue(store.requestVisual("one")); assertFalse(store.requestVisual("one"))
        val job = store.claim(setOf("topic"), 1000)!!
        assertEquals("published", job.state)
        store.ready("one", AttentionChineseArticle("新闻", document.body, "", document))
        assertEquals("published", store.metadata("one")!!.state)
        assertEquals(2L, store.metadata("one")!!.collected)
        assertFalse(store.requestVisual("one"))
        assertNull(store.claim(setOf("topic"), Long.MAX_VALUE))
    }

    @Test fun failedImageEnrichmentLeavesPublishedBodyReadableAndUsesBackoff() = store { store, _ ->
        store.ready("one", AttentionChineseArticle("新闻", prose, "")); store.published("one"); store.requestVisual("one")
        val job = store.claim(setOf("topic"), 1000)!!
        store.failed(job, "article_body_missing", 1000)
        assertEquals(prose, store.body("one"))
        assertEquals("published", store.metadata("one")!!.state)
        assertNull(store.claim(setOf("topic"), 1001))
        assertNotNull(store.claim(setOf("topic"), 1_801_000))
    }

    @Test fun legacyPreviewSkipsSubmissionThanksBeforeVisualEnrichment() = store { store, name ->
        store.ready("one", AttentionChineseArticle("News", prose, "")); store.published("one")
        SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use {
            it.execSQL("UPDATE articles SET preview = ? WHERE id = 'one'", arrayOf("感谢网友提供线索！\n\n$prose"))
        }
        assertFalse(store.presentation("one", false)!!.preview.contains("感谢"))
        assertTrue(store.presentation("one", false)!!.preview.contains("产品目前仍在测试阶段"))
        assertEquals(prose, store.body("one"))
    }

    @Test fun upgradeKeepsOldBodiesAndDoesNotQueueTheWholeHistory() = store { store, name ->
        store.ready("one", AttentionChineseArticle("新闻", prose, "")); store.published("one")
        AttentionArticleStore.closeTest(context, name)
        SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { it.version = 5 }
        val reopened = AttentionArticleStore(context, name)
        assertEquals(prose, reopened.body("one"))
        assertEquals("published", reopened.metadata("one")!!.state)
        assertNull(reopened.claim(setOf("topic"), Long.MAX_VALUE))
        assertNotNull(reopened.presentation("one", true)!!.document)
    }

    @Test fun stalePresentationCannotReplaceAnotherArticleAndTitlesAreBold() {
        instrumentation.runOnMainSync {
            val theme = ContextThemeWrapper(context, android.R.style.Theme_Material_Light)
            val callbacks = mutableMapOf<String, (AttentionArticlePresentation?) -> Unit>()
            val view = ProactiveAttentionArticleView(theme, {}, {}, {}, {}, { _, done -> done(null) }, { _, _ -> },
                loadArticle = { key, _, done -> callbacks[key] = done })
            fun item(id: String) = GlobalProactiveInboxPolicy.project(listOf(GlobalProactiveMessage(id = "attention-feed:$id",
                sourceEventId = "research:attention-research:ai:feed:$id", sourceConversationId = "",
                target = GlobalProactiveTarget.NEW_CONVERSATION, title = "新闻$id", content = prose, topic = "科技",
                urgent = false, status = GlobalProactiveMessageStatus.DELIVERED, newsArticleKey = id)), emptyList()).single()
            val one = item("one"); val two = item("two")
            view.bind(AttentionReaderRow(one, false, false))
            view.bind(AttentionReaderRow(two, false, false))
            callbacks.getValue("one")(AttentionArticlePresentation("错误内容", null, "Source", 1))
            assertFalse(view.findViewWithTag<TextView>("attention-preview:${two.key}").text.contains("错误"))
            callbacks.getValue("two")(AttentionArticlePresentation("正确内容", document.cover, "Source", 1))
            assertEquals("正确内容", view.findViewWithTag<TextView>("attention-preview:${two.key}").text.toString())
            assertTrue(view.findViewWithTag<TextView>("attention-headline:${two.key}").typeface.isBold)
            assertEquals(1, views(view).filterIsInstance<AttentionArticleImageView>().count())
        }
    }

    @Test fun longArticlesAppendInPagesInsteadOfCreatingAllViewsAtOnce() {
        instrumentation.runOnMainSync {
            val view = AttentionArticleBodyView(context, AttentionArticleDocument((0 until 100).map {
                AttentionArticleBlock("paragraph", "正文第${it}段。".repeat(5))
            }))
            assertTrue(view.childCount < 40)
            val initial = view.childCount
            view.findViewWithTag<View>("attention-body-more").performClick()
            assertTrue(view.childCount > initial)
            assertTrue(view.childCount < 75)
        }
    }

    @Test fun excerptsStayCompactWithoutTruncatingTheArticleBody() {
        instrumentation.runOnMainSync {
            val view = AttentionArticleBodyView(context, document)
            val excerpts = views(view).filterIsInstance<TextView>().filter { it.tag == "attention-body-excerpt" }.toList()
            assertTrue(excerpts.isNotEmpty()); assertTrue(excerpts.size <= 2)
            assertTrue(excerpts.all { it.maxLines == 3 })
            assertTrue(views(view).filterIsInstance<TextView>().any { it.text.toString() == prose && it.maxLines == Int.MAX_VALUE })
        }
    }

    @Test fun realPublishedArticlesRetainImagesAndDecodeOnThePhone() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_visual_live") == "true")
        val store = AttentionArticleStore(context)
        val candidates = SQLiteDatabase.openDatabase(context.getDatabasePath(AttentionArticleStore.NAME).path, null,
            SQLiteDatabase.OPEN_READONLY).use { db -> db.rawQuery("SELECT id,url,title FROM articles WHERE state = 'published' " +
                "AND url LIKE 'https://www.ithome.com/%' ORDER BY collected DESC LIMIT 3", null).use { c ->
                buildList { while (c.moveToNext()) add(Triple(c.getString(0), c.getString(1), c.getString(2))) }
            } }
        assertTrue("No published live articles available", candidates.isNotEmpty())
        val fetcher = AgentBoundedWebIntelligenceFetcher(AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
            policy = AgentWebPolicy(maxTimeoutMillis = 20_000)))
        var verified = 0
        for ((key, url, title) in candidates) {
            val page = fetcher.fetch(url, 10 * 1024 * 1024L, 20_000, AgentNativeToolCancellationToken.NONE) {}
            val source = try { AttentionArticlePolicy.extractStructured(page) } finally { page.body.fill(0) }
            val cover = source.document.cover ?: continue
            val translated = AttentionArticleTranslator(context).use { it.translate(title, source) }
            val before = store.metadata(key)!!
            store.ready(key, translated)
            assertEquals("published", store.metadata(key)!!.state)
            assertEquals(before.collected, store.metadata(key)!!.collected)
            val done = CountDownLatch(1)
            var decoded = false
            AttentionArticleImages.load(context, cover.url, 384) { decoded = it != null; done.countDown() }
            assertTrue(done.await(30, TimeUnit.SECONDS)); assertTrue("Real source image failed to decode", decoded)
            instrumentation.sendStatus(0, Bundle().apply { putString("stream", "visual_news_live title=$title " +
                "blocks=${source.document.blocks.size} images=${source.document.blocks.count { it.kind == "image" }}\n") })
            verified++
        }
        assertTrue("No source image verified", verified > 0)
    }

    private fun views(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) yieldAll(views(view.getChildAt(index)))
    }
}
