package com.galaxyssi.chat

import android.content.Context
import android.app.NotificationManager
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.Assume.assumeTrue
import org.junit.runner.RunWith

/** Only isolated synthetic evidence; no provider calls, accounts, trades or existing research tasks. */
@RunWith(AndroidJUnit4::class)
class ProactiveAttentionDeviceTest {
    @Test fun inboxMigratesAndRetainsBeyondThreeHundredAcrossReopenAndRestore() = isolated { context ->
        val database = AgentEncryptedDatabase(context, GlobalAgentRepository.DATABASE_NAME)
        val legacy = org.json.JSONArray().apply { repeat(305) { index -> put(JSONObject()
            .put("id", "legacy-$index").put("source_event_id", "source-$index")
            .put("content", "fixture-$index").put("status", "DELIVERED").put("target", "NEW_CONVERSATION")
            .put("created_at_millis", index + 1).put("delivered_at_millis", index + 1)
            .put("viewed_at_millis", if (index == 0) 1000 else 0)) } }
        database.writeString("proactive_messages", legacy.toString())
        val repository = GlobalAgentRepository(context)
        assertEquals(305, repository.proactiveMessages().size)
        assertFalse(database.contains("proactive_messages"))
        repeat(900) { index -> assertTrue(repository.appendProactiveMessage(message().copy(
            id = "new-$index", sourceEventId = "new-source-$index", status = GlobalProactiveMessageStatus.DELIVERED))) }
        assertFalse(repository.appendProactiveMessage(message().copy(id = "duplicate", sourceEventId = "source-0")))
        repository.bindProactiveConversation("legacy-0", "fixture-conversation")
        repository.reviseProactiveMessage("legacy-0", "reviewed", true)
        assertEquals(1, repository.markProactiveViewed(setOf("new-0"), 2000))
        val reopened = GlobalAgentRepository(context)
        assertEquals(1205, reopened.proactiveMessages().size)
        assertEquals("fixture-conversation", reopened.proactiveMessage("legacy-0")!!.deliveredConversationId)
        assertEquals(1000L, reopened.proactiveMessage("legacy-0")!!.viewedAtMillis)
        assertEquals(2000L, reopened.proactiveMessage("new-0")!!.viewedAtMillis)
        val snapshot = reopened.exportSnapshot()
        reopened.clear()
        reopened.restoreSnapshot(snapshot)
        assertEquals(1205, reopened.proactiveMessages().size)
        assertEquals("reviewed", reopened.proactiveMessage("legacy-0")!!.content)
        assertFalse(reopened.appendProactiveMessage(message().copy(id = "duplicate2", sourceEventId = "source-0")))
        assertTrue(reopened.appendProactiveMessage(message().copy(id = "case-sensitive", sourceEventId = "SOURCE-0")))
        val longPrefix = "source".repeat(450)
        assertTrue(reopened.appendProactiveMessage(message().copy(id = "long-a", sourceEventId = longPrefix + "a")))
        assertTrue(reopened.appendProactiveMessage(message().copy(id = "long-b", sourceEventId = longPrefix + "b")))
    }

    @Test fun feedAndEvidenceKeepMoreThanFiveHundredWithoutEvictingSavedArticles() = isolated { context ->
        val now = System.currentTimeMillis()
        val topic = AttentionTopic("ai_models", "AI", "AI")
        val attention = ProactiveAttentionStore(context)
        attention.update { it.copy(configured = true, topics = listOf(topic)) }
        val legacyRecord = JSONObject().put("key", "legacy-feed").put("topic", topic.id)
            .put("title", "Legacy").put("summary", "Fixture").put("url", "https://example.org/legacy")
            .put("publisher", "Fixture").put("published", now).put("collected", now).put("review", "pending")
        val feedDatabase = AgentEncryptedDatabase(context, "attention_feed_v1")
        feedDatabase.writeString("articles", org.json.JSONArray().put(legacyRecord).toString())
        val evidenceDatabase = AgentEncryptedDatabase(context, GlobalAgentRepository.DATABASE_NAME)
        evidenceDatabase.writeString("proactive_attention_evidence_v1", JSONObject()
            .put("legacy-evidence", JSONObject().put("sources", org.json.JSONArray().put(JSONObject().put("url", "https://example.org/legacy"))))
            .toString())
        assertNotNull(attention.evidence("legacy-evidence"))
        val store = ProactiveAttentionFeedStore(context)
        val first = AttentionFeedArticle("news-0", topic.id, "Fixture", "Summary", "https://example.org/0", "Fixture", now, now)
        repeat(605) { index -> assertTrue(store.ingest(first.copy(key = "news-$index", url = "https://example.org/$index"), topic)) }
        val repository = GlobalAgentRepository(context)
        attention.update { it.copy(savedKeys = setOf("global-agent:attention-feed:news-0")) }
        assertEquals(605, repository.proactiveMessages().size)
        assertEquals(606, feedDatabase.countKeys("article:"))
        assertEquals(606, evidenceDatabase.countKeys("proactive_attention_evidence_row:"))
        assertFalse(feedDatabase.contains("articles"))
        assertFalse(evidenceDatabase.contains("proactive_attention_evidence_v1"))
        val reopened = ProactiveAttentionFeedStore(context)
        assertFalse(reopened.ingest(first, topic))
        val message = repository.proactiveMessage("attention-feed:news-0")!!
        assertNotNull(ProactiveAttentionStore(context).evidence(message.sourceEventId))
        assertNotNull(ProactiveAttentionStore(context).evidence("legacy-evidence"))
        val items = GlobalProactiveInboxPolicy.project(repository.proactiveMessages(), emptyList())
        val timeline = ProactiveAttentionTimeline().apply {
            update(items, attention.preferences().savedKeys); begin(AttentionFeedFilter.SAVED)
        }
        assertEquals(message.id, timeline.visible.single().messageIds.single())
    }

    @Test fun malformedLegacyMigrationRollsBackWithoutLosingOriginalRecords() = isolated { context ->
        val database = AgentEncryptedDatabase(context, "attention_feed_v1")
        val legacy = """[{"key":"valid"},{"unexpected":true}]"""
        database.writeString("articles", legacy)
        val rows = ProactiveRecordRows(database, "article:", "articles", { it.getString("key") })
        assertTrue(runCatching { rows.all().toList() }.isFailure)
        assertEquals(legacy, database.readString("articles", ""))
        assertEquals(0, database.countKeys("article:"))
    }

    @Test fun continuousReaderKeepsExpandedContentAndAnchorWhileNewStoriesArrive() = isolated { context ->
        val repository = GlobalAgentRepository(context)
        repeat(65) { index -> repository.appendProactiveMessage(message().copy(id = "reader-$index",
            sourceEventId = "reader-$index", title = "Fixture $index", content = "**Fixture $index**\n\nBody $index",
            status = GlobalProactiveMessageStatus.DELIVERED, deliveredAtMillis = index + 1L)) }
        val worker = java.util.concurrent.Executors.newSingleThreadExecutor()
        var reader: ProactiveAttentionReader? = null
        var asks = 0
        ActivityScenario.launch<ProactiveAttentionActivity>(Intent(instrumentation.targetContext, ProactiveAttentionActivity::class.java)).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    val original = ProactiveAttentionActivity::class.java.getDeclaredField("reader").apply { isAccessible = true }
                        .get(activity) as ProactiveAttentionReader
                    original.pause()
                    reader = ProactiveAttentionReader(activity, worker, { asks++ }, {}, { _, callback -> callback(null) }, {}, context)
                    activity.setContentView(reader!!.view)
                    reader!!.update(GlobalProactiveInboxPolicy.project(repository.proactiveMessages(), emptyList()),
                        emptySet(), AttentionReaderState())
                }
                await(scenario) { views(it).any { view -> view.tag == "attention-item:global-agent:reader-64" } }
                var body: View? = null
                var initialTop = 0
                scenario.onActivity {
                    assertFalse(views(it.window.decorView).any { view -> view.tag == "attention-page-count" })
                    reader!!.list.scrollBy(0, 40)
                    val row = views(it.window.decorView).filterIsInstance<ProactiveAttentionArticleView>().first()
                    row.readable.performClick()
                }
                await(scenario) { views(it).any { view -> view.tag == "attention-expanded:global-agent:reader-64" } }
                scenario.onActivity {
                    body = views(it.window.decorView).first { view -> view.tag == "attention-expanded:global-agent:reader-64" }
                    initialTop = reader!!.list.getChildAt(0).top
                }
                repository.appendProactiveMessage(message().copy(id = "reader-new", sourceEventId = "reader-new",
                    title = "New fixture", status = GlobalProactiveMessageStatus.DELIVERED, deliveredAtMillis = 1000))
                repository.reviseProactiveMessage("reader-64", "New reviewed body", false)
                scenario.onActivity {
                    reader!!.update(GlobalProactiveInboxPolicy.project(repository.proactiveMessages(), emptyList()),
                        emptySet(), AttentionReaderState())
                    assertEquals("global-agent:reader-64", reader!!.timeline.visible.first().key)
                    assertEquals(1, reader!!.timeline.newerCount)
                    assertSame(body, views(it.window.decorView).first { view -> view.tag == "attention-expanded:global-agent:reader-64" })
                    assertEquals(initialTop, reader!!.list.getChildAt(0).top)
                    assertEquals(0, asks)
                    reader!!.pause()
                    reader!!.persist()
                }
                worker.submit {}.get(10, java.util.concurrent.TimeUnit.SECONDS)
                val restored = ProactiveAttentionReaderStateStore(context).read()
                assertTrue("global-agent:reader-64" in restored.expanded)
                assertEquals("global-agent:reader-64", restored.anchor)
                scenario.onActivity { activity ->
                    reader!!.destroy()
                    reader = ProactiveAttentionReader(activity, worker, { asks++ }, {}, { _, callback -> callback(null) }, {}, context)
                    activity.setContentView(reader!!.view)
                    reader!!.update(GlobalProactiveInboxPolicy.project(repository.proactiveMessages(), emptyList()), emptySet(), restored)
                }
                await(scenario) { views(it).any { view -> view.tag == "attention-expanded:global-agent:reader-64" } }
                scenario.onActivity {
                    assertEquals(initialTop, reader!!.list.getChildAt(0).top)
                    assertTrue(reader!!.timeline.expanded.contains(restored.anchor))
                    (reader!!.list.layoutManager as androidx.recyclerview.widget.LinearLayoutManager).scrollToPositionWithOffset(19, 0)
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { reader!!.list.scrollBy(0, 80) }
                await(scenario) { reader!!.timeline.visible.size > 20 }
                scenario.onActivity {
                    assertTrue(reader!!.list.childCount < 12)
                    assertEquals(0, asks)
                    (reader!!.list.layoutManager as androidx.recyclerview.widget.LinearLayoutManager).scrollToPositionWithOffset(0, -40)
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { views(it.window.decorView).first { view -> view.tag == "attention-reader-updates" }.performClick() }
                worker.submit {}.get(10, java.util.concurrent.TimeUnit.SECONDS)
                assertEquals("global-agent:reader-64", ProactiveAttentionReaderStateStore(context).read().anchor)
                instrumentation.waitForIdleSync()
                scenario.onActivity {
                    views(it.window.decorView).first { view -> view.tag == "attention-collapse:global-agent:reader-64" }.performClick()
                }
                worker.submit {}.get(10, java.util.concurrent.TimeUnit.SECONDS)
                assertEquals(0, ProactiveAttentionReaderStateStore(context).read().offset)
            } finally {
                scenario.onActivity { reader?.pause(); reader?.destroy() }
                worker.shutdown(); assertTrue(worker.awaitTermination(10, java.util.concurrent.TimeUnit.SECONDS))
            }
        }
    }

    @Test fun readerAutomaticallyMarksVisibleNewsAndBookmarkCanBeUndone() = isolated { context ->
        val repository = GlobalAgentRepository(context)
        repository.appendProactiveMessage(message().copy(id = "reader-auto", sourceEventId = "reader-auto",
            title = "Reader fixture", content = "Visible synthetic summary.", status = GlobalProactiveMessageStatus.DELIVERED,
            deliveredAtMillis = 1000))
        val worker = java.util.concurrent.Executors.newSingleThreadExecutor()
        var reader: ProactiveAttentionReader? = null
        ActivityScenario.launch<ProactiveAttentionActivity>(Intent(instrumentation.targetContext, ProactiveAttentionActivity::class.java)).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    (ProactiveAttentionActivity::class.java.getDeclaredField("reader").apply { isAccessible = true }
                        .get(activity) as ProactiveAttentionReader).pause()
                    reader = ProactiveAttentionReader(activity, worker, { fail("Reading must not launch Agent") }, {},
                        { _, callback -> callback(null) }, {}, context)
                    activity.setContentView(reader!!.view)
                    reader!!.update(GlobalProactiveInboxPolicy.project(repository.proactiveMessages(), emptyList()),
                        emptySet(), AttentionReaderState(filter = AttentionFeedFilter.UNREAD))
                    reader!!.resume()
                }
                await(scenario) { reader!!.timeline.unreadCount == 0 }
                assertTrue(repository.proactiveMessage("reader-auto")!!.viewedAtMillis > 0)
                scenario.onActivity {
                    assertEquals(1, reader!!.timeline.visible.size)
                    val headline = views(it.window.decorView).first { view -> view.tag == "attention-headline:global-agent:reader-auto" } as TextView
                    assertEquals(it.getColor(R.color.attention_unread_title), headline.currentTextColor)
                    assertEquals(1f, headline.alpha, 0f)
                    views(it.window.decorView).filterIsInstance<ProactiveAttentionArticleView>().first().readable.performClick()
                }
                await(scenario) { views(it).any { view -> view.tag == "attention-expanded:global-agent:reader-auto" } }
                scenario.onActivity {
                    val headline = views(it.window.decorView).first { view -> view.tag == "attention-headline:global-agent:reader-auto" } as TextView
                    assertEquals(it.getColor(R.color.attention_unread_title), headline.currentTextColor)
                    views(it.window.decorView).first { view -> view.contentDescription == it.getString(R.string.attention_save) }.performClick()
                }
                await(scenario) { ProactiveAttentionStore(context).preferences().savedKeys.isNotEmpty() &&
                    views(it).filterIsInstance<TextView>().any { view -> view.text == context.getString(R.string.attention_undo) } }
                scenario.onActivity {
                    val bookmark = views(it.window.decorView).first { view -> view.contentDescription == it.getString(R.string.attention_unsave) }
                    assertTrue(bookmark.isSelected)
                    views(it.window.decorView).filterIsInstance<TextView>().first { view -> view.text == it.getString(R.string.attention_undo) }.performClick()
                }
                await(scenario) { ProactiveAttentionStore(context).preferences().savedKeys.isEmpty() }
                scenario.onActivity {
                    reader!!.pause()
                    assertEquals(1, reader!!.timeline.visible.size)
                    val headline = views(it.window.decorView).first { view -> view.tag == "attention-headline:global-agent:reader-auto" } as TextView
                    assertEquals(it.getColor(R.color.attention_unread_title), headline.currentTextColor)
                    it.setContentView(android.widget.FrameLayout(it))
                    it.setContentView(reader!!.view)
                    assertEquals(it.getColor(R.color.text_primary), headline.currentTextColor)
                }
                worker.submit {}.get(10, java.util.concurrent.TimeUnit.SECONDS)
                val restored = ProactiveAttentionReaderStateStore(context).read()
                scenario.onActivity { activity ->
                    reader!!.destroy()
                    reader = ProactiveAttentionReader(activity, worker, { fail("Reading must not launch Agent") }, {},
                        { _, callback -> callback(null) }, {}, context)
                    activity.setContentView(reader!!.view)
                    reader!!.update(GlobalProactiveInboxPolicy.project(repository.proactiveMessages(), emptyList()), emptySet(), restored)
                }
                await(scenario) { views(it).any { view -> view.tag == "attention-headline:global-agent:reader-auto" } }
                scenario.onActivity {
                    val headline = views(it.window.decorView).first { view -> view.tag == "attention-headline:global-agent:reader-auto" } as TextView
                    assertEquals(it.getColor(R.color.text_primary), headline.currentTextColor)
                    assertEquals(1f, headline.alpha, 0f)
                }
            } finally {
                scenario.onActivity { reader?.pause(); reader?.destroy() }
                worker.shutdown(); assertTrue(worker.awaitTermination(10, java.util.concurrent.TimeUnit.SECONDS))
            }
        }
    }

    @Test fun attentionTitleColorsRemainLegibleInLightAndDarkModes() {
        listOf(android.content.res.Configuration.UI_MODE_NIGHT_NO,
            android.content.res.Configuration.UI_MODE_NIGHT_YES).forEach { mode ->
            val configuration = android.content.res.Configuration(instrumentation.targetContext.resources.configuration).apply {
                uiMode = (uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK.inv()) or mode
            }
            val context = instrumentation.targetContext.createConfigurationContext(configuration)
            val background = context.getColor(R.color.page_bg)
            val unread = context.getColor(R.color.attention_unread_title)
            val read = context.getColor(R.color.text_primary)
            assertNotEquals(unread, read)
            assertTrue(androidx.core.graphics.ColorUtils.calculateContrast(unread, background) >= 4.5)
            assertTrue(androidx.core.graphics.ColorUtils.calculateContrast(read, background) >= 4.5)
        }
    }

    @Test fun streamedNewStoryAndReplayProduceOneInboxItem() = isolated { context ->
        val topic = AttentionTopic("ai_models", "AI", "AI")
        ProactiveAttentionStore(context).update { it.copy(configured = true, topics = listOf(topic)) }
        val store = ProactiveAttentionPushStore(context)
        val received = java.util.concurrent.CountDownLatch(3)
        val error = java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val client = okhttp3.OkHttpClient()
        okhttp3.mockwebserver.MockWebServer().use { server ->
            val baseline = "event: put\ndata: {\"path\":\"/\",\"data\":[11,10]}\n\n"
            val update = "event: patch\ndata: {\"path\":\"/\",\"data\":{\"0\":12,\"1\":11}}\n\n"
            server.enqueue(okhttp3.mockwebserver.MockResponse().setHeader("Content-Type", "text/event-stream")
                .setBody(baseline + update + update))
            val source = okhttp3.sse.EventSources.createFactory(client).newEventSource(
                okhttp3.Request.Builder().url(server.url("/events")).build(), object : okhttp3.sse.EventSourceListener() {
                    override fun onEvent(source: okhttp3.sse.EventSource, id: String?, type: String?, data: String) {
                        runCatching {
                            store.accept(type!!, data)
                            store.next()?.let { storyId ->
                                val now = System.currentTimeMillis()
                                val json = """{"id":$storyId,"type":"story","time":${now / 1000},"title":"New AI model","url":"https://example.org/streamed"}"""
                                val article = ProactiveAttentionPushPolicy.article(json, storyId, now)!!
                                ProactiveAttentionFeedStore(context).ingest(article.copy(topicId = topic.id), topic)
                                store.complete(storyId)
                            }
                        }.onFailure(error::set)
                        received.countDown()
                    }
                    override fun onFailure(source: okhttp3.sse.EventSource, t: Throwable?, response: okhttp3.Response?) {
                        error.set(t ?: IllegalStateException("Stream failed"))
                        while (received.count > 0) received.countDown()
                    }
                })
            try {
                assertTrue(received.await(10, java.util.concurrent.TimeUnit.SECONDS))
                error.get()?.let { throw AssertionError("Fixture stream failed", it) }
                assertEquals(1, GlobalAgentRepository(context).proactiveMessages().size)
                assertNull(store.next())
            } finally { source.cancel(); client.dispatcher.cancelAll(); client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown() }
        }
    }

    @Test fun pushCursorAndPendingArticlesSurviveReopenAndBackoff() = isolated { context ->
        val now = System.currentTimeMillis()
        val first = ProactiveAttentionPushStore(context)
        first.accept("put", """{"path":"/","data":[11,10]}""", now)
        assertNull(first.next(now))
        first.accept("patch", """{"path":"/","data":{"0":12,"1":11}}""", now)
        val reopened = ProactiveAttentionPushStore(context)
        assertEquals(12L, reopened.next(now))
        reopened.defer(12, now)
        assertNull(first.next(now))
        assertEquals(12L, first.next(now + 10_000))
        first.complete(12)
        reopened.accept("put", """{"path":"/","data":[12,11]}""", now + 20_000)
        assertNull(reopened.next(now + 20_000))
    }

    @Test fun pushAndRssShareInboxIdentityAndNeverInventOriginalDates() = isolated { context ->
        val topic = AttentionTopic("ai_models", "AI", "AI")
        ProactiveAttentionStore(context).update { it.copy(configured = true, topics = listOf(topic)) }
        val now = System.currentTimeMillis()
        val story = """{"id":12,"type":"story","time":${now / 1000},"title":"New AI model","url":"https://example.org/model"}"""
        val article = ProactiveAttentionPushPolicy.article(story, 12, now)!!.copy(topicId = topic.id)
        val store = ProactiveAttentionFeedStore(context)
        assertTrue(store.ingest(article, topic))
        assertFalse(store.ingest(article.copy(discoveryDate = false), topic))
        val message = GlobalAgentRepository(context).proactiveMessages().single()
        val evidence = ProactiveAttentionStore(context).evidence(message.sourceEventId)!!
        assertEquals(0L, evidence.getJSONArray("sources").getJSONObject(0).getLong("published"))
        assertTrue(message.content.contains(context.getString(R.string.attention_source_discovered,
            java.time.Instant.ofEpochMilli(now).atZone(java.time.ZoneOffset.UTC).toLocalDate().toString())))
    }

    @Test fun livePhoneStreamReceivesEventsWithoutRelayOrModel() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_live_push") == "true")
        isolated { context ->
            val received = java.util.concurrent.CountDownLatch(1)
            val client = okhttp3.OkHttpClient.Builder().connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS).build()
            val error = java.util.concurrent.atomic.AtomicReference<Throwable?>()
            val store = ProactiveAttentionPushStore(context)
            val started = SystemClock.elapsedRealtime()
            val source = okhttp3.sse.EventSources.createFactory(client).newEventSource(
                okhttp3.Request.Builder().url(ProactiveAttentionPushPolicy.STREAM).header("Accept", "text/event-stream").build(),
                object : okhttp3.sse.EventSourceListener() {
                    override fun onEvent(source: okhttp3.sse.EventSource, id: String?, type: String?, data: String) {
                        if (type !in setOf("put", "patch")) return
                        runCatching { store.accept(type!!, data) }.onFailure(error::set)
                        received.countDown()
                    }
                    override fun onFailure(source: okhttp3.sse.EventSource, t: Throwable?, response: okhttp3.Response?) {
                        error.set(t ?: IllegalStateException("HTTP ${response?.code}")); received.countDown()
                    }
                })
            try {
                assertTrue("No phone-side SSE event", received.await(40, java.util.concurrent.TimeUnit.SECONDS))
                error.get()?.let { throw AssertionError("Source stream failed", it) }
                val snapshot = store.snapshot()
                assertTrue(snapshot.getBoolean("initialized"))
                assertTrue(snapshot.getJSONObject("slots").length() > 0)
                File(instrumentation.targetContext.getExternalFilesDir(null), "attention-push-live-evidence.json").writeText(
                    JSONObject().put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                        .put("snapshot_ids", snapshot.getJSONObject("slots").length()).put("model_dispatches", 0)
                        .put("desktop_required", false).toString())
            } finally { source.cancel(); client.dispatcher.cancelAll(); client.connectionPool.evictAll(); client.dispatcher.executorService.shutdown() }
        }
    }
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    @Test fun feedPublishesWithoutAModelAndReviewUpdatesTheSameReadItem() = isolated { context ->
        val now = System.currentTimeMillis()
        val topic = AttentionTopic("ai_models", "AI models", "AI models")
        ProactiveAttentionStore(context).update { it.copy(configured = true, allowPairedModel = false,
            allowCloudModel = false, topics = it.topics.map { t -> t.copy(enabled = t.id == topic.id) }) }
        val repository = GlobalAgentRepository(context)
        val before = GlobalModelCallBudgetStore(context).snapshot(repository.settings()).dispatchesInWindow
        val article = AttentionFeedArticle("fixture-news", topic.id, "Synthetic release", "Source-provided summary",
            "https://github.com/example/project/releases", "Publisher", now, now)
        val feed = ProactiveAttentionFeedStore(context)
        assertTrue(feed.ingest(article, topic))
        val original = repository.proactiveMessages().single()
        assertEquals(GlobalProactiveMessageStatus.DELIVERED, original.status)
        assertTrue(original.deliveredConversationId.isBlank())
        assertTrue(original.content.contains(context.getString(R.string.attention_source_summary)))
        assertFalse(original.urgent)
        repository.markProactiveViewed(setOf(original.id), now + 1)
        assertFalse(ProactiveAttentionFeedStore(context).ingest(article, topic))
        assertEquals(1, repository.proactiveMessages().size)
        val plan = feed.nextPlan(task("attention-research:ai_models"), now)!!
        val ledger = GlobalEvidenceLedger(sources = listOf(GlobalEvidenceSource(article.url,
            GlobalEvidenceSourceKind.OFFICIAL, 1.0, "Publisher")), verified = true)
        val reviewed = ProactiveAttentionNewsPolicy.Reviewed("Verified fixture", ledger, 1,
            listOf(ProactiveAttentionNewsPolicy.ReviewedItem("Verified fixture", ledger, false)))
        feed.finish(task("attention-research:ai_models").copy(researchPlan = plan), reviewed, "test")
        val updated = GlobalAgentRepository(context).proactiveMessages().single()
        assertEquals(original.id, updated.id)
        assertEquals(original.deliveredAtMillis, updated.deliveredAtMillis)
        assertTrue(updated.viewedAtMillis > 0)
        assertTrue(updated.content.startsWith("Verified fixture"))
        assertNull(ProactiveAttentionFeedStore(context).nextPlan(task("attention-research:ai_models"), now))
        assertEquals(before, GlobalModelCallBudgetStore(context).snapshot(repository.settings()).dispatchesInWindow)
    }

    @Test fun unavailableOriginalDoesNotRetractTheFeedOrLoopOnTheSameEvidence() = isolated { context ->
        val now = System.currentTimeMillis()
        val topic = AttentionTopic("ai_models", "AI models", "AI models")
        ProactiveAttentionStore(context).update { it.copy(configured = true) }
        val feed = ProactiveAttentionFeedStore(context)
        feed.ingest(AttentionFeedArticle("unavailable", topic.id, "Source headline", "",
            "https://example.org/news", "Source", now, now), topic)
        val task = task("attention-research:ai_models")
        feed.finish(task.copy(researchPlan = feed.nextPlan(task, now)!!), null, "source_unavailable")
        val message = GlobalAgentRepository(context).proactiveMessages().single()
        assertEquals(GlobalProactiveMessageStatus.DELIVERED, message.status)
        assertTrue(message.content.contains(context.getString(R.string.attention_not_verified)))
        assertNull(ProactiveAttentionFeedStore(context).nextPlan(task, now))
        assertFalse(message.urgent)
    }

    @Test fun disabledTopicDoesNotReceiveANetworkResultThatArrivesLate() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        store.update { it.copy(configured = true, enabled = false) }
        val now = System.currentTimeMillis()
        assertFalse(ProactiveAttentionFeedStore(context).ingest(AttentionFeedArticle("disabled", "ai_models",
            "Headline", "", "https://example.org/news", "Source", now, now),
            AttentionTopic("ai_models", "AI", "AI")))
        assertTrue(GlobalAgentRepository(context).proactiveMessages().isEmpty())
    }

    @Test fun invalidReviewBacksOffDurablyAndDoesNotBlockAnotherArticle() = isolated { context ->
        val now = System.currentTimeMillis()
        val topic = AttentionTopic("ai_models", "AI models", "AI models")
        ProactiveAttentionStore(context).update { it.copy(configured = true) }
        val feed = ProactiveAttentionFeedStore(context)
        val article = AttentionFeedArticle("invalid-review", topic.id, "Source headline", "Summary",
            "https://example.org/invalid-review", "Source", now, now)
        feed.ingest(article, topic)
        val task = task("attention-research:ai_models")
        feed.finish(task.copy(researchPlan = feed.nextPlan(task, now)!!), null, "attention_review_invalid")
        assertNull(ProactiveAttentionFeedStore(context).nextPlan(task, now + 1000))
        assertNotNull(ProactiveAttentionFeedStore(context).nextPlan(task, now + 61 * 60_000L))
        feed.ingest(article.copy(key = "other-article", url = "https://example.org/other"), topic)
        val next = ProactiveAttentionFeedStore(context).nextPlan(task, now + 1000)!!
        assertEquals("attention-feed:other-article", next.units.single().id)
        assertEquals(2, GlobalAgentRepository(context).proactiveMessages().size)
    }

    @Test fun exhaustedLearningBudgetAndOneFailedSourceDoNotBlockCollection() = isolated { context ->
        val repository = GlobalAgentRepository(context)
        val settings = repository.settings().copy(enabled = true, dailyBackgroundModelCallBudget = 0,
            dailyBackgroundTokenBudget = 10_000)
        repository.saveSettings(settings)
        ProactiveAttentionStore(context).update { it.copy(configured = true,
            topics = it.topics.map { t -> t.copy(enabled = t.id == "ai_models") }) }
        val now = System.currentTimeMillis()
        val budget = GlobalModelCallBudgetStore(context)
        assertTrue(budget.acquire(GlobalModelCallKind.RESEARCH_EVIDENCE, "exhaust", 60000, settings).granted)
        budget.complete(GlobalModelCallKind.RESEARCH_EVIDENCE, "exhaust", 10_000, 1, 0, "fixture")
        assertEquals(GlobalModelCallBudgetDenial.TOKEN_LIMIT, budget.availability(settings).denial)
        val before = budget.snapshot(settings)
        val date = java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME.format(
            java.time.Instant.ofEpochMilli(now).atZone(java.time.ZoneOffset.UTC))
        var requests = 0
        val collector = ProactiveAttentionFeedCollector(context) {
            requests++
            if (requests == 1) throw java.io.IOException("offline fixture")
            "<rss><channel><item><title>Fixture public release</title><link>https://example.org/release</link>" +
                "<source>Fixture publisher</source><pubDate>$date</pubDate></item></channel></rss>"
        }
        val cycle = collector.collect(now)
        assertEquals(1, cycle.newItems)
        assertEquals(2, requests)
        assertEquals(1, repository.proactiveMessages().size)
        assertEquals(before.totalTokensInWindow, budget.snapshot(settings).totalTokensInWindow)
        assertEquals(before.dispatchesInWindow, budget.snapshot(settings).dispatchesInWindow)
        assertEquals(cycle.nextAt, ProactiveAttentionFeedStore(context).topicState("ai_models").optLong("next"))
        collector.collect(now + 1)
        assertEquals(2, requests)
    }

    @Test fun livePublicFeedUsesNoModelAndDoesNotTouchUserTopics() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_live_feed") == "true")
        isolated { context ->
            val repository = GlobalAgentRepository(context)
            repository.saveSettings(repository.settings().copy(enabled = true))
            ProactiveAttentionStore(context).update { it.copy(configured = true,
                topics = it.topics.map { t -> t.copy(enabled = t.id == "ai_models") }) }
            val started = SystemClock.elapsedRealtime()
            val result = ProactiveAttentionFeedCollector(context).collect()
            val elapsed = SystemClock.elapsedRealtime() - started
            assertTrue("No live articles delivered: " + result.error, result.newItems > 0)
            assertTrue(repository.proactiveMessages().all { it.status == GlobalProactiveMessageStatus.DELIVERED })
            assertEquals(0, GlobalModelCallBudgetStore(context).snapshot(repository.settings()).dispatchesInWindow)
            File(instrumentation.targetContext.getExternalFilesDir(null), "attention-feed-live-evidence.json")
                .writeText(org.json.JSONObject().put("at", System.currentTimeMillis())
                    .put("new_items", result.newItems).put("elapsed_ms", elapsed).put("model_dispatches", 0)
                    .put("isolated_fixture", true).toString())
        }
    }

    @Test fun publisherCachesKeepTheirOwnBodiesAndExpire() = isolated { context ->
        val store = ProactiveAttentionFeedStore(context)
        val now = System.currentTimeMillis()
        val first = "<rss><channel><title>Technology</title></channel></rss>"
        val second = "<rss><channel><title>Finance</title></channel></rss>"
        store.cacheFeed("https://one.example/rss", first, now)
        store.cacheFeed("https://two.example/rss", second, now)
        assertEquals(first, ProactiveAttentionFeedStore(context).cachedFeed("https://one.example/rss", now + 1))
        assertEquals(second, ProactiveAttentionFeedStore(context).cachedFeed("https://two.example/rss", now + 1))
        assertNull(store.cachedFeed("https://one.example/rss", now + 6 * 60_000L))
    }

    @Test fun subscribedAlertsHonorSelectedModeWithoutUnsolicitedHeuristics() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        store.update { it.copy(configured = true, alertMode = AttentionAlertMode.IMPORTANT) }
        val task = task("attention-research:macro").copy(lastResultFingerprint = "alert-test",
            evidenceLedger = GlobalEvidenceLedger(sources = listOf(GlobalEvidenceSource(
                "https://example.org/original", GlobalEvidenceSourceKind.OFFICIAL, 1.0, "Original")), verified = true))
        val finding = message().copy(sourceEventId = ProactiveAttentionStore.eventId(task), urgent = true)
        assertFalse(AgentCognitiveEvalBridge.shouldNotify(context, finding))
        store.saveEvidence(task, true)
        assertTrue(AgentCognitiveEvalBridge.shouldNotify(context, finding))
        assertFalse(AgentCognitiveEvalBridge.shouldNotify(context, finding.copy(urgent = false)))
        assertFalse(AgentCognitiveEvalBridge.shouldNotify(context, finding.copy(content = "Expired notice\n2020-01-01")))
        store.update { it.copy(alertMode = AttentionAlertMode.ALL) }
        assertTrue(AgentCognitiveEvalBridge.shouldNotify(context, finding.copy(urgent = false)))
        store.update { it.copy(alertMode = AttentionAlertMode.SILENT) }
        assertFalse(AgentCognitiveEvalBridge.shouldNotify(context, finding))
    }

    @Test fun oldCountBlockedEvidenceResumesWithoutErasingUsage() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        store.update { it.copy(configured = true) }
        val repository = GlobalAgentRepository(context)
        val coordinator = ProactiveAttentionCoordinator(context)
        coordinator.reconcile()
        val original = repository.researchTasks().first()
        val collected = GlobalResearchUnit(purpose = GlobalResearchUnitPurpose.CHANGE_MONITOR,
            question = "Public fixture", sourceFocus = "Original page", result = "Retained original evidence",
            status = GlobalResearchUnitStatus.COMPLETED)
        repository.upsertResearchTask(original.copy(status = GlobalResearchTaskStatus.WAITING_FOR_RESOURCE,
            nextAttemptAtMillis = Long.MAX_VALUE, lastError = "The background model-call budget is temporarily unavailable",
            researchPlan = GlobalResearchPlan(id = "preserved", units = listOf(collected))))
        val budget = GlobalModelCallBudgetStore(context)
        budget.acquire(GlobalModelCallKind.RESEARCH_EVIDENCE, "fixture", 60000, repository.settings())
        val usage = budget.snapshot(repository.settings()).dispatchesInWindow
        coordinator.reconcile()
        val restored = repository.researchTasks().first { it.id == original.id }
        assertEquals(0L, restored.nextAttemptAtMillis)
        assertEquals(collected, restored.researchPlan.units.single())
        assertEquals(usage, budget.snapshot(repository.settings()).dispatchesInWindow)
    }

    @Test fun reviewReadyTopicIsClaimedBeforeFreshTopicsAndOnlyOneTopicRuns() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        store.update { it.copy(configured = true) }
        val repository = GlobalAgentRepository(context)
        ProactiveAttentionCoordinator(context).reconcile()
        val original = repository.researchTasks().last()
        val unit = GlobalResearchUnit(purpose = GlobalResearchUnitPurpose.CHANGE_MONITOR, question = "", sourceFocus = "",
            status = GlobalResearchUnitStatus.COMPLETED)
        repository.upsertResearchTask(original.copy(status = GlobalResearchTaskStatus.WAITING_FOR_RESOURCE,
            attemptCount = 10, researchPlan = GlobalResearchPlan(id = "progress", units = listOf(unit))))
        val claimed = repository.claimResearchTask(attentionOnly = true)!!
        try {
            assertEquals(original.id, claimed.id)
            assertNull(repository.claimResearchTask(attentionOnly = true))
        } finally { repository.releaseResearchPreparation(claimed) }
        val resumed = repository.claimResearchTask(attentionOnly = true)!!
        try {
            assertEquals(original.id, resumed.id)
            assertEquals(unit, resumed.researchPlan.units.single())
        } finally { repository.releaseResearchPreparation(resumed) }
    }

    @Test fun configurationAndFavoritesSurviveRecreation() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        assertEquals(31, store.preferences().topics.size)
        store.update { it.copy(configured = true, alertMode = AttentionAlertMode.SILENT, allowPairedModel = true,
            topics = it.topics.map { topic -> if (topic.id == "macro") topic.copy(title = "Edited scope", enabled = false) else topic },
            savedKeys = setOf("fixture")) }
        val restored = ProactiveAttentionStore(context).preferences()
        assertEquals(AttentionAlertMode.SILENT, restored.alertMode)
        assertEquals("Edited scope", restored.topics.first().title)
        assertFalse(restored.topics.first().enabled)
        assertTrue("fixture" in restored.savedKeys)
        assertTrue(restored.allowPairedModel)
        assertFalse(GlobalAgentRepository(context).settings().allowPairedAgentCognition)
    }

    @Test fun reconciliationIsIdempotentAndPauseResumeDoesNotMultiplyTasks() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        val coordinator = ProactiveAttentionCoordinator(context)
        val repository = GlobalAgentRepository(context)
        store.update { it.copy(configured = true) }
        repeat(3) { coordinator.reconcile() }
        assertEquals(31, repository.researchTasks().size)
        assertTrue(repository.researchTasks().all { it.depth == GlobalResearchDepth.CONTINUOUS_MONITOR })
        store.update { it.copy(enabled = false) }
        coordinator.reconcile()
        assertTrue(repository.researchTasks().all { it.status == GlobalResearchTaskStatus.PAUSED })
        store.update { it.copy(enabled = true) }
        coordinator.reconcile()
        assertEquals(31, repository.researchTasks().size)
        assertTrue(repository.researchTasks().all { it.status == GlobalResearchTaskStatus.QUEUED })
    }

    @Test fun previousFinancialConfigurationUpgradesWithoutRestartingActiveResearch() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        val repository = GlobalAgentRepository(context)
        store.update { it.copy(configured = true, alertMode = AttentionAlertMode.SILENT, allowPairedModel = true,
            topics = it.topics.take(15).map { topic -> if (topic.id == "rates") topic.copy(enabled = false) else topic },
            savedKeys = setOf("existing-finding")) }
        val macro = store.preferences().topics.first()
        val running = task("attention-research:macro").copy(topic = macro.title,
            question = ProactiveAttentionPolicy.researchQuestion(macro), status = GlobalResearchTaskStatus.RUNNING,
            sourceMessageId = 12345L, leaseExpiresAtMillis = Long.MAX_VALUE,
            preferredSources = ProactiveAttentionPolicy.preferredSources(macro.id))
        repository.upsertResearchTask(running)
        val persisted = repository.researchTasks().single()
        val coordinator = ProactiveAttentionCoordinator(context)
        repeat(3) { coordinator.reconcile() }
        val reopened = ProactiveAttentionStore(context).preferences()
        assertEquals(31, reopened.topics.size)
        assertEquals(16, reopened.topics.drop(15).count { it.enabled })
        assertFalse(reopened.topics.first { it.id == "rates" }.enabled)
        assertEquals(AttentionAlertMode.SILENT, reopened.alertMode)
        assertEquals(setOf("existing-finding"), reopened.savedKeys)
        assertTrue(reopened.allowPairedModel)
        assertEquals(30, repository.researchTasks().size)
        assertEquals(persisted, repository.researchTasks().first { it.id == running.id })
        val protein = repository.researchTasks().first { it.id == "attention-research:protein_life_sciences" }
        assertTrue(protein.question.contains("computational predictions and experimental validation"))
        assertTrue(protein.preferredSources.joinToString().contains("Original papers"))
    }

    @Test fun disabledTopicDoesNotKeepPendingNotificationsAndOtherTasksAreUntouched() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        val repository = GlobalAgentRepository(context)
        store.update { it.copy(configured = true, topics = it.topics.map { topic -> topic.copy(enabled = topic.id != "macro") }) }
        repository.upsertResearchTask(task("unrelated"))
        repository.appendProactiveMessage(message())
        ProactiveAttentionCoordinator(context).reconcile()
        assertEquals(GlobalResearchTaskStatus.QUEUED, repository.researchTasks().first { it.id == "unrelated" }.status)
        assertEquals(GlobalProactiveMessageStatus.DISMISSED, repository.proactiveMessages().single().status)
        assertFalse(repository.researchTasks().any { it.id == "attention-research:macro" })
    }

    @Test fun sourcesRetainOriginalDatesAndNotificationModeIsIndependent() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        store.update { it.copy(configured = true, alertMode = AttentionAlertMode.SILENT) }
        val task = task("attention-research:macro").copy(lastResultFingerprint = "test", updatedAtMillis = 5000,
            evidenceLedger = GlobalEvidenceLedger(sources = listOf(GlobalEvidenceSource(
                "https://example.org/synthetic", GlobalEvidenceSourceKind.OFFICIAL, 1.0, "Synthetic fixture",
                publishedAtMillis = 1000, retrievedAtMillis = 2000)), verified = true))
        store.saveEvidence(task, true)
        val source = ProactiveAttentionStore(context).evidence(ProactiveAttentionStore.eventId(task))!!
            .getJSONArray("sources").getJSONObject(0)
        assertEquals(1000L, source.getLong("published"))
        assertEquals(2000L, source.getLong("retrieved"))
        assertTrue(store.allows(message()))
        assertFalse(store.allowsNotification(message()))
        store.update { it.copy(alertMode = AttentionAlertMode.ALL) }
        assertTrue(store.allowsNotification(message()))
    }

    @Test fun viewedFindingRemainsSavedAfterStoreRecreation() = isolated { context ->
        val repository = GlobalAgentRepository(context)
        val finding = message().copy(status = GlobalProactiveMessageStatus.DELIVERED,
            deliveredConversationId = "test-destination", deliveredAtMillis = 1000)
        repository.appendProactiveMessage(finding)
        val item = GlobalProactiveInboxPolicy.project(repository.proactiveMessages(), emptyList()).single()
        ProactiveAttentionStore(context).update { it.copy(savedKeys = setOf(item.key)) }
        repository.markProactiveViewed(setOf(finding.id), 2000)
        val reopened = GlobalProactiveInboxPolicy.project(GlobalAgentRepository(context).proactiveMessages(), emptyList()).single()
        assertFalse(reopened.isNew)
        assertTrue(ProactiveAttentionPolicy.matches(reopened, AttentionFeedFilter.SAVED, ProactiveAttentionStore(context).preferences().savedKeys))
    }

    @Test fun settingsEntryShowsAllCategoriesAndReturnsFromDiscoveries() {
        val context = instrumentation.targetContext
        ActivityScenario.launch<ProactiveAttentionActivity>(Intent(context, ProactiveAttentionActivity::class.java)
            .putExtra("settings", true)).use { scenario ->
            await(scenario) { root -> views(root).filterIsInstance<CheckBox>().count() >= 31 }
            scenario.onActivity { activity ->
                val root = activity.window.decorView
                assertTrue(views(root).filterIsInstance<TextView>().any { it.text.toString() == activity.getString(R.string.attention_not_connected) })
                listOf("FINANCE", "TECHNOLOGY", "GALAXYSSI", "RESEARCH").forEach { group ->
                    assertTrue(views(root).any { it.tag == "attention-group:$group" })
                }
                assertEquals(31, activity.resources.getStringArray(R.array.attention_categories).size)
                assertEquals(31, activity.resources.getStringArray(R.array.attention_scopes).size)
                views(root).filterIsInstance<TextView>().first { it.text.toString() == activity.getString(R.string.attention_view) }
                    .parent.let { (it as View).parent as View }.performClick()
            }
            await(scenario) { root -> views(root).filterIsInstance<TextView>().any { it.text.toString() == context.getString(R.string.attention_saved) } }
            scenario.onActivity { it.onBackPressed() }
            await(scenario) { root -> views(root).filterIsInstance<CheckBox>().count() >= 31 }
            scenario.recreate()
            await(scenario) { root -> views(root).filterIsInstance<CheckBox>().count() >= 31 }
        }
    }

    @Test fun importantFindingUsesSystemHeadsUpChannel() {
        val context = instrumentation.targetContext
        val manager = context.getSystemService(NotificationManager::class.java)
        val id = 0x534103
        assumeTrue("System notifications are disabled", manager.areNotificationsEnabled())
        assumeTrue("Preserve an existing discovery notification", manager.activeNotifications.none { it.id == id })
        try {
            assertTrue(AndroidCognitionNotificationCenter.notify(context, GlobalAgentNotificationCandidate(
                title = "GalaxySSI \u6d4b\u8bd5\u63d0\u9192", content = "\u6d4b\u8bd5\u6570\u636e\uff0c\u4ec5\u9a8c\u8bc1\u91cd\u8981\u53d1\u73b0\u901a\u77e5\u3002",
                conversationId = "synthetic-attention-test", messageIds = emptySet(), attention = true, important = true)))
            SystemClock.sleep(800)
            val notification = manager.activeNotifications.single { it.id == id }.notification
            assertEquals(NotificationManager.IMPORTANCE_HIGH, manager.getNotificationChannel(notification.channelId).importance)
            assertNotNull(notification.contentIntent)
            assertNull(notification.fullScreenIntent)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(context.getExternalFilesDir(null), "attention-notification-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
            }
        } finally { manager.cancel(id) }
    }

    @Test fun homepageHidesEmptyDiscoveriesAndKeepsReadFindingsAccessible() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val bar = activity.findViewById<View>(R.id.agentInsightBar)
                val label = activity.findViewById<TextView>(R.id.agentInsightText)
                val items = GlobalProactiveInboxPolicy.project(listOf(message().copy(
                    status = GlobalProactiveMessageStatus.DELIVERED, deliveredAtMillis = 1000)), emptyList())
                try {
                    activity.renderGlobalInsightIndicator(emptyList())
                    assertEquals(View.GONE, bar.visibility)
                    activity.renderGlobalInsightIndicator(items)
                    assertEquals(View.VISIBLE, bar.visibility)
                    assertEquals(activity.getString(R.string.attention_unread_entry, 1), label.text.toString())
                    activity.renderGlobalInsightIndicator(items.map { it.copy(viewedAtMillis = 2000) })
                    assertEquals(View.VISIBLE, bar.visibility)
                    assertEquals(activity.getString(R.string.attention_discoveries), label.text.toString())
                    activity.renderGlobalInsightIndicator(emptyList())
                    assertEquals(View.GONE, bar.visibility)
                } finally { activity.refreshGlobalInsightIndicator() }
            }
        }
    }

    private fun await(scenario: ActivityScenario<ProactiveAttentionActivity>, predicate: (View) -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 15000
        while (SystemClock.uptimeMillis() < deadline) {
            var ready = false
            scenario.onActivity { ready = predicate(it.window.decorView) }
            if (ready) return
            SystemClock.sleep(100)
        }
        fail("Attention UI did not settle")
    }

    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()

    private fun task(id: String) = GlobalResearchTask(id = id, sourceEventId = "test", sourceConversationId = "test",
        topic = "Synthetic fixture", question = "No model execution", depth = GlobalResearchDepth.CONTINUOUS_MONITOR,
        preferredSources = emptyList())
    private fun message() = GlobalProactiveMessage(id = "test-finding", sourceEventId = "research:attention-research:macro:test",
        sourceConversationId = "test", target = GlobalProactiveTarget.NEW_CONVERSATION, title = "Synthetic fixture",
        content = "Test data, not financial news.", topic = "Macro", urgent = true)

    private fun isolated(block: (Context) -> Unit) {
        val context = IsolatedContext(instrumentation.targetContext)
        try { block(context) } finally {
            AgentEncryptedDatabase(context, GlobalAgentRepository.DATABASE_NAME).clear()
            context.cleanup()
        }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "attention-test-${UUID.randomUUID()}-"
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
