package com.galaxyssi.chat

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

internal object ProactiveAttentionTitleScheduler {
    internal const val TIMER = "attention_title_timer"
    internal fun buildRequest(delay: Long) = OneTimeWorkRequestBuilder<ProactiveAttentionTitleWorker>()
        .setInputData(workDataOf(TIMER to (delay > 0)))
        .setInitialDelay(delay.coerceAtLeast(0L), TimeUnit.MILLISECONDS).build()

    fun request(context: Context, delay: Long = 0L) {
        if (AppLanguage.resolved(context) != AppLanguage.ZH_CN) return
        val request = buildRequest(delay)
        // A replaceable timer only wakes the KEEP-protected inference job; it never calls a model.
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            if (delay > 0) "attention-title-timer-v1" else "attention-title-now-v1",
            if (delay > 0) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
    }
}

class ProactiveAttentionTitleWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        if (inputData.getBoolean(ProactiveAttentionTitleScheduler.TIMER, false)) {
            ProactiveAttentionTitleScheduler.request(applicationContext)
            return Result.success()
        }
        return execution.withLock { withContext(Dispatchers.IO) {
        val context = applicationContext
        val preferences = ProactiveAttentionStore(context).preferences()
        val repository = GlobalAgentRepository(context)
        val store = ProactiveAttentionTitleStore(context)
        if (!ProactiveAttentionTranslationPolicy.enabled(preferences,
                if (AppLanguage.resolved(context) == AppLanguage.ZH_CN) "zh" else "en")) {
            store.workerState(AttentionTitleStatus.DISABLED)
            return@withContext Result.success()
        }
        val load = BackgroundLearningLoadSampler.read(context)
        if (load.deferMillis > 0) {
            ProactiveAttentionTitleScheduler.request(context, load.deferMillis)
            android.util.Log.i("GalaxySSIAttention", "title_translation_deferred reason=device_load")
            return@withContext Result.success()
        }
        val paired = ProactiveAttentionPairedTitles(context)
        val pairedDelay = paired.pendingDelay(System.currentTimeMillis())
        // Only public feed headlines enter this lightweight path, never personal inbox contents.
        val pending = repository.proactiveMessages().asSequence().filter {
            it.id.startsWith("attention-feed:") && it.status == GlobalProactiveMessageStatus.DELIVERED
        }.sortedByDescending { it.deliveredAtMillis }.map { it.title }.distinct().filter {
            ProactiveAttentionTitlePolicy.needsTranslation(it) && store.translation(it).isBlank()
        }.toList()
        if (pending.isEmpty()) return@withContext Result.success()
        val now = System.currentTimeMillis()
        val priority = store.priorityKeys(now)
        val batch = pending.filter { store.nextAt(it) <= now }
            .sortedBy { ProactiveAttentionTitlePolicy.key(it) !in priority }.take(ProactiveAttentionTitlePolicy.BATCH_SIZE)
        if (batch.isEmpty()) {
            ProactiveAttentionTitleScheduler.request(context, (pending.minOf(store::nextAt) - now).coerceAtLeast(30_000L))
            return@withContext Result.success()
        }
        val local = AttentionLocalTitleTranslation(::AttentionMlKitTranslator, store::translation,
            { title, translated -> store.save(title, translated, AttentionMlKitTranslator.PROVIDER) },
            { AttentionMlKitTranslator.requestDownload(context) }).translate(batch.associateBy(ProactiveAttentionTitlePolicy::key))
        android.util.Log.i("GalaxySSIAttention", "title_translation_local requested=${batch.size} saved=${local.translated} reason=${local.reason}")
        if (local.translated > 0) GlobalProactiveDeliveryBus.signalReady()
        if (local.remaining.isEmpty()) {
            if (pending.any { store.translation(it).isBlank() }) ProactiveAttentionTitleScheduler.request(context, load.spacingMillis)
            return@withContext Result.success()
        }
        val titles = local.remaining
        val fallbackBatch = titles.values.toList()
        val resources = GlobalAgentResourceResolver(context)
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val online = connectivity?.getNetworkCapabilities(connectivity.activeNetwork)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        val resource = ProactiveAttentionTranslationPolicy.orderRoutes(
            resources.route("Translate public news headlines into Chinese", allowPaired = online, allowCloud = online),
            { resources.cloudContact(it) != null }, store.lastFailedResource(now)).firstOrNull()
        if (resource == null) {
            store.workerState(AttentionTitleStatus.WAITING_MODEL)
            android.util.Log.i("GalaxySSIAttention", "title_translation_wait reason=no_available_model pending=${pending.size}")
            ProactiveAttentionTitleScheduler.request(context, 5 * 60_000L)
            return@withContext Result.success()
        }
        val cloud = resources.cloudContact(resource)
        val pairedContact = if (resource != "local-llm" && cloud == null) resources.resolvePairedContact(resource) else null
        if (resource != "local-llm" && cloud == null && pairedContact == null) {
            store.workerState(AttentionTitleStatus.WAITING_MODEL)
            ProactiveAttentionTitleScheduler.request(context, 5 * 60_000L)
            return@withContext Result.success()
        }
        if (pairedContact != null && pairedDelay > 0L) {
            store.workerState(AttentionTitleStatus.PENDING)
            ProactiveAttentionTitleScheduler.request(context, pairedDelay)
            return@withContext Result.success()
        }
        val prompt = ProactiveAttentionTitlePolicy.prompt(titles, store.feedback(titles))
        val owner = "attention-titles:" + UUID.randomUUID()
        val budget = GlobalModelCallBudgetStore(context)
        val lease = if (pairedContact != null) AttentionTitleRequest.LEASE else 5 * 60_000L
        val permit = budget.acquire(GlobalModelCallKind.COGNITION, owner, lease,
            repository.settings().copy(dailyBackgroundModelCallBudget = 0), resource,
            GlobalModelUsageEstimator.estimateTokens(ProactiveAttentionTitlePolicy.SYSTEM, prompt))
        if (!permit.granted) {
            store.workerState(AttentionTitleStatus.WAITING_CAPACITY)
            ProactiveAttentionTitleScheduler.request(context, (permit.nextEligibleAtMillis - now).coerceAtLeast(60_000L))
            return@withContext Result.success()
        }
        // Persist the retry lease before network/inference work, including process-death recovery.
        store.beginAttempt(fallbackBatch, now, lease)
        val started = android.os.SystemClock.elapsedRealtime()
        android.util.Log.i("GalaxySSIAttention", "title_translation_start requested=${titles.size} route=" +
            when { cloud != null -> "cloud"; pairedContact != null -> "paired"; else -> "local" })
        try {
            currentCoroutineContext().ensureActive()
            if (pairedContact != null) {
                if (paired.dispatch(pairedContact, owner, titles, now)) {
                    ProactiveAttentionTitleScheduler.request(context, lease)
                } else {
                    budget.release(GlobalModelCallKind.COGNITION, owner)
                    store.failed(fallbackBatch, "dispatch_unavailable")
                    store.workerState(AttentionTitleStatus.RETRYING, resource)
                    ProactiveAttentionTitleScheduler.request(context, 30_000L)
                }
                return@withContext Result.success()
            }
            val response = if (cloud != null) CloudModelClient.sendStructuredWithUsage(context, cloud,
                ProactiveAttentionTitlePolicy.SYSTEM, prompt) else {
                val local = LocalModelCooperativeRuntime.generate(context = context,
                    systemPrompt = ProactiveAttentionTitlePolicy.SYSTEM, userPrompt = prompt,
                    workClass = LocalModelWorkClass.BACKGROUND,
                    executionProfile = AgentExecutionProfile.forGoal("Translate news headlines"))
                CloudModelResponse(local.text,
                    GlobalModelUsageEstimator.estimateTokens(ProactiveAttentionTitlePolicy.SYSTEM, prompt),
                    GlobalModelUsageEstimator.estimateTokens(local.text), 0L)
            }
            budget.complete(GlobalModelCallKind.COGNITION, owner, response.inputTokens,
                response.outputTokens, response.costMicros, response.text)
            currentCoroutineContext().ensureActive()
            val saved = store.accept(response.text, titles)
            store.workerState(if (saved == titles.size) AttentionTitleStatus.PENDING else AttentionTitleStatus.RETRYING,
                if (saved == titles.size) "" else resource)
            GlobalProactiveDeliveryBus.signalReady()
            android.util.Log.i("GalaxySSIAttention", "title_translation requested=${titles.size} saved=$saved elapsed_ms=" +
                (android.os.SystemClock.elapsedRealtime() - started))
        } catch (failure: Exception) {
            budget.release(GlobalModelCallKind.COGNITION, owner)
            if (failure is java.util.concurrent.CancellationException) {
                store.failed(fallbackBatch, "request_interrupted")
                store.workerState(AttentionTitleStatus.PENDING)
                throw failure
            }
            store.failed(fallbackBatch, "request_${failure.javaClass.simpleName}")
            store.workerState(AttentionTitleStatus.RETRYING, resource)
            android.util.Log.w("GalaxySSIAttention", "title_translation_retry type=${failure.javaClass.simpleName}")
        }
        val remaining = pending.filter { store.translation(it).isBlank() }
        if (remaining.isNotEmpty()) ProactiveAttentionTitleScheduler.request(context,
            (remaining.minOf(store::nextAt) - System.currentTimeMillis()).coerceAtLeast(30_000L))
        Result.success()
    } } }

    companion object { private val execution = Mutex() }
}
