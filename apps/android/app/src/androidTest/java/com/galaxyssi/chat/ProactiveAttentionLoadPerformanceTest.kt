package com.galaxyssi.chat

import android.os.SystemClock
import android.os.Bundle
import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.recyclerview.widget.RecyclerView
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in, read-only timings. No news bodies or account data are logged. */
@RunWith(AndroidJUnit4::class)
class ProactiveAttentionLoadPerformanceTest {
    private fun report(value: String) {
        Log.i("AttentionLoadProfile", value)
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply { putString("stream", "$value\n") })
    }

    @Test fun measureIndexedHomeCounts() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_load_profile") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        repeat(3) { pass ->
            val start = SystemClock.elapsedRealtime()
            val counts = GlobalAgentRepository(context).proactiveInboxCounts()
            report("home_count_pass=$pass total=${counts.total} unread=${counts.unread} ms=${SystemClock.elapsedRealtime() - start}")
        }
    }

    @Test fun measureDiscoveryFirstContent() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_load_profile") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val start = SystemClock.elapsedRealtime()
        ActivityScenario.launch<ProactiveAttentionActivity>(Intent(context, ProactiveAttentionActivity::class.java)).use { scenario ->
            var rows = 0
            while (rows == 0 && SystemClock.elapsedRealtime() - start < 30_000) {
                scenario.onActivity { activity ->
                    rows = activity.window.decorView.findViewWithTag<RecyclerView>("attention-reader-list")?.adapter?.itemCount ?: 0
                }
                if (rows == 0) SystemClock.sleep(20)
            }
            report("ui_first_content_ms=${SystemClock.elapsedRealtime() - start} rows=$rows")
            org.junit.Assert.assertTrue("No discovery content rendered", rows > 0)
        }
    }

    @Test fun measureIndexedDiscoveryLoad() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_load_profile") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        repeat(3) { pass ->
            val start = SystemClock.elapsedRealtime()
            val preferences = ProactiveAttentionStore(context).preferences()
            val state = ProactiveAttentionReaderStateStore(context).read()
            val items = GlobalAgentRepository(context).proactiveInboxPreview(state, preferences.savedKeys)
            ProactiveAttentionTitleStore(context).decorate(items)
            report("indexed_pass=$pass rows=${items.size} first_page_ms=${SystemClock.elapsedRealtime() - start}")
        }
    }

    @Test fun measureExistingDiscoveryLoad() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_load_profile") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        fun <T> timed(name: String, block: () -> T): T {
            val start = SystemClock.elapsedRealtime()
            return block().also { report("$name ms=${SystemClock.elapsedRealtime() - start}") }
        }
        repeat(2) { pass ->
            val start = SystemClock.elapsedRealtime()
            val store = ProactiveAttentionStore(context)
            val preferences = timed("preferences") { store.preferences() }
            val repository = GlobalAgentRepository(context)
            val messages = timed("messages") { repository.proactiveMessages() }
            val feedback = timed("feedback") { repository.feedback() }
            val inbox = timed("projection") { GlobalProactiveInboxPolicy.project(messages, feedback) }
            timed("titles") { ProactiveAttentionTitleStore(context).decorate(inbox) }
            timed("reader_state") { ProactiveAttentionReaderStateStore(context).read() }
            timed("research") { repository.researchTasks().filter(ProactiveAttentionPolicy::isAttention) }
            timed("feed_status") {
                val feed = ProactiveAttentionFeedStore(context)
                preferences.topics.filter { it.enabled }.map { feed.topicState(it.id) }
            }
            report("pass=$pass messages=${messages.size} inbox=${inbox.size} total_ms=${SystemClock.elapsedRealtime() - start}")
        }
    }
}
