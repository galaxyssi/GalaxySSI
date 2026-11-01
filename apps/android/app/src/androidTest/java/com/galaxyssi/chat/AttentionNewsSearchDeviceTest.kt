package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.os.CancellationSignal
import android.os.OperationCanceledException
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID
import org.json.JSONObject
import org.junit.Assume.assumeTrue

class AttentionNewsSearchDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(block: (AttentionArticleStore, AttentionNewsSearchState, SQLiteDatabase) -> Unit) {
        val name = "news-search-test-${UUID.randomUUID()}.db"
        try {
            val store = AttentionArticleStore(context, name)
            store.enqueue(AttentionFeedArticle("pending", "topic", "智能体", "", "https://example.com/draft", "Source", 1, 1), "技术")
            SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                db.beginTransaction()
                try {
                    db.compileStatement("INSERT INTO articles(id,url,topic,topic_title,title,zh_title,body,preview,publisher,published,collected,state) " +
                        "VALUES(?,?,'topic','人工智能','Original title',?,?,?,?,?,?,'published')").use { s ->
                        repeat(1003) { index ->
                            s.bindString(1, "news-%04d".format(index)); s.bindString(2, "https://example.com/$index")
                            s.bindString(3, "智能体新闻 $index"); s.bindString(4, "这是完整的中文新闻正文。".repeat(150) + "深处关键词 星际电池")
                            s.bindString(5, "这是中文摘要。".repeat(10)); s.bindString(6, if (index % 2 == 0) "Source A" else "Source B")
                            s.bindLong(7, index.toLong()); s.bindLong(8, index.toLong()); s.executeInsert()
                        }
                    }
                    db.setTransactionSuccessful()
                } finally { db.endTransaction() }
                val state = AttentionNewsSearchState((0..1002).associate { "news-%04d".format(it) to if (it % 2 == 0) 1L else 0L },
                    setOf(AttentionNewsSearchState.itemKey("news-0000"), AttentionNewsSearchState.itemKey("news-0900")))
                block(store, state, db)
            }
        } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }

    @Test fun allHistoricalPagesAreReachableWithoutDuplicatesOrFullBodyMaterialization() = fixture { store, state, _ ->
        val query = AttentionNewsQuery("智能体", sort = AttentionNewsSort.NEWEST, snapshot = 2000)
        val ids = mutableListOf<String>()
        val times = mutableListOf<Long>()
        do {
            val start = SystemClock.elapsedRealtime()
            val page = store.search(query, state, ids.size, CancellationSignal())
            times += SystemClock.elapsedRealtime() - start
            assertEquals(1003, page.total)
            assertTrue(page.hits.size <= 30)
            assertTrue(page.hits.all { it.snippet.length <= 220 })
            ids += page.hits.map { it.id }
        } while (page.hasMore)
        assertEquals(1003, ids.size); assertEquals(1003, ids.distinct().size)
        assertEquals("news-1002", ids.first()); assertEquals("news-0000", ids.last())
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("stream", "news_search_fixture rows=1003 pages=${times.size} max_ms=${times.max()}\n")
        })
    }
    @Test fun fullBodySourceAndChineseSubstringSearchAreNotLimitedToVisiblePreviews() = fixture { store, state, _ ->
        val page = store.search(AttentionNewsQuery("星际电池", snapshot = 2000), state, 0, CancellationSignal())
        assertEquals(1003, page.total); assertTrue(page.hits.all { it.snippet.contains("星际电池") })
        assertEquals(1003, store.search(AttentionNewsQuery("source", snapshot = 2000), state, 0, CancellationSignal()).total)
        assertEquals(502, store.search(AttentionNewsQuery("source", source = "Source A", snapshot = 2000), state, 0, CancellationSignal()).total)
        assertEquals(1003, store.search(AttentionNewsQuery("能体", snapshot = 2000), state, 0, CancellationSignal()).total)
        assertEquals(0, store.search(AttentionNewsQuery("智能体 不存在", snapshot = 2000), state, 0, CancellationSignal()).total)
    }
    @Test fun readSavedSourceTimeAndSnapshotFiltersComposeWithoutDiscardingHistory() = fixture { store, state, _ ->
        fun find(q: AttentionNewsQuery) = store.search(q, state, 0, CancellationSignal())
        val base = AttentionNewsQuery("智能体", snapshot = 2000)
        assertEquals(501, find(base.copy(scope = AttentionNewsScope.UNREAD)).total)
        assertEquals(2, find(base.copy(scope = AttentionNewsScope.SAVED)).total)
        assertEquals(1, find(base.copy(scope = AttentionNewsScope.SAVED, since = 500)).total)
        assertEquals(0, find(base.copy(scope = AttentionNewsScope.UNREAD, source = "Source A")).total)
        assertEquals(501, find(base.copy(snapshot = 500)).total)
        assertEquals(503, find(base.copy(since = 500)).total)
    }
    @Test fun escapedInputCancellationAndHiddenArticlesStayCorrect() = fixture { store, state, db ->
        db.execSQL("UPDATE articles SET zh_title = '50%_Value' WHERE id='news-0000'")
        fun find(text: String) = store.search(AttentionNewsQuery(text, snapshot = 2000), state, 0, CancellationSignal())
        assertEquals(listOf("news-0000"), find("50%_").hits.map { it.id })
        assertEquals(0, find("x' OR 1=1--").total)
        assertEquals(0, find("    ").total)
        db.execSQL("UPDATE articles SET state='repair' WHERE id='news-0001'")
        db.execSQL("UPDATE articles SET body='' WHERE id='news-0002'")
        assertEquals(1000, find("智能体").total)
        val cancel = CancellationSignal().apply { cancel() }
        assertThrows(OperationCanceledException::class.java) { store.search(AttentionNewsQuery("智能体"), state, 0, cancel) }
    }
    @Test fun relevancePrefersTitleAndSortHasStableTieBreaks() = fixture { store, state, db ->
        db.execSQL("UPDATE articles SET body=body || ' alpha' WHERE id IN ('news-0000','news-1002')")
        db.execSQL("UPDATE articles SET zh_title='alpha news' WHERE id='news-0000'")
        val relevance = store.search(AttentionNewsQuery("alpha"), state, 0, CancellationSignal())
        assertEquals(listOf("news-0000", "news-1002"), relevance.hits.map { it.id })
        val newest = store.search(AttentionNewsQuery("alpha", sort = AttentionNewsSort.NEWEST), state, 0, CancellationSignal())
        assertEquals(listOf("news-1002", "news-0000"), newest.hits.map { it.id })
    }
    @Test fun maximumLengthMultiTermQueryDoesNotExceedSqlParameterLimit() = fixture { store, state, _ ->
        val query = (0..127).joinToString(" ") { (0x4e00 + it).toChar().toString() }
        assertTrue(query.length <= AttentionNewsSearchPolicy.MAX_QUERY)
        assertEquals(0, store.search(AttentionNewsQuery(query), state, 0, CancellationSignal()).total)
    }

    @Test fun metadataSnapshotExcludesNonNewsDismissedAndObsoleteArticles() {
        val database = AgentEncryptedDatabase(context, "news-search-index-${UUID.randomUUID()}")
        try {
            val index = ProactiveMessageReadIndex(database)
            fun record(id: String, viewed: Long = 0L) = JSONObject().put("id", "attention-feed:$id")
                .put("status", "DELIVERED").put("news_article_key", id)
                .put("news_article_revision", AttentionArticlePolicy.REVISION).put("viewed_at_millis", viewed)
            index.prepare { sequenceOf(record("read", 100L), record("unread"),
                record("dismissed").put("status", "DISMISSED"), record("obsolete").put("news_article_revision", 0),
                JSONObject().put("id", "private-reminder").put("status", "DELIVERED")) }
            assertEquals(mapOf("read" to 100L, "unread" to 0L), index.newsViewed(CancellationSignal()))
        } finally { database.clear() }
    }

    @Test fun inspectLiveNewsSearchReadOnly() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verify_live_news") == "true")
        val store = AttentionArticleStore(context)
        val signal = CancellationSignal()
        val state = GlobalAgentRepository(context).newsSearchState(ProactiveAttentionStore(context).preferences().savedKeys, signal)
        for (keyword in listOf("智能体", "苹果", "生物", "的")) {
            val times = mutableListOf<Long>()
            var count = 0
            repeat(5) {
                val start = SystemClock.elapsedRealtime()
                val page = store.search(AttentionNewsQuery(keyword), state, 0, signal)
                times += SystemClock.elapsedRealtime() - start; count = page.total
                assertTrue(page.hits.size <= 30); assertTrue(page.hits.size <= page.total)
            }
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("stream", "news_search_live keyword=$keyword eligible=${state.viewed.size} matches=$count latency_ms=$times\n")
            })
        }
    }
}
