package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AttentionArticleRetryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val topics = setOf("ai_models")
    private val body = "\u7814\u7a76\u62a5\u544a\u6b63\u6587\u3002".repeat(30)

    @Test fun fourthFailedAttemptRemovesUnpublishedArticleAndPreventsRediscovery() = isolated { store, _ ->
        val rejected = article("reject")
        store.enqueue(rejected, "AI")
        store.translationProgress(rejected.key).save("partial", "draft")
        var now = 1L
        repeat(4) { prior ->
            val job = checkNotNull(store.claim(topics, now))
            assertEquals(prior, job.attempts)
            store.failed(job, "article_translation_not_chinese", now)
            if (prior < 3) {
                assertEquals(1, store.counts(topics).retrying)
                assertNull(store.claim(topics, now))
                now = checkNotNull(store.nextAt(topics))
            }
        }
        assertEquals(0, store.counts(topics).retrying)
        assertNull(store.nextAt(topics))
        assertEquals(0L, store.progressCount(rejected.key))
        assertTrue(store.topics(rejected.key).isEmpty())
        assertFalse(store.enqueue(rejected.copy(topicId = "other"), "Other"))
        assertNull(store.metadata(rejected.key))
    }

    @Test fun upgradeClearsAllOldFailuresWithoutTouchingPublishedOrUnattemptedArticles() = isolated { store, name ->
        val old = article("old")
        val published = article("published")
        val untouched = article("untouched")
        listOf(old, published, untouched).forEach { store.enqueue(it, "AI") }
        store.failed(checkNotNull(store.metadata(old.key)), "transport_failed", 10L)
        store.translationProgress(old.key).save("partial", "draft")
        store.ready(published.key, AttentionChineseArticle("Title", body, ""))
        store.published(published.key)
        AttentionArticleStore.closeTest(context, name)
        SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            db.execSQL("DROP TABLE discarded_article_ids")
            db.version = 11
        }

        val upgraded = AttentionArticleStore(context, name)
        assertEquals(AttentionArticleQueueCounts(1, 1, 0), upgraded.counts(topics))
        assertEquals(body, upgraded.body(published.key))
        assertEquals(0L, upgraded.progressCount(old.key))
        assertFalse(upgraded.enqueue(old, "AI"))
        assertEquals(untouched.key, upgraded.claim(topics, 20L)?.key)
    }

    @Test fun failedVisualRefreshPreservesPublishedBody() = isolated { store, _ ->
        val published = article("published")
        store.enqueue(published, "AI")
        store.ready(published.key, AttentionChineseArticle("Title", body, ""))
        store.published(published.key)
        assertTrue(store.requestVisual(published.key))
        var now = 1L
        repeat(4) { prior ->
            val job = checkNotNull(store.claim(topics, now))
            assertEquals(prior, job.attempts)
            store.failed(job, "transport_failed", now)
            if (prior < 3) now = checkNotNull(store.nextAt(topics))
        }
        assertEquals(body, store.body(published.key))
        assertEquals(1, store.counts(topics).published)
        assertFalse(store.requestVisual(published.key))
        assertNull(store.nextAt(topics))
    }

    private fun article(id: String) =
        AttentionFeedArticle(id, "ai_models", "Title", "", "https://example.org/$id", "example.org", 1L, 1L)

    private fun isolated(block: (AttentionArticleStore, String) -> Unit) {
        val name = "article-retry-test-${UUID.randomUUID()}.db"
        try { block(AttentionArticleStore(context, name), name) }
        finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }
}
