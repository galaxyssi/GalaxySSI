package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.os.SystemClock
import android.view.ContextThemeWrapper
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttentionArticleDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val chinese = "研究团队开发了新型电池，提高了储能效率，也改善了设备的可靠性。".repeat(6)
    private fun report(text: String) = instrumentation.sendStatus(0, Bundle().apply { putString("stream", "$text\n") })

    @Test fun queueResumesAndStoresChineseBodyAsPlaintextWithoutLoadingItInMetadata() {
        val name = "article-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            val article = AttentionFeedArticle("a", "topic", "Title", "", "https://example.com/news", "Example", 1, 2)
            store.enqueue(article, "主题"); store.enqueue(article, "主题")
            val job = store.claim(setOf("topic"), 1000)!!
            assertNull(store.claim(setOf("topic"), 1001))
            assertNotNull(AttentionArticleStore(context, name).claim(setOf("topic"), 301_001))
            store.ready(job.key, AttentionChineseArticle("电池研究", chinese, AttentionMlKitTranslator.PROVIDER))
            val resumed = AttentionArticleStore(context, name).claim(setOf("topic"), 301_002)!!
            assertEquals("ready", resumed.state); assertEquals(chinese, store.body(job.key))
            assertTrue(resumed.preview.length <= 500)
            SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                db.rawQuery("SELECT body FROM articles WHERE id = 'a'", null).use { c ->
                    assertTrue(c.moveToFirst()); assertEquals(chinese, c.getString(0))
                }
            }
            store.published(job.key)
            assertNull(store.claim(setOf("topic"), Long.MAX_VALUE))
            assertEquals(chinese, AttentionArticleStore(context, name).body(job.key))
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun failedAndDisabledTopicsRemainHiddenAndBackOff() {
        val name = "article-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            store.enqueue(AttentionFeedArticle("a", "topic", "Title", "", "https://example.com/news", "Example", 1, 2), "主题")
            assertNull(store.claim(setOf("other"), 1000))
            val job = store.claim(setOf("topic"), 1000)!!
            store.failed(job, "article_body_missing", 1000)
            assertNull(store.body("a")); assertNull(store.claim(setOf("topic"), 1001))
            assertNotNull(store.claim(setOf("topic"), 1_801_000))
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun backlogRotatesSourcesInsteadOfOnlyPublishingTheNewestSource() {
        val name = "article-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            for ((id, publisher, time) in listOf(Triple("new-1", "IT", 100L), Triple("new-2", "IT", 101L),
                Triple("old", "HN", 1L))) {
                store.enqueue(AttentionFeedArticle(id, "topic", "Title", "", "https://example.com/$id", publisher, time, time), "主题")
            }
            assertEquals("new-2", store.claim(setOf("topic"), 1000)!!.key)
            assertEquals("old", store.claim(setOf("topic"), 1001)!!.key)
            assertEquals("new-1", store.claim(setOf("topic"), 1002)!!.key)
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun thousandsOfHistoricalArticlesProgressDespiteNewArrivalsAndRepeatedFailures() {
        val name = "article-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            store.enqueue(AttentionFeedArticle("retry", "topic", "Title", "", "https://example.com/retry", "Example", 1, 999999), "Topic")
            SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                db.beginTransaction()
                try {
                    db.execSQL("UPDATE articles SET attempts = 8,error = 'article_body_missing' WHERE id = 'retry'")
                    db.compileStatement("INSERT INTO articles(id,url,topic,topic_title,title,publisher,published,collected) " +
                        "VALUES(?,?,'topic','Topic','Title','Example',1,?)").use { statement ->
                        repeat(4326) { index ->
                            statement.bindString(1, "old-$index"); statement.bindString(2, "https://example.com/$index")
                            statement.bindLong(3, index.toLong()); statement.executeInsert()
                        }
                    }
                    AttentionArticleTopics.create(db)
                    db.setTransactionSuccessful()
                } finally { db.endTransaction() }
            }
            val claimed = mutableListOf<String>()
            repeat(60) { index ->
                store.enqueue(AttentionFeedArticle("fresh-$index", "topic", "Title", "", "https://example.com/new/$index",
                    "Example", 1, 100_000L + index), "Topic")
                // Reopening on every claim exercises the persisted lane, not an in-memory counter.
                val reopened = AttentionArticleStore(context, name)
                val job = reopened.claim(setOf("topic"), 1_000_000L + index)!!
                claimed += job.key
                if (job.key == "retry") reopened.failed(job, "article_body_missing", 1_000_000L + index)
                else { reopened.ready(job.key, AttentionChineseArticle("新闻", chinese, "")); reopened.published(job.key) }
            }
            assertTrue(claimed.count { it.startsWith("old-") } >= 20)
            assertTrue(claimed.count { it.startsWith("fresh-") } >= 29)
            assertEquals(1, claimed.count { it == "retry" })
            assertEquals(60, claimed.distinct().size)
            assertTrue(claimed.contains("old-0"))
            assertEquals(59, store.counts(setOf("topic")).published)
            assertEquals(4326 + 60 + 1, store.counts(setOf("topic")).let { it.published + it.waiting + it.retrying })
            assertEquals(AttentionArticleQueueCounts(0, 0, 0), store.counts(setOf("disabled")))
            report("article_backlog_fixture records=4387 historical=${claimed.count { it.startsWith("old-") }} " +
                "fresh=${claimed.count { it.startsWith("fresh-") }} retry=${claimed.count { it == "retry" }}")
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun retryLaneSurvivesContinuousFirstAttemptsAndLeasesRecoverAfterProcessDeath() {
        val name = "article-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            fun enqueue(id: String, at: Long) = store.enqueue(AttentionFeedArticle(id, "topic", "Title", "",
                "https://example.com/$id", "Example", at, at), "Topic")
            enqueue("interrupted", 0)
            assertEquals("interrupted", store.claim(setOf("topic"), 1000)!!.key)
            repeat(60) { enqueue("first-$it", it.toLong()) }
            val claims = (0..5).map { AttentionArticleStore(context, name).claim(setOf("topic"), 301_001L + it)!!.key }
            assertTrue(claims.contains("interrupted"))
            assertEquals(6, claims.distinct().size)
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun oldExtractedBodiesAreRequeuedWithoutLosingDiscoveries() {
        val name = "article-test-${UUID.randomUUID()}.db"
        try {
            var store = AttentionArticleStore(context, name)
            store.enqueue(AttentionFeedArticle("old", "topic", "Title", "", "https://example.com/old", "HN", 1, 2), "主题")
            store.ready("old", AttentionChineseArticle("标题", chinese, "")); store.published("old")
            AttentionArticleStore.closeTest(context, name)
            SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { it.version = 1 }
            store = AttentionArticleStore(context, name)
            assertEquals("repair", store.metadata("old")!!.state)
            assertNull(store.body("old"))
            assertEquals("old", store.claim(setOf("topic"), 1000)!!.key)
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun extractorUpgradeRetriesMissingBodiesWithoutResettingPublishedRecordsOrAttempts() {
        val name = "article-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            for (id in listOf("broken", "complete")) store.enqueue(AttentionFeedArticle(id, "topic", "Title", "",
                "https://example.com/$id", "Example", 1, 2), "Topic")
            store.ready("complete", AttentionChineseArticle("新闻", chinese, "")); store.published("complete")
            val job = store.claim(setOf("topic"), 1000)!!
            store.failed(job, "article_body_missing", 1000)
            AttentionArticleStore.closeTest(context, name)
            SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { it.version = 4 }
            val reopened = AttentionArticleStore(context, name)
            assertEquals("broken", reopened.claim(setOf("topic"), 1001)!!.key)
            assertEquals(2, reopened.metadata("broken")!!.attempts)
            assertEquals("published", reopened.metadata("complete")!!.state)
            assertEquals(chinese, reopened.body("complete"))
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun readIndexAndProjectionBothExcludeLegacyHeadlines() {
        val name = "article-index-test-${UUID.randomUUID()}"
        val database = AgentEncryptedDatabase(context, name)
        try {
            val index = ProactiveMessageReadIndex(database)
            fun record(id: String, key: String) = JSONObject().put("id", id).put("status", "DELIVERED")
                .put("source_event_id", "research:attention-research:ai:feed:$id").put("news_article_key", key)
                .put("news_article_revision", AttentionArticlePolicy.REVISION)
            index.prepare { sequenceOf(record("old", ""), record("new", "key"), record("obsolete", "bad-body").put("news_article_revision", 0)) }
            assertEquals(ProactiveInboxCounts(1, 1), index.counts(emptyList()))
            assertEquals(listOf("proactive_message_row:new"), index.firstKeys(AttentionReaderState(), emptySet()))
        } finally { database.clear() }
    }

    @Test fun articleBodyLoadsOnlyOnExpansionAndIgnoresRecycledRowCallbacks() {
        instrumentation.runOnMainSync {
            val theme = ContextThemeWrapper(context, android.R.style.Theme_Material_Light)
            fun item(id: String) = GlobalProactiveInboxPolicy.project(listOf(GlobalProactiveMessage(
                id = "attention-feed:$id", sourceEventId = "research:attention-research:ai:feed:$id",
                sourceConversationId = "", target = GlobalProactiveTarget.NEW_CONVERSATION, title = "中文新闻$id",
                content = "中文预览$id", topic = "科技", urgent = false, status = GlobalProactiveMessageStatus.DELIVERED,
                newsArticleKey = id, newsTranslationProvider = AttentionMlKitTranslator.PROVIDER)), emptyList()).single()
            val callbacks = mutableMapOf<String, (String?) -> Unit>()
            val view = ProactiveAttentionArticleView(theme, {}, {}, {}, {}, { _, done -> done(null) }, {},
                { key, done -> callbacks[key] = done })
            val first = item("first"); val second = item("second")
            val branded = first.copy(title = "Copilot")
            assertEquals(AttentionMlKitTranslator.PROVIDER,
                ProactiveAttentionTitleStore(context).decorate(listOf(branded)).single().titleTranslationProvider)
            view.bind(AttentionReaderRow(first, false, false))
            assertTrue(callbacks.isEmpty())
            view.bind(AttentionReaderRow(first, true, false))
            callbacks.getValue("first")(chinese)
            assertEquals(chinese, view.findViewWithTag<TextView>("attention-expanded:${first.key}").text.toString())
            view.bind(AttentionReaderRow(second, true, false))
            callbacks.getValue("first")("过期正文")
            assertEquals(second.content, view.findViewWithTag<TextView>("attention-expanded:${second.key}").text.toString())
            callbacks.getValue("second")(chinese + "最新正文")
            assertEquals(chinese + "最新正文", view.findViewWithTag<TextView>("attention-expanded:${second.key}").text.toString())
        }
    }

    @Test fun discoveryTimestampIsNotPresentedAsOriginalPublicationDate() {
        val name = "article-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            store.enqueue(AttentionFeedArticle("hn", "topic", "Title", "", "https://example.com/news", "HN", 100, 200,
                discoveryDate = true), "科技")
            assertEquals(0L, store.metadata("hn")!!.published)
            assertEquals(200L, store.metadata("hn")!!.collected)
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun realArticleFetchAndChineseTranslation() = runBlocking {
        val url = InstrumentationRegistry.getArguments().getString("attention_article_url")
        assumeTrue(!url.isNullOrBlank())
        val started = SystemClock.elapsedRealtime()
        val fetcher = AgentBoundedWebIntelligenceFetcher(AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
            policy = AgentWebPolicy(maxTimeoutMillis = 20_000)))
        val page = fetcher.fetch(url!!, 10 * 1024 * 1024, 20_000, AgentNativeToolCancellationToken.NONE, {})
        val article = try { AttentionArticlePolicy.extract(page) } finally { page.body.fill(0) }
        if (InstrumentationRegistry.getArguments().getString("attention_article_diagnostics") == "true") {
            AttentionArticlePolicy.parts(article.content).filterNot(AttentionArticlePolicy::chinese).take(12)
                .forEach { report("public_article_non_chinese_segment=" + it.take(120)) }
        }
        val fetchedAt = SystemClock.elapsedRealtime()
        AttentionArticleTranslator(context).use { translator ->
            val translated = translator.translate(article.title, article.content)
            assertTrue(AttentionArticlePolicy.chinese(translated.body))
            assertTrue(translated.body.length >= 80)
            report("article_live fetch_ms=${fetchedAt - started} translate_ms=${SystemClock.elapsedRealtime() - fetchedAt} " +
                "source_chars=${article.content.length} chinese_chars=${translated.body.length} paragraphs=${AttentionArticlePolicy.parts(article.content).size}")
        }
    }
}
