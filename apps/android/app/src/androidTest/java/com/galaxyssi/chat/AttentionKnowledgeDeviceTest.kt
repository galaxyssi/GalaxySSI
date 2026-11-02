package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttentionKnowledgeDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val body = "蛋白质是由氨基酸组成的生物大分子，参与细胞结构、催化与信号传递。".repeat(6)

    @Test fun acquireSelectedRealIllustratedChapterThroughProductionPipeline() = kotlinx.coroutines.runBlocking {
        val url = InstrumentationRegistry.getArguments().getString("attention_knowledge_article").orEmpty()
        assumeTrue(url.isNotBlank())
        val endpoint = AttentionKnowledgeSources.endpoints.first { AttentionKnowledgeSources.accepts(it, url) }
        val preferences = ProactiveAttentionStore(context).preferences()
        val topic = preferences.topics.first { it.id == AttentionLifeScienceSources.TOPIC }
        assumeTrue(preferences.enabled && topic.enabled)
        val page = AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url, maxBytes = 10 * 1024 * 1024L, timeoutMillis = 20_000)
        val source = try { AttentionArticlePolicy.extractStructured(AgentWebIntelligenceFetched(page.finalUrl, page.contentType, page.body)) }
            finally { page.body.fill(0) }
        assertNotNull(source.document.cover)
        val translated = AttentionArticleTranslator(context).use { it.translate(source.article.title, source) }
        val article = AttentionFeedArticle(ProactiveAttentionFeedPolicy.urlKey(url), topic.id, source.article.title, "", url,
            java.net.URI(url).host, 0, System.currentTimeMillis(), true, endpoint, true)
        val feed = ProactiveAttentionFeedStore(context)
        feed.ingest(article, topic)
        val store = AttentionArticleStore(context)
        store.ready(article.key, translated)
        val job = store.scopedMetadata(article.key, setOf(topic.id))!!
        val count = if (feed.publishArticle(job)) 1 else 0
        store.published(article.key)
        ProactiveAttentionFeedDelivery.published(context, count)
        GlobalProactiveDeliveryBus.signalReady()
        val cover = store.presentation(article.key, true)!!.document!!.cover!!
        val done = java.util.concurrent.CountDownLatch(1)
        var decoded = false
        AttentionArticleImages.load(context, cover.url, 1280) { decoded = it != null; done.countDown() }
        assertTrue(done.await(30, java.util.concurrent.TimeUnit.SECONDS))
        assertTrue("Public source figure did not decode", decoded)
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("stream", "illustrated_knowledge_live url=$url images=${source.document.blocks.count { it.kind == "image" }} translated=true decoded=true\n")
        })
    }

    /** Opt-in public content acquisition; preserve every preference, private message and read state. */
    @Test fun acquireLiveEducationalCatalogIntoTheNormalArticleQueue() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_knowledge_live") == "true")
        val topic = ProactiveAttentionStore(context).preferences().topics.first { it.id == AttentionLifeScienceSources.TOPIC }
        assumeTrue(topic.enabled && ProactiveAttentionStore(context).preferences().enabled)
        val feed = ProactiveAttentionFeedStore(context)
        var discovered = 0
        var inserted = 0
        for (endpoint in AttentionKnowledgeSources.endpoints) {
            val now = System.currentTimeMillis()
            val page = AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(endpoint,
                maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES, timeoutMillis = 15_000)
            val records = try { AttentionKnowledgeSources.discover(page.body.toString(Charsets.UTF_8), endpoint, topic.id, now) }
                finally { page.body.fill(0) }
            assertTrue(endpoint, records.isNotEmpty())
            discovered += records.size
            inserted += records.count { feed.ingest(it, topic) }
            feed.knowledgeScanned(topic.id, endpoint, now)
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("stream", "knowledge_live endpoint=$endpoint discovered=${records.size}\n")
            })
        }
        AttentionArticleScheduler.request(context)
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("stream", "knowledge_live total=$discovered inserted=$inserted queued_for_full_text=true\n")
        })
        assertTrue(discovered >= 500)
    }

    @Test fun knowledgeKindSurvivesQueuePublicationAndRepeatedNewsDiscovery() = isolated { name ->
        val store = AttentionArticleStore(context, name)
        val article = AttentionFeedArticle("protein", AttentionLifeScienceSources.TOPIC, "Proteins", "",
            "https://medlineplus.gov/genetics/understanding/howgeneswork/protein", "MedlinePlus", 0, 100,
            discoveryDate = true, knowledge = true)
        store.enqueue(article, "蛋白质与生命科学")
        assertNull(store.presentation(article.key, true))
        assertTrue(store.claim(setOf(article.topicId), 1000)!!.knowledge)
        store.ready(article.key, AttentionChineseArticle("蛋白质是什么？", body, "fixture"))
        store.published(article.key)
        store.enqueue(article.copy(knowledge = false), "蛋白质与生命科学")
        AttentionArticleStore.closeTest(context, name)
        val reopened = AttentionArticleStore(context, name)
        assertEquals(AttentionArticleQueueCounts(1, 0, 0), reopened.counts(setOf(article.topicId)))
        assertTrue(reopened.metadata(article.key)!!.knowledge)
        for (expanded in listOf(false, true)) {
            val presentation = reopened.presentation(article.key, expanded)!!
            assertTrue(presentation.knowledge)
            assertEquals(0L, presentation.published)
        }
        assertEquals(body, reopened.body(article.key))
    }

    @Test fun versionSevenMigrationPreservesPublishedBodyAndQueuedWork() = isolated { name ->
        SQLiteDatabase.openOrCreateDatabase(context.getDatabasePath(name), null).use { db ->
            db.execSQL("CREATE TABLE articles(id TEXT PRIMARY KEY NOT NULL,url TEXT NOT NULL,topic TEXT NOT NULL," +
                "topic_title TEXT NOT NULL,title TEXT NOT NULL,publisher TEXT NOT NULL,published INTEGER NOT NULL," +
                "collected INTEGER NOT NULL,state TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0," +
                "next_at INTEGER NOT NULL DEFAULT 0,error TEXT NOT NULL DEFAULT '',zh_title TEXT NOT NULL DEFAULT ''," +
                "preview TEXT NOT NULL DEFAULT '',body TEXT NOT NULL DEFAULT '',provider TEXT NOT NULL DEFAULT ''," +
                "document TEXT NOT NULL DEFAULT '',cover TEXT NOT NULL DEFAULT '',cover_width INTEGER NOT NULL DEFAULT 0," +
                "cover_height INTEGER NOT NULL DEFAULT 0,visual_revision INTEGER NOT NULL DEFAULT 0," +
                "visual_requested INTEGER NOT NULL DEFAULT 0)")
            db.execSQL("CREATE TABLE metadata(id TEXT PRIMARY KEY NOT NULL,value TEXT NOT NULL)")
            db.execSQL("INSERT INTO articles(id,url,topic,topic_title,title,publisher,published,collected,state,body) " +
                "VALUES('old','https://example.org/old','biology','Biology','Old','Example',10,20,'published',?)", arrayOf(body))
            db.execSQL("INSERT INTO articles(id,url,topic,topic_title,title,publisher,published,collected,attempts,next_at) " +
                "VALUES('pending','https://example.org/pending','biology','Biology','Pending','Example',11,21,3,987654321)")
            AttentionArticleTopics.create(db)
            db.version = 7
        }
        val upgraded = AttentionArticleStore(context, name)
        assertEquals(body, upgraded.body("old"))
        assertFalse(upgraded.presentation("old", true)!!.knowledge)
        assertEquals(10L, upgraded.presentation("old", false)!!.published)
        assertEquals("published", upgraded.metadata("old")!!.state)
        assertEquals(3, upgraded.metadata("pending")!!.attempts)
        assertNull(upgraded.claim(setOf("biology"), 1000))
        assertEquals("pending", upgraded.claim(setOf("biology"), 987654321)!!.key)
    }

    private fun isolated(block: (String) -> Unit) {
        val name = "knowledge-test-${UUID.randomUUID()}.db"
        try { block(name) } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }
}
