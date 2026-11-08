package com.galaxyssi.chat

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

internal object HealthCareResearchWork {
    private const val RECONCILE = "health-authorized-research"
    private const val DEADLINE = "health-research-deadline"
    internal const val TURN = "health_research_turn"

    fun changed(context: Context) {
        runCatching {
            if (!context.getDatabasePath(HealthCareStore.DEFAULT_DB).exists()) return
            // Reconciliation is replayable from durable rows; coalesce bursts without queueing one full scan per event.
            WorkManager.getInstance(context).enqueueUniqueWork(RECONCILE, ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<HealthCareResearchWorker>().setInitialDelay(750, TimeUnit.MILLISECONDS).build())
        }.onFailure { android.util.Log.w("HealthResearch", "Research reconciliation enqueue failed: ${it.javaClass.simpleName}") }
    }

    fun enqueue(context: Context, job: HealthCareResearchJob, online: Boolean) {
        val request = OneTimeWorkRequestBuilder<HealthCareResearchTurnWorker>().setInputData(workDataOf(TURN to job.turnId))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
        if (online) request.setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
        WorkManager.getInstance(context).enqueueUniqueWork("health-research-turn-${job.turnId}", ExistingWorkPolicy.KEEP, request.build())
    }

    fun reconcile(context: Context, stopped: () -> Boolean = { false }) {
        val app = AppLanguage.wrap(context)
        if (!app.getDatabasePath(HealthCareStore.DEFAULT_DB).exists()) return
        HealthCareEngine.evaluate(app, cancelled = stopped)
        var nextDue: Long? = null
        var cancellationsDelivered = true
        val now = System.currentTimeMillis()
        HealthCareStore(app).use { care ->
            var after = ""
            do {
                val page = care.researchAuthorizations(after)
                if (page.isEmpty()) break
                for (authorization in page) {
                    if (stopped()) return
                    if (!authorization.active) continue
                    val issue = care.concern(authorization.scope.concernId)
                    if (issue == null || !HealthCareResearchPolicy.eligible(issue) || !care.settings().enabled ||
                        care.settings().version != authorization.scope.settingsVersion || !HealthCareResearchRuntime.bindingCurrent(app, authorization)) {
                        care.revokeResearch(authorization.scope.concernId, authorization.id, now)
                        continue
                    }
                    val job = care.queueResearch(authorization.id, issue.id, now)
                    var previous = ""
                    do {
                        val pending = care.researchJobs(issue.id, previous, unfinishedOnly = true)
                        if (pending.isEmpty()) break
                        pending.filter { it.turnId != job.turnId || it.revision != issue.revision }.forEach {
                            care.updateResearchJob(it, HealthCareResearchState.SUPERSEDED, app.getString(R.string.health_care_changed))
                        }
                        previous = pending.last().turnId
                    } while (!stopped())
                    care.researchJob(job.turnId)?.takeUnless { it.terminal }?.let {
                        enqueue(app, it, authorization.scope.targetId != "local-llm")
                    }
                    issue.actions.filter { it.state == HealthCareActionState.CONFIRMED }.mapNotNull { it.dueFrom }
                        .filter { it > now }.minOrNull()?.let { nextDue = minOf(nextDue ?: Long.MAX_VALUE, it) }
                }
                after = page.last().scope.concernId
            } while (!stopped())
            cancellationsDelivered = cancelPending(app, care, stopped)
        }
        if (stopped()) return
        val manager = WorkManager.getInstance(app)
        val deadline = nextDue
        if (deadline == null) manager.cancelUniqueWork(DEADLINE)
        else manager.enqueueUniqueWork(DEADLINE, ExistingWorkPolicy.REPLACE, OneTimeWorkRequestBuilder<HealthCareResearchWorker>()
            .setInitialDelay(maxOf(1000, deadline - now), TimeUnit.MILLISECONDS).build())
        if (!cancellationsDelivered) throw HealthCareConflict()
    }

    private fun cancelPending(context: Context, care: HealthCareStore, stopped: () -> Boolean): Boolean {
        var delivered = true
        var after = ""
        while (!stopped()) {
            val jobs = care.pendingResearchCancellations(after)
            if (jobs.isEmpty()) break
            for (job in jobs) {
                val supervisor = AgentTaskRuntime.supervisor(context)
                supervisor.cancelWorkspace(job.turnId, "Health research authorization or evidence changed")
                AgentCloudDispatchRegistry.cancelTurn(job.conversationId, job.turnId)
                val saved = SharedPreferencesAgentSessionStore(context, "task:${job.turnId}").load()
                val result = saved?.lastActionResult
                AgentCloudDispatchRegistry.cancel(result)
                val metadata = result?.metadata.orEmpty()
                val source = metadata["source_message_id"]?.toLongOrNull() ?: 0L
                val contact = metadata["contact_id"].orEmpty()
                val remote = metadata["remote_task_id"].orEmpty()
                if (source > 0) AgentTerminalDeliveryStore.mark(context,
                    AgentPendingDelivery(source, job.conversationId, job.turnId, remote.ifBlank { job.turnId }, contact),
                    "Health research authorization or evidence changed")
                if (source > 0 && contact.isNotBlank() && remote.isNotBlank()) {
                    val sent = GalaxySSIMqttClient.publishAgentTaskCancel(remote, contact, source, job.conversationId, job.turnId,
                        topicOverride = AppStore.outgoingTopicForContact(context, contact))
                    // Keep the cancellation outbox until MQTT accepts it; never redispatch the research.
                    if (!sent) { delivered = false; continue }
                }
                care.acknowledgeResearchCancellation(job)
            }
            after = jobs.last().turnId
        }
        return delivered
    }

    fun allowProjection(context: Context, conversationId: String, turnId: String): Boolean {
        if (!context.getDatabasePath(HealthCareStore.DEFAULT_DB).exists()) return true
        return HealthCareStore(context).use { care ->
            val job = care.researchJob(turnId) ?: return@use true
            if (conversationId != job.conversationId || care.concern(job.concernId) == null) return@use false
            val authorization = care.researchAuthorization(job.concernId)
            if (authorization?.active != true || authorization.id != job.authorizationId ||
                job.state in setOf(HealthCareResearchState.CANCELLED, HealthCareResearchState.SUPERSEDED, HealthCareResearchState.FAILED)) return@use false
            if (!HealthCareResearchRuntime.bindingCurrent(context, authorization)) return@use false
            if (!job.terminal && HealthCareDiscussion.rejection(context, job.conversationId, job.turnId) != null) {
                care.updateResearchJob(job, HealthCareResearchState.SUPERSEDED, context.getString(R.string.health_care_changed))
                return@use false
            }
            true
        }
    }

    fun projected(context: Context, conversationId: String, turnId: String, state: AgentUiState) {
        if (!context.getDatabasePath(HealthCareStore.DEFAULT_DB).exists()) return
        HealthCareStore(context).use { care ->
            val job = care.researchJob(turnId)?.takeUnless { it.terminal } ?: return
            if (job.conversationId != conversationId) return
            val next = when (state.phase) {
                AgentPhase.COMPLETED -> HealthCareResearchState.COMPLETED
                AgentPhase.FAILED, AgentPhase.BLOCKED -> HealthCareResearchState.FAILED
                AgentPhase.CANCELLED -> HealthCareResearchState.CANCELLED
                else -> return
            }
            care.updateResearchJob(job, next, if (next == HealthCareResearchState.FAILED) state.lastActionResult?.message.orEmpty() else "")
        }
    }
}

class HealthCareResearchWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = try {
        HealthCareResearchWork.reconcile(applicationContext) { isStopped }; Result.success()
    } catch (_: HealthCareConflict) { Result.retry() }
    catch (_: android.database.sqlite.SQLiteDatabaseLockedException) { Result.retry() }
    catch (_: Exception) { Result.failure() }
}

class HealthCareResearchTurnWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val context = AppLanguage.wrap(applicationContext)
        val turn = inputData.getString(HealthCareResearchWork.TURN) ?: return Result.failure()
        val claim = AgentLongTaskRecoveryClaims.tryAcquire(turn) ?: return Result.retry()
        return try {
            val job = HealthCareStore(context).use { it.researchJob(turn) }?.takeUnless { it.terminal } ?: return Result.success()
            val supervisor = AgentTaskRuntime.supervisor(context)
            val workspace = supervisor.findWorkspace(turn)
            if (workspace != null) {
                if (!workspace.status.isTerminal && supervisor.activeWorkspaces().any { it.workspaceId == turn }) return Result.success()
                if (workspace.status.isTerminal) {
                    HealthCareStore(context).use { care ->
                        val latest = care.researchJob(turn)?.takeUnless { it.terminal } ?: return@use
                        care.updateResearchJob(latest, if (workspace.status == AgentWorkspaceStatus.COMPLETED && latest.state == HealthCareResearchState.DISPATCHED) HealthCareResearchState.COMPLETED
                            else HealthCareResearchState.FAILED, workspace.errorMessage)
                    }
                } else if (SharedPreferencesAgentSessionStore(context, "task:$turn").load() == null) {
                    supervisor.cancelWorkspace(turn, "Health research interrupted before its execution checkpoint")
                    HealthCareStore(context).use { care -> care.researchJob(turn)?.takeUnless { it.terminal }?.let {
                        care.updateResearchJob(it, HealthCareResearchState.FAILED, context.getString(R.string.health_research_interrupted))
                    } }
                } else {
                    AndroidAgentRecoveryWake.request(context)
                    AgentLongTaskRecoveryScheduler.enqueue(context, turn, "Resume authorized health research")
                }
                return Result.success()
            }
            val authorization = HealthCareStore(context).use { it.researchAuthorization(job.concernId) } ?: throw HealthCareConflict()
            check(authorization.id == job.authorizationId && HealthCareResearchRuntime.bindingCurrent(context, authorization)) {
                context.getString(R.string.health_care_changed)
            }
            if (SharedPreferencesAgentSafetySettingsStore(context).load().executionPaused) return Result.retry()
            setForeground(AgentRecoveryNotification.foregroundInfo(context, turn))
            val preview = HealthCareResearchRuntime.prepare(context, job, authorization)
            HealthCareResearchRuntime.launch(context, job, preview)
            Result.success()
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: android.database.sqlite.SQLiteDatabaseLockedException) { Result.retry() }
        catch (failure: Exception) {
            HealthCareStore(context).use { care -> care.researchJob(turn)?.takeUnless { it.terminal }?.let {
                care.updateResearchJob(it, HealthCareResearchState.FAILED, failure.message ?: context.getString(R.string.health_storage_error))
            } }
            Result.success()
        } finally { claim.close() }
    }
}
