package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** One bounded archive probe per worker run; discovered feeds share the existing collection budget. */
internal object AttentionSourceDiscovery {
    suspend fun probe(context: Context, articles: AttentionArticleStore, topics: Set<String>) {
        if (BackgroundLearningLoadSampler.read(context).deferMillis > 0) return
        val current = ProactiveAttentionStore(context).preferences()
        if (!current.configured || !current.enabled) return
        val enabled = topics.intersect(current.topics.filter { it.enabled }.map { it.id }.toSet())
        if (enabled.isEmpty()) return
        repeat(4) { articles.backfillSources() }
        val now = System.currentTimeMillis()
        val candidate = articles.sourceProbe(enabled, now) ?: return
        val coroutine = currentCoroutineContext()
        try {
            val page = AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(candidate.url,
                maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES, timeoutMillis = 10_000,
                checkpoint = { coroutine.ensureActive() })
            try {
                val fetched = AgentWebIntelligenceFetched(page.finalUrl, page.contentType, page.body)
                AttentionArticlePolicy.extractStructured(fetched)
                val html = AgentWebTextDecoder.decode(page.body, page.contentType, page.finalUrl)
                val feeds = if (AttentionLearnedFeedPolicy.host(page.finalUrl) == candidate.host)
                    AttentionLearnedFeedPolicy.discover(html, page.finalUrl) else emptyList()
                val changed = articles.learnFeeds(page.finalUrl, feeds, candidate.topics, now)
                val store = ProactiveAttentionFeedStore(context)
                changed.forEach { store.sourceDiscovered(it, now) }
                if (changed.isNotEmpty()) ProactiveAttentionFeedScheduler.request(context)
                articles.sourceProbeDone(candidate.host, now + 7 * 86_400_000L, if (feeds.isEmpty()) "no_declared_feed" else "learned")
            } finally { page.body.fill(0) }
        } catch (cancelled: CancellationException) { throw cancelled
        } catch (failure: Exception) {
            articles.sourceProbeDone(candidate.host, now + 60 * 60_000L, failure.javaClass.simpleName)
        }
    }
}
