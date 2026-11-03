package com.galaxyssi.chat

import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import com.google.mlkit.nl.translate.TranslateLanguage
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Opt-in public publisher checks. No user messages, credentials, preferences or read state are changed. */
class AttentionSourceLiveDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun report(text: String) = instrumentation.sendStatus(0, Bundle().apply { putString("stream", "$text\n") })

    @Test fun specialistFeedsFetchParseAndRoundTripTheirFullUnicodeCache() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("attention_source_live") == "true")
        val urls = listOf("https://www.langchain.com/blog/rss.xml", "https://openai.com/news/rss.xml",
            "https://journals.plos.org/plosbiology/feed/atom", "https://elifesciences.org/rss/recent.xml",
            "https://www.nature.com/nbt.rss", "https://news.mit.edu/rss/topic/biology-and-genetics")
        val db = AgentEncryptedDatabase(context, "attention_feed_v1")
        val key = "diagnostic-public-feed-${java.util.UUID.randomUUID()}"
        var successes = 0
        try {
            for (url in urls) {
                val result = runCatching {
                    val xml = AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url,
                        maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES, timeoutMillis = 15_000).body.toString(Charsets.UTF_8)
                    val articles = ProactiveAttentionFeedPolicy.parse(xml, "fixture", System.currentTimeMillis(), 30)
                    check(articles.isNotEmpty()) { "No dated recent items" }
                    val json = org.json.JSONObject().put("xml", xml).toString()
                    db.writeString(key, json)
                    assertEquals(json, db.readString(key, ""))
                    articles.size
                }
                report("specialist_feed url=$url items=${result.getOrNull()} error=${result.exceptionOrNull()?.message}")
                if (result.isSuccess) successes++
            }
            assertEquals("All new specialist feed paths must work on the phone", urls.size, successes)
        } finally { db.remove(key) }
    }

    @Test fun selectedArticleUsesTheProductionStructuredTranslationPipeline() = runBlocking {
        val url = InstrumentationRegistry.getArguments().getString("attention_source_article")
        assumeTrue(!url.isNullOrBlank())
        val start = SystemClock.elapsedRealtime()
        val page = AgentBoundedWebIntelligenceFetcher(AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
            policy = AgentWebPolicy(maxTimeoutMillis = 20_000))).fetch(url!!, 10 * 1024 * 1024, 20_000,
            AgentDynamicArticleRequestPolicy.headers(url), AgentNativeToolCancellationToken.NONE, {})
        val source = try { AttentionArticlePolicy.extractStructured(page) } finally { page.body.fill(0) }
        val downloaded = SystemClock.elapsedRealtime()
        if (InstrumentationRegistry.getArguments().getString("attention_source_diagnose") == "true") {
            val client = Translation.getClient(TranslatorOptions.Builder().setSourceLanguage(TranslateLanguage.ENGLISH)
                .setTargetLanguage(TranslateLanguage.CHINESE).build())
            try {
                var failures = 0
                for ((index, block) in source.document.blocks.withIndex()) {
                    if (block.text.isBlank() || block.kind == "code" || !block.text.any(Char::isLetter)) continue
                    val result = runCatching { AttentionTranslationRecovery.convert(block.text) { part ->
                        val translated = client.translate(part).await()
                        val failure = runCatching { AttentionArticlePolicy.validateTranslation(part, translated) }.exceptionOrNull()
                        if (failure != null) report("article_block=$index kind=${block.kind} reason=${failure.message} source=$part translated=$translated")
                        translated
                    } }
                    if (result.isFailure && ++failures >= 5) break
                }
            } finally { client.close() }
        }
        AttentionArticleTranslator(context).use { translator ->
            val article = translator.translate(source.article.title, source)
            assertTrue(AttentionArticlePolicy.chinese(article.body))
            assertEquals(source.document.blocks.size, article.document!!.blocks.size)
            report("specialist_article url=$url fetch_ms=${downloaded-start} translate_ms=${SystemClock.elapsedRealtime()-downloaded} " +
                "source_chars=${source.article.content.length} chinese_chars=${article.body.length} blocks=${article.document.blocks.size} provider=${article.provider}")
        }
    }
}
