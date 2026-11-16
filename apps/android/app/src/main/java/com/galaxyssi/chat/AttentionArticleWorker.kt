package com.galaxyssi.chat

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

private class ArticleBudgetYield : RuntimeException()

internal object AttentionArticleScheduler {
    fun request(context: Context, delay: Long = 0L) {
        val request = OneTimeWorkRequestBuilder<AttentionArticleWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInputData(workDataOf("timer" to (delay > 0)))
            .setInitialDelay(delay.coerceAtLeast(0L), TimeUnit.MILLISECONDS).build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            if (delay > 0) "attention-article-timer-v1" else "attention-article-now-v1",
            if (delay > 0) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
    }
}

/** Independent from private cognition, chat routing, and Desktop availability. */
class AttentionArticleWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = execution.withLock { withContext(Dispatchers.IO) {
        val context = applicationContext
        if (inputData.getBoolean("timer", false)) {
            AttentionArticleScheduler.request(context)
            return@withContext Result.success()
        }
        val preferences = ProactiveAttentionStore(context).preferences()
        if (!preferences.configured || !preferences.enabled) return@withContext Result.success()
        val now = System.currentTimeMillis()
        val profile = AttentionNewsBudget.profile(context, now)
        val delay = maxOf(AttentionNewsBudget.articleDelay(context, now, profile), AttentionNewsBudget.pressure(context))
        if (delay > 0L) {
            AttentionArticleScheduler.request(context, delay)
            return@withContext Result.success()
        }
        val store = AttentionArticleStore(context)
        val feed = ProactiveAttentionFeedStore(context)
        val topics = preferences.topics.filter { it.enabled }.map { it.id }.toSet()
        if (topics.isEmpty()) return@withContext Result.success()
        fun nextAt() = listOfNotNull(store.nextAt(topics),
            if (profile.charging || profile.recentlyRead) store.nextSourceProbe(topics) else null).minOrNull()
        if (!store.hasLegacyImport()) {
            val next = nextAt() ?: return@withContext Result.success()
            if (next > now) {
                AttentionArticleScheduler.request(context, next - now)
                return@withContext Result.success()
            }
        }
        // Persist the lease before processing in case the process dies mid-batch.
        AttentionNewsBudget.articleBoundary(context, now)
        var migrating = false
        repeat(if (profile.charging) 2 else 1) {
            currentCoroutineContext().ensureActive()
            if (AttentionNewsBudget.pressure(context) == 0L) migrating = store.importLegacy(feed, preferences.topics)
            else migrating = store.hasLegacyImport()
        }
        val coroutine = currentCoroutineContext()
        val fetcher = AgentBoundedWebIntelligenceFetcher(AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
            policy = AgentWebPolicy(maxTimeoutMillis = 20_000L)))
        var published = 0
        var attempted = 0
        val started = android.os.SystemClock.elapsedRealtime()
        val parallelism = if (profile.charging) 2 else 1
        val extraction = Mutex()
        fun canContinue() = AttentionNewsBudget.pressure(context) == 0L &&
            ProactiveAttentionStore(context).preferences().enabled &&
            android.os.SystemClock.elapsedRealtime() - started < profile.articleTime
        AttentionArticleTranslator(context).use { translator ->
            articleBatch@ while (attempted < profile.articleLimit && canContinue()) {
                coroutine.ensureActive()
                val jobs = (0 until minOf(parallelism, profile.articleLimit - attempted))
                    .mapNotNull { store.claim(topics, System.currentTimeMillis()) }
                if (jobs.isEmpty()) break
                attempted += jobs.size
                val progressBefore = jobs.associate { it.key to store.progressCount(it.key) }
                // Only downloads overlap. DOM extraction and the reused translator stay bounded.
                val prepared = coroutineScope { jobs.map { job -> async(Dispatchers.IO) {
                    try {
                        val article = if (job.state == "ready") null else store.extracted(job.key, System.currentTimeMillis()) ?: run {
                            val page = fetcher.fetch(job.url, 10 * 1024 * 1024L, 20_000L,
                                AgentDynamicArticleRequestPolicy.headers(job.url), AgentNativeToolCancellationToken.NONE,
                                {
                                    coroutine.ensureActive()
                                    if (AttentionNewsBudget.cpuDelay() > 0L) throw ArticleBudgetYield()
                                })
                            try { extraction.withLock { AttentionArticlePolicy.extractStructured(page).also {
                                store.checkpoint(job.key, it, System.currentTimeMillis())
                            } } } finally { page.body.fill(0) }
                        }
                        kotlin.Result.success(article)
                    } catch (cancelled: CancellationException) { throw cancelled
                    } catch (failure: Exception) { kotlin.Result.failure<AttentionArticleSource?>(failure) }
                } }.awaitAll() }
                for ((index, job) in jobs.withIndex()) {
                    if (!canContinue()) {
                        jobs.drop(index).forEach(store::releaseBudgetClaim)
                        break@articleBatch
                    }
                    try {
                        val article = prepared[index].getOrThrow()
                        if (article != null) {
                            val title = if (job.knowledge) article.article.title else job.title.ifBlank { article.article.title }
                            val translated = translator.translate(title, article, store.translationProgress(job.key)) {
                                if (!canContinue()) throw ArticleBudgetYield()
                            }
                            coroutine.ensureActive()
                            store.ready(job.key, translated)
                        }
                        val current = ProactiveAttentionStore(context).preferences()
                        val scoped = store.scopedMetadata(job.key, current.topics.filter { it.enabled }.map { it.id }.toSet())
                        if (job.state != "published" && current.configured && current.enabled && scoped != null) {
                            if (feed.publishArticle(scoped)) published++
                            store.published(job.key)
                        }
                    } catch (_: ArticleBudgetYield) {
                        jobs.drop(index).forEach(store::releaseBudgetClaim)
                        break@articleBatch
                    } catch (timeout: TimeoutCancellationException) {
                        coroutine.ensureActive()
                        store.failed(job, "article_translation_timeout", System.currentTimeMillis())
                        if (store.progressCount(job.key) > progressBefore.getValue(job.key))
                            store.continueTranslation(job.key, System.currentTimeMillis())
                    } catch (cancelled: CancellationException) { throw cancelled
                    } catch (failure: Exception) {
                        val reason = if (failure is AgentWebMediaException) failure.code else
                            failure.message?.takeIf { it.startsWith("article_") } ?: failure.javaClass.simpleName
                        store.failed(job, reason, System.currentTimeMillis())
                        android.util.Log.w("GalaxySSIAttention", "article_deferred id=${job.key.take(12)} reason=$reason")
                    }
                }
            }
        }
        coroutine.ensureActive()
        ProactiveAttentionFeedDelivery.published(context, published)
        if (published == 0 && (attempted > 0 || migrating)) GlobalProactiveDeliveryBus.signalReady()
        if ((profile.charging || profile.recentlyRead) && AttentionNewsBudget.pressure(context) == 0L &&
            android.os.SystemClock.elapsedRealtime() - started < profile.articleTime)
            AttentionSourceDiscovery.probe(context, store, topics)
        val next = nextAt()
        val finished = System.currentTimeMillis()
        AttentionNewsBudget.articleBoundary(context, finished, published > 0)
        if (migrating || next != null) AttentionArticleScheduler.request(context,
            maxOf((next ?: finished) - finished, profile.articleSpacing(published > 0), AttentionNewsBudget.pressure(context)))
        android.util.Log.i("GalaxySSIAttention", "article_batch attempted=$attempted published=$published migrating=$migrating " +
            "elapsed_ms=${android.os.SystemClock.elapsedRealtime() - started}")
        Result.success()
    } }
    companion object { private val execution = Mutex() }
}
