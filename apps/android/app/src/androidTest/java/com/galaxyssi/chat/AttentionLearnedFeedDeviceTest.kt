package com.galaxyssi.chat

import android.os.Bundle
import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AttentionLearnedFeedDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val chinese = "研究介绍了智能体使用工具进行持续检索与信息核对的方法。".repeat(8)

    @Test fun feedStatePersistsScopesPollDatesAndSourceProbeLeases() = isolated { name ->
        var store = AttentionArticleStore(context, name)
        val origin = "https://publisher.org/article"
        assertEquals(setOf("ai_models", "agent_frontiers"), store.learnFeeds(origin, listOf("https://publisher.org/feed"),
            setOf("ai_models", "agent_frontiers"), 1000))
        assertTrue(store.learnFeeds(origin, listOf("https://publisher.org/feed"), setOf("ai_models"), 1001).isEmpty())
        assertTrue(store.learnFeeds(origin, listOf("https://foreign.org/feed"), setOf("ai_models"), 1001).isEmpty())
        store.deferLearnedFeed("https://publisher.org/feed", 5000, 1000)
        AttentionArticleStore.closeTest(context, name); store = AttentionArticleStore(context, name)
        assertNull(store.dueLearnedFeed("ai_models", 4999))
        assertEquals("https://publisher.org/feed", store.dueLearnedFeed("agent_frontiers", 5000))
        assertNull(store.dueLearnedFeed("disabled", 6000))
        assertEquals(setOf("ai_models", "agent_frontiers"), store.learnedFeedTopics("https://publisher.org/feed"))
        store.enqueue(AttentionFeedArticle("old", "biology", "Old", "", "https://archive.org/article", "Archive", 1, 2), "Biology")
        store.ready("old", AttentionChineseArticle("旧文章", chinese, "fixture")); store.published("old")
        val probe = store.sourceProbe(setOf("biology"), 1000)!!
        assertEquals("archive.org", probe.host)
        assertNull(store.sourceProbe(setOf("biology"), 1001))
        assertEquals(chinese, store.body("old"))
        assertEquals(301000L, store.nextSourceProbe(setOf("biology")))
        store.sourceProbeDone(probe.host, 1_000_000, "no_declared_feed")
        assertNull(store.sourceProbe(setOf("biology"), 999999))
        assertNotNull(store.sourceProbe(setOf("biology"), 1_000_000))
    }

    @Test fun successfulTimeoutProgressAndModelDownloadDoNotWaitForOldExponentialBackoff() = isolated { name ->
        val store = AttentionArticleStore(context, name)
        for (id in listOf("timeout", "model")) store.enqueue(
            AttentionFeedArticle(id, "topic", "Title", "", "https://example.org/$id", "Example", 1, 2), "Topic")
        val first = store.claim(setOf("topic"), 1000)!!
        store.failed(first, "article_translation_timeout", 1000)
        store.continueTranslation(first.key, 1000)
        val other = store.claim(setOf("topic"), 1001)!!
        store.failed(other, "article_translation_model_pending", 1001)
        assertEquals(first.key, store.claim(setOf("topic"), 2000)!!.key)
        store.translationModelReady()
        assertEquals(other.key, store.claim(setOf("topic"), 2001)!!.key)
    }

    @Test fun learnedFeedReusesKnownWwwArticleIdentityWithoutMergingDifferentTitlesOrPaths() = isolated { name ->
        val store = AttentionArticleStore(context, name)
        val original = AttentionFeedArticle(ProactiveAttentionFeedPolicy.urlKey("https://www.publisher.org/story"),
            "topic", "AI research report", "", "https://www.publisher.org/story", "Publisher", 1, 2)
        store.enqueue(original, "Topic")
        val incoming = original.copy(key = ProactiveAttentionFeedPolicy.urlKey("https://publisher.org/story"), url = "https://publisher.org/story")
        assertEquals(original.key, store.knownPublisherArticle(incoming).key)
        assertEquals(original.url, store.knownPublisherArticle(incoming).url)
        assertEquals("https://publisher.org/other", store.knownPublisherArticle(incoming.copy(url = "https://publisher.org/other")).url)
        assertEquals(incoming.key, store.knownPublisherArticle(incoming.copy(title = "Different research report")).key)
        assertNotNull(store.metadata(original.key))
        assertNull(store.metadata(incoming.key))
    }

    @Test fun upgradePrunesOnlyLearnedCommentSubscriptionsWithoutRemovingArchiveBodies() = isolated { name ->
        val store = AttentionArticleStore(context, name)
        store.enqueue(AttentionFeedArticle("kept", "topic", "Research", "", "https://publisher.org/story", "Publisher", 1, 2), "Topic")
        store.ready("kept", AttentionChineseArticle("研究", chinese, "fixture")); store.published("kept")
        store.learnFeeds("https://publisher.org/story", listOf("https://publisher.org/feed"), setOf("topic"), 1000)
        AttentionArticleStore.closeTest(context, name)
        SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            db.execSQL("INSERT INTO learned_news_feeds(url,host,next_at) VALUES('https://publisher.org/comments/feed','publisher.org',0)")
            db.execSQL("INSERT INTO learned_news_topics VALUES('https://publisher.org/comments/feed','topic')")
            db.version = 10
        }
        val reopened = AttentionArticleStore(context, name)
        assertEquals("https://publisher.org/feed", reopened.dueLearnedFeed("topic", 1000))
        assertTrue(reopened.learnedFeedTopics("https://publisher.org/comments/feed").isEmpty())
        assertEquals(chinese, reopened.body("kept"))
        assertEquals("published", reopened.metadata("kept")!!.state)
    }

    @Test fun realPublishedSiteDeclaresFeedsAndAddsRecentRelevantArticles() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val url = args.getString("attention_follow_source").orEmpty()
        assumeTrue(url.isNotBlank())
        val preferences = ProactiveAttentionStore(context).preferences()
        assumeTrue(preferences.enabled && preferences.configured)
        val store = AttentionArticleStore(context)
        val key = ProactiveAttentionFeedPolicy.urlKey(ProactiveAttentionFeedPolicy.publicUrl(url)!!)
        val original = store.metadata(key)!!
        assertEquals("published", original.state)
        val topics = preferences.topics.filter { it.enabled && it.id in store.topics(key) }
        assertTrue(topics.isNotEmpty())
        val page = AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url,
            maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES, timeoutMillis = 10_000)
        val (source, feeds) = try {
            AttentionArticlePolicy.extractStructured(AgentWebIntelligenceFetched(page.finalUrl, page.contentType, page.body)) to
                AttentionLearnedFeedPolicy.discover(AgentWebTextDecoder.decode(page.body, page.contentType, page.finalUrl), page.finalUrl)
        } finally { page.body.fill(0) }
        assertTrue(feeds.isNotEmpty())
        val changed = store.learnFeeds(page.finalUrl, feeds, topics.map { it.id }.toSet(), System.currentTimeMillis())
        val feed = ProactiveAttentionFeedStore(context)
        changed.forEach { feed.sourceDiscovered(it, System.currentTimeMillis()) }
        var inserted = 0
        var candidates = 0
        var fetchedFeeds = 0
        for (endpoint in feeds) {
            val fetched = try { AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(endpoint,
                maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES, timeoutMillis = 10_000)
            } catch (cancelled: CancellationException) { throw cancelled
            } catch (failure: Exception) {
                InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                    putString("stream", "learned_feed_live url=$endpoint error=${failure.javaClass.simpleName}\n")
                })
                continue
            }
            fetchedFeeds++
            val records = try { ProactiveAttentionFeedPolicy.parse(fetched.body.toString(Charsets.UTF_8), original.topic,
                System.currentTimeMillis(), 30) } finally { fetched.body.fill(0) }
            for (record in records.map(store::knownPublisherArticle)) for (topic in topics) if (ProactiveAttentionFeedSources.matches(record, topic)) {
                candidates++; if (feed.ingest(record.copy(topicId = topic.id), topic)) inserted++
            }
        }
        assertTrue("No declared feed could be fetched", fetchedFeeds > 0)
        assertTrue("No relevant source articles found", candidates > 0)
        assertEquals("published", store.metadata(key)!!.state)
        assertTrue(source.article.content.isNotEmpty())
        ProactiveAttentionFeedScheduler.request(context); AttentionArticleScheduler.request(context)
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("stream", "learned_source_live url=$url feeds=${feeds.size} relevant=$candidates inserted=$inserted\n")
        })
    }

    private fun isolated(test: (String) -> Unit) {
        val name = "learned-feeds-${UUID.randomUUID()}.db"
        try { test(name) } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }
}
