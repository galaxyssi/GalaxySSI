package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttentionNewsCurationDeviceTest {
    private val now = 1_800_000_000_000L
    private fun item(id: Int) = GlobalProactiveInboxItem("item-$id", setOf("message-$id"), "Research discovery number $id",
        "Complete translated preview", "Biology", GlobalProactiveTarget.NEW_CONVERSATION, false,
        "", "", emptySet(), now - id, now - id, 0, null, newsArticleKey = "article-$id")

    @Test fun metadataUsesActualPublisherHostAndOnlyEnabledMemberships() = database { db ->
        insert(db, 1, "https://www.actual.org/article", "Misleading feed label", listOf("disabled", "biology", "genetics"))
        val output = AttentionNewsCurationStore.decorate(db, listOf(item(1)), setOf("biology", "genetics"), now).single()
        assertEquals("actual.org", output.newsSummary!!.source)
        assertEquals(setOf("biology", "genetics"), output.newsSummary!!.topics)
        assertTrue(output.newsSummary!!.selected)
        assertEquals(item(1).messageIds, output.messageIds)
        assertEquals(item(1).viewedAtMillis, output.viewedAtMillis)
        assertFalse(output.urgent)
    }

    @Test fun missingDisabledAndNotYetPublishedArticlesNeverBecomeHighlights() = database { db ->
        insert(db, 1, topics = listOf("disabled"))
        insert(db, 2, state = "pending")
        insert(db, 3, state = "ready")
        insert(db, 4)
        val output = AttentionNewsCurationStore.decorate(db, (1..5).map(::item), setOf("biology"), now)
        assertEquals(5, output.size)
        assertEquals(listOf("item-4"), output.filter { it.newsSummary?.selected == true }.map { it.key })
        assertEquals(listOf("pending", "ready"), db.rawQuery("SELECT state FROM articles WHERE id IN ('article-2','article-3') ORDER BY id", null)
            .use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } })
    }

    @Test fun metadataBatchesBeyondSqlVariableLimitsWithoutTruncatingTheArchive() = database { db ->
        db.beginTransaction()
        try {
            (1..1205).forEach { insert(db, it) }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        val input = (1..1205).map(::item)
        val output = AttentionNewsCurationStore.decorate(db, input, setOf("biology"), now)
        assertEquals(input.map { it.key }, output.map { it.key })
        assertTrue(output.all { it.newsSummary != null })
        assertEquals(30, output.count { it.newsSummary?.selected == true })
        assertEquals(1205L, android.database.DatabaseUtils.longForQuery(db, "SELECT COUNT(*) FROM articles", null))
        assertTrue(AttentionNewsCurationStore.decorate(db, emptyList(), setOf("biology"), now).isEmpty())
    }

    @Test fun repeatedSelectionDoesNotModifyRowsAndDisabledSubscriptionsClearTransientPicks() = database { db ->
        insert(db, 1)
        val first = AttentionNewsCurationStore.decorate(db, listOf(item(1)), setOf("biology"), now)
        val before = android.database.DatabaseUtils.longForQuery(db, "SELECT total_changes()", null)
        assertEquals(first, AttentionNewsCurationStore.decorate(db, first, setOf("biology"), now))
        assertEquals(before, android.database.DatabaseUtils.longForQuery(db, "SELECT total_changes()", null))
        val disabled = AttentionNewsCurationStore.decorate(db, first, emptySet(), now)
        assertNull(disabled.single().newsSummary)
        assertEquals(item(1), disabled.single())
    }

    private fun insert(db: SQLiteDatabase, id: Int, url: String = "https://publisher.org/$id", publisher: String = "Publisher",
        topics: List<String> = listOf("biology"), state: String = "published") {
        db.execSQL("INSERT INTO articles VALUES(?,?,?,?,?,?,?)", arrayOf("article-$id", url, publisher, now - id, now - id, 0, state))
        topics.forEach { db.execSQL("INSERT INTO article_topics VALUES(?,?)", arrayOf("article-$id", it)) }
    }

    private fun database(test: (SQLiteDatabase) -> Unit) {
        SQLiteDatabase.create(null).use { db ->
            // Deliberately omit bodies/documents: highlights must only query lightweight metadata.
            db.execSQL("CREATE TABLE articles(id TEXT PRIMARY KEY,url TEXT,publisher TEXT,published INTEGER,collected INTEGER,knowledge INTEGER,state TEXT)")
            db.execSQL("CREATE TABLE article_topics(article_id TEXT,topic TEXT,PRIMARY KEY(article_id,topic))")
            test(db)
        }
    }
}
