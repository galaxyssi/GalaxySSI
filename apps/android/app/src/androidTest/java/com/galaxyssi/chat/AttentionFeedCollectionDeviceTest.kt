package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttentionFeedCollectionDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val now = System.currentTimeMillis()
    private val topic = AttentionTopic("ai_models", "AI", "AI")
    private fun feed(url: String, time: Long = now) = "<rss><channel><item><title>New AI model</title>" +
        "<link>$url</link><pubDate>${java.time.Instant.ofEpochMilli(time)}</pubDate></item></channel></rss>"

    @Test fun successfulFirstSourceDoesNotSuppressOthersAndContinuationSurvivesReopen() = isolated { context ->
        configure(context, listOf(topic))
        val urls = AttentionFeedCollectionPlan.endpoints(topic)
        val requests = mutableListOf<String>()
        var time = now
        do {
            val cycle = ProactiveAttentionFeedCollector(context) { url ->
                requests += url
                feed("https://example.org/${urls.indexOf(url)}")
            }.collect(time)
            time = cycle.nextAt
        } while (ProactiveAttentionFeedStore(context).topicState(topic.id).optInt("cursor") != 0)
        assertEquals(urls, requests)
        assertEquals(urls.size, ProactiveAttentionFeedStore(context).articleRecordsAfter("", 100).size)
        assertEquals(urls.size, ProactiveAttentionFeedStore(context).topicState(topic.id).optInt("new_items"))
        assertTrue(GlobalAgentRepository(context).proactiveMessages().isEmpty())
    }

    @Test fun failuresBackOffPerSourceWithoutSuppressingHealthyPublishers() = isolated { context ->
        configure(context, listOf(topic))
        val urls = AttentionFeedCollectionPlan.endpoints(topic)
        val requests = mutableListOf<String>()
        val cycle = ProactiveAttentionFeedCollector(context) { url ->
            requests += url
            if (url == urls.first()) throw java.io.IOException("fixture offline")
            feed("https://example.org/${urls.indexOf(url)}")
        }.collect(now)
        assertEquals(4, requests.size)
        assertEquals(3, cycle.newItems)
        assertTrue(cycle.error.contains("IOException"))
        val store = ProactiveAttentionFeedStore(context)
        assertTrue(store.sourceRetryAt(urls.first()) > now)
        assertEquals(0L, store.sourceRetryAt(urls[1]))
        configure(context, listOf(topic.copy(id = "agent_frontiers")))
        requests.clear()
        ProactiveAttentionFeedCollector(context) { url -> requests += url; feed("https://example.org/shared") }.collect(now + 1)
        assertFalse(requests.contains(urls.first()))
    }

    @Test fun multipleTopicsReusePublisherCacheAndCrossTopicUrlsRemainUnique() = isolated { context ->
        val other = AttentionTopic("open_source", "Open source", "Open source")
        configure(context, listOf(topic, other))
        val requests = mutableListOf<String>()
        repeat(2) {
            ProactiveAttentionFeedCollector(context) { url -> requests += url
                feed("https://example.org/shared").replace("New AI model", "New AI model open source")
            }.collect(now + it)
        }
        ProactiveAttentionFeedSources.originals(topic).take(2).forEach { url ->
            assertEquals(1, requests.count { it == url })
        }
        assertEquals(1, ProactiveAttentionFeedStore(context).articleRecordsAfter("", 100).size)
    }

    @Test fun failedSourceCacheAndCatalogRevisionSurviveRestartWithoutClearingDiscoveries() = isolated { context ->
        val store = ProactiveAttentionFeedStore(context)
        configure(context, listOf(topic))
        store.ingest(AttentionFeedArticle("kept", topic.id, "AI", "", "https://example.org/kept", "Example", now, now), topic)
        AgentEncryptedDatabase(context, "attention_feed_v1").writeString("topic:${topic.id}",
            """{"source_revision":2,"next":9223372036854775807} """)
        assertEquals(0L, ProactiveAttentionFeedStore(context).topicState(topic.id).optLong("next"))
        val url = "https://example.org/feed"
        store.cacheFeed(url, feed("https://example.org/kept"), now)
        assertNotNull(ProactiveAttentionFeedStore(context).cachedFeed(url, now + 10 * 60_000L))
        assertNull(store.cachedFeed(url, now + AttentionFeedCollectionPlan.CACHE_MILLIS))
        assertEquals("kept", store.articleRecordsAfter("", 10).single().getString("key"))
    }

    @Test fun pushAttributionKeepsOriginalPublisherAndDiscoveryChannelSeparately() = isolated { context ->
        configure(context, listOf(topic))
        val article = ProactiveAttentionPushPolicy.article("""{"id":1,"type":"story","time":${now / 1000},
            "url":"https://original.example/article","title":"AI model"}""", 1, now)!!.copy(topicId = topic.id)
        ProactiveAttentionFeedStore(context).ingest(article, topic)
        val record = ProactiveAttentionFeedStore(context).articleRecordsAfter("", 10).single()
        assertEquals("original.example", record.getString("publisher"))
        assertEquals("Hacker News", record.getString("discovered_via"))
    }

    @Test fun liveCatalogFetchParsesIndependentPublishers() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_live_catalog") == "true")
        val urls = listOf("https://www.federalreserve.gov/feeds/press_all.xml", "https://research.google/blog/rss/",
            "https://github.blog/feed/", "https://www.nasa.gov/feed/")
        var passed = 0
        for (url in urls) {
            val result = runCatching {
                val xml = AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url,
                    maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES, timeoutMillis = 15_000).body.toString(Charsets.UTF_8)
                ProactiveAttentionFeedPolicy.parse(xml, "fixture", now)
            }
            instrumentation.sendStatus(0, Bundle().apply { putString("stream",
                "catalog_live url=$url valid=${result.isSuccess} recent_items=${result.getOrNull()?.size ?: 0}\n") })
            if (result.isSuccess) passed++
        }
        assertTrue("Fewer than three independent feeds accessible: $passed", passed >= 3)
    }

    private fun configure(context: Context, topics: List<AttentionTopic>) {
        ProactiveAttentionStore(context).update { previous -> previous.copy(configured = true, enabled = true,
            topics = previous.topics.filter { old -> topics.none { it.id == old.id } }.map { it.copy(enabled = false) } + topics) }
    }

    private fun isolated(block: (Context) -> Unit) {
        val context = IsolatedContext(instrumentation.targetContext)
        try { block(context) } finally {
            AttentionArticleStore.closeTest(context, context.getDatabasePath(AttentionArticleStore.NAME).absolutePath)
            context.cleanup()
        }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "feed-collection-test-${UUID.randomUUID()}-"
        private val names = mutableSetOf<String>()
        private val preferences = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getDatabasePath(name: String): File = if (File(name).isAbsolute) File(name) else {
            names.add(prefix + name); baseContext.getDatabasePath(prefix + name)
        }
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?, handler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, handler)
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
            preferences.add(prefix + name); return baseContext.getSharedPreferences(prefix + name, mode)
        }
        fun cleanup() { names.forEach(baseContext::deleteDatabase); preferences.forEach(baseContext::deleteSharedPreferences) }
    }
}
