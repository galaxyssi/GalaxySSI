package com.galaxyssi.chat

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

internal object ProactiveAttentionTitleScheduler {
    fun request(context: Context, delay: Long = 0L) {
        if (context.resources.configuration.locales[0].language != "zh") return
        val request = OneTimeWorkRequestBuilder<ProactiveAttentionTitleWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInitialDelay(delay.coerceAtLeast(0L), TimeUnit.MILLISECONDS).build()
        // Separate the timer from the active job so a completed batch can schedule the next one.
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            if (delay > 0) "attention-title-timer-v1" else "attention-title-now-v1",
            if (delay > 0) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
    }
}

class ProactiveAttentionTitleWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = execution.withLock { withContext(Dispatchers.IO) {
        val context = applicationContext
        val preferences = ProactiveAttentionStore(context).preferences()
        val repository = GlobalAgentRepository(context)
        val settings = repository.settings()
        if (!preferences.configured || !preferences.enabled || !settings.enabled ||
            context.resources.configuration.locales[0].language != "zh") return@withContext Result.success()
        val paired = ProactiveAttentionPairedTitles(context)
        val pairedDelay = paired.pendingDelay(System.currentTimeMillis())
        if (pairedDelay > 0L) {
            ProactiveAttentionTitleScheduler.request(context, pairedDelay)
            return@withContext Result.success()
        }
        val store = ProactiveAttentionTitleStore(context)
        // Only public feed headlines enter this lightweight path, never personal inbox contents.
        val pending = repository.proactiveMessages().asSequence().filter {
            it.id.startsWith("attention-feed:") && it.status == GlobalProactiveMessageStatus.DELIVERED
        }.sortedByDescending { it.deliveredAtMillis }.map { it.title }.distinct().filter {
            ProactiveAttentionTitlePolicy.needsTranslation(it) && store.translation(it).isBlank()
        }.toList()
        if (pending.isEmpty()) return@withContext Result.success()
        val now = System.currentTimeMillis()
        val batch = pending.filter { store.nextAt(it) <= now }.take(ProactiveAttentionTitlePolicy.BATCH_SIZE)
        if (batch.isEmpty()) {
            ProactiveAttentionTitleScheduler.request(context, (pending.minOf(store::nextAt) - now).coerceAtLeast(30_000L))
            return@withContext Result.success()
        }
        val resources = GlobalAgentResourceResolver(context)
        val resource = resources.route("Translate public news headlines into Chinese", preferences.allowPairedModel,
            preferences.allowCloudModel).firstOrNull() ?: return@withContext Result.success()
        val cloud = resources.cloudContact(resource)
        val pairedContact = if (resource != "local-llm" && cloud == null) resources.resolvePairedContact(resource) else null
        if (resource != "local-llm" && cloud == null && pairedContact == null) return@withContext Result.success()
        val titles = batch.associateBy(ProactiveAttentionTitlePolicy::key)
        val prompt = ProactiveAttentionTitlePolicy.prompt(titles)
        val owner = "attention-titles:" + UUID.randomUUID()
        val budget = GlobalModelCallBudgetStore(context)
        val lease = if (pairedContact != null) AttentionTitleRequest.LEASE else 5 * 60_000L
        val permit = budget.acquire(GlobalModelCallKind.COGNITION, owner, lease,
            settings.copy(dailyBackgroundModelCallBudget = 0), resource,
            GlobalModelUsageEstimator.estimateTokens(ProactiveAttentionTitlePolicy.SYSTEM, prompt))
        if (!permit.granted) {
            ProactiveAttentionTitleScheduler.request(context, (permit.nextEligibleAtMillis - now).coerceAtLeast(60_000L))
            return@withContext Result.success()
        }
        // Persist the retry lease before network/inference work, including process-death recovery.
        store.defer(batch, now)
        try {
            currentCoroutineContext().ensureActive()
            if (pairedContact != null) {
                if (paired.dispatch(pairedContact, owner, titles, now)) {
                    ProactiveAttentionTitleScheduler.request(context, lease)
                } else {
                    budget.release(GlobalModelCallKind.COGNITION, owner)
                    ProactiveAttentionTitleScheduler.request(context, 5 * 60_000L)
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
            val translated = ProactiveAttentionTitlePolicy.parse(response.text, titles)
            translated.forEach { (id, title) -> store.save(titles.getValue(id), title) }
            if (translated.isNotEmpty()) GlobalProactiveDeliveryBus.signalReady()
            android.util.Log.i("GalaxySSIAttention", "title_translation requested=${batch.size} saved=${translated.size}")
        } catch (failure: Exception) {
            budget.release(GlobalModelCallKind.COGNITION, owner)
            if (failure is java.util.concurrent.CancellationException) throw failure
            android.util.Log.w("GalaxySSIAttention", "title_translation_retry type=${failure.javaClass.simpleName}")
        }
        val remaining = pending.filter { store.translation(it).isBlank() }
        if (remaining.isNotEmpty()) ProactiveAttentionTitleScheduler.request(context,
            (remaining.minOf(store::nextAt) - System.currentTimeMillis()).coerceAtLeast(30_000L))
        Result.success()
    } }

    companion object { private val execution = Mutex() }
}
