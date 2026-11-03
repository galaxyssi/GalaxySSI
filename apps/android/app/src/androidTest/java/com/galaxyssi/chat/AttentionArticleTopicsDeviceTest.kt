package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class AttentionArticleTopicsDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val body = "\u7814\u7a76\u56e2\u961f\u516c\u5e03\u4e86\u65b0\u7684\u7ed3\u679c\uff0c\u4fdd\u7559\u539f\u59cb\u6570\u636e\u4e0e\u6765\u6e90\u3002".repeat(10)

    @Test fun oneArticleMatchesTwoTopicsWithoutDuplicatePublicationOrQueueEntries() = isolated { store, _ ->
        val article = AttentionFeedArticle("same", "ai_models", "AI agents design proteins", "", "https://example.org/a", "example.org", 1, 2)
        store.enqueue(article, "AI")
        store.enqueue(article.copy(topicId = "protein_life_sciences"), "Biology")
        assertEquals(setOf("ai_models", "protein_life_sciences"), store.topics("same").keys)
        assertEquals(1, store.counts(setOf("ai_models", "protein_life_sciences")).waiting)
        val claimed = store.claim(setOf("protein_life_sciences"), 10)!!
        assertEquals("protein_life_sciences", claimed.topic)
        assertNull(store.claim(setOf("ai_models"), 11))
        store.ready("same", AttentionChineseArticle("\u7814\u7a76", body, ""))
        store.published("same")
        assertEquals(1, store.counts(setOf("ai_models", "protein_life_sciences")).published)
        assertNull(store.claim(setOf("ai_models"), 1_000_000))
        assertEquals(body, store.body("same"))
    }

    @Test fun disablingOriginalCategoryStillAllowsAnEnabledSecondaryCategory() = isolated { store, _ ->
        val article = AttentionFeedArticle("a", "industry", "AI Agent", "", "https://example.org/a", "Hacker News", 1, 2)
        store.enqueue(article, "Industry"); store.enqueue(article.copy(topicId = "agent_frontiers"), "Agents")
        assertNull(store.scopedMetadata("a", emptySet()))
        assertEquals("agent_frontiers", store.scopedMetadata("a", setOf("agent_frontiers"))!!.topic)
        assertEquals("example.org", store.metadata("a")!!.publisher)
        assertNotNull(store.nextAt(setOf("agent_frontiers")))
    }

    @Test fun versionSixMigrationKeepsPublishedBodiesAndRetriesOnlyAffectedFailures() = isolated { store, name ->
        for (id in listOf("published", "translate", "network")) {
            store.enqueue(AttentionFeedArticle(id, "ai_models", "AI", "", "https://example.org/$id", "example.org", 1, 2), "AI")
        }
        store.ready("published", AttentionChineseArticle("\u7814\u7a76", body, "")); store.published("published")
        store.failed(store.metadata("translate")!!, "article_translation_not_chinese", 100)
        store.failed(store.metadata("network")!!, "transport_failed", 100)
        AttentionArticleStore.closeTest(context, name)
        SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            db.execSQL("DROP TABLE article_topics")
            db.execSQL("INSERT OR REPLACE INTO metadata VALUES('legacy_done','1')")
            db.version = 6
        }
        val reopened = AttentionArticleStore(context, name)
        assertEquals(body, reopened.body("published"))
        assertEquals(setOf("ai_models"), reopened.topics("published").keys)
        assertEquals("translate", reopened.claim(setOf("ai_models"), 101)!!.key)
        assertNull(reopened.claim(setOf("ai_models"), 102))
    }

    private fun isolated(block: (AttentionArticleStore, String) -> Unit) {
        val name = "article-topic-test-${UUID.randomUUID()}.db"
        try { block(AttentionArticleStore(context, name), name) }
        finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }
}
