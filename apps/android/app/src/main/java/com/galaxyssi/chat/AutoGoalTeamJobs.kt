package com.galaxyssi.chat

import android.content.Context
import androidx.work.*
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.json.JSONObject

internal object AutoGoalTeamJobs {
    private val lock = Any()
    private val live = ConcurrentHashMap<String, AgentNativeToolCancellationSource>()
    private fun db(ctx: Context) = AgentEncryptedDatabase(ctx, "galaxyssi_conversation_teams_v1")
    private fun read(ctx: Context, chat: String) = db(ctx).readString(chat, "")
        .takeIf(String::isNotEmpty)?.let(::JSONObject)
    private fun active(j: JSONObject?) = j?.optString("state") in setOf("queued", "running")
    private fun name(id: String) = "chat-text-team:$id"
    private fun valid(ctx: Context, chat: String): Boolean {
        val current = AgentTranscriptStore(ctx).conversation(chat)
        return current != null && !current.trackingPaused && ConversationGoalRunner.eligible(ctx, current)
    }

    fun start(context: Context, chat: AgentConversation, objective: String, route: GoalRoute,
        sourceTurn: String? = null, pinnedCloud: Boolean = false): Boolean = synchronized(lock) {
        val ctx = context.applicationContext
        require(objective.isNotBlank() && objective.length <= 4000)
        check(valid(ctx, chat.id))
        if (pinnedCloud) check(sourceTurn != null && AutoGoalTeamCommand.allowsModelReview(objective) &&
            !AgentTaskRequirementAnalyzer.analyze(objective).localOnly && PinnedCloudTeamAdmission.current(ctx, chat.id, route))
        val transcript = AgentTranscriptStore(ctx)
        if (sourceTurn != null) {
            val original = transcript.firstEntryForTurn(chat.id, sourceTurn)
            check(original?.role == AgentTranscriptRole.USER && original.text == objective) {
                "Original request is no longer available."
            }
        }
        val prior = read(ctx, chat.id)
        if (active(prior)) return false
        if (prior?.optString("state") == "finished") publish(ctx, chat.id, prior)
        val id = UUID.randomUUID().toString()
        val turn = sourceTurn ?: id
        val job = JSONObject().put("id", id).put("turn", turn).put("state", "queued").put("objective", objective).put("route", route.json())
            .put("pinned_cloud", pinnedCloud)
        val request = OneTimeWorkRequestBuilder<AutoGoalTeamWorker>().setInputData(workDataOf("chat" to chat.id, "id" to id))
            .setConstraints(Constraints.Builder().apply {
                if (route.target != "local-llm") setRequiredNetworkType(NetworkType.CONNECTED)
            }.build()).build()
        WorkManager.getInstance(ctx).enqueueUniqueWork(name(id), ExistingWorkPolicy.KEEP, request).result.get(15, TimeUnit.SECONDS)
        db(ctx).writeString(chat.id, job.toString())
        if (sourceTurn == null) transcript.append(AgentTranscriptRole.USER, objective, "$id:team-request", conversationId = chat.id, turnId = turn)
        transcript.append(AgentTranscriptRole.ASSISTANT, ctx.getString(R.string.auto_team_job_queued, route.label),
            "$id:team-start", conversationId = chat.id, turnId = turn)
        true
    }

    fun stop(context: Context, chat: String): Boolean = synchronized(lock) {
        val job = read(context, chat) ?: return false
        if (!active(job)) return false
        val id = job.getString("id")
        db(context).remove(chat)
        live[id]?.cancel()
        WorkManager.getInstance(context).cancelUniqueWork(name(id))
        if (valid(context, chat)) AgentTranscriptStore(context).append(AgentTranscriptRole.ASSISTANT,
            context.getString(R.string.auto_team_job_stopped), "$id:team-stop", conversationId = chat, turnId = job.optString("turn", id))
        true
    }

    fun remove(context: Context, chat: String) = synchronized(lock) {
        val job = read(context, chat) ?: return@synchronized
        db(context).remove(chat)
        live[job.getString("id")]?.cancel()
        WorkManager.getInstance(context).cancelUniqueWork(name(job.getString("id")))
        Unit
    }

    private fun publish(ctx: Context, chat: String, job: JSONObject) {
        val id = job.getString("id")
        if (valid(ctx, chat)) AgentTranscriptStore(ctx).append(AgentTranscriptRole.ASSISTANT,
            job.getString("answer"), "$id:team-result", conversationId = chat, turnId = job.optString("turn", id))
        db(ctx).remove(chat)
    }

    private fun finish(ctx: Context, chat: String, job: JSONObject, answer: String) {
        job.put("state", "finished").put("answer", answer)
        db(ctx).writeString(chat, job.toString())
        publish(ctx, chat, job)
    }

    fun execute(ctx: Context, chat: String, id: String, stopped: () -> Boolean,
        cancel: AgentNativeToolCancellationSource) {
        fun own() = read(ctx, chat)?.takeIf { it.optString("id") == id }
        val job = synchronized(lock) {
            val current = own() ?: return
            if (!valid(ctx, chat)) { db(ctx).remove(chat); return }
            when (current.getString("state")) {
                "finished" -> { publish(ctx, chat, current); return }
                "running" -> { finish(ctx, chat, current, ctx.getString(R.string.auto_team_job_interrupted)); return }
                else -> check(current.getString("state") == "queued")
            }
            current.put("state", "running")
            db(ctx).writeString(chat, current.toString())
            live[id] = cancel
            current
        }
        val routeJson = job.getJSONObject("route")
        val route = GoalRoute(routeJson.getString("target"), routeJson.getString("model"), routeJson.getString("endpoint"),
            routeJson.optString("host"))
        val calls = AtomicInteger()
        val roles = AtomicInteger()
        val answer = try {
            runBlocking {
                val labels = TeamResultLabels(ctx.getString(R.string.auto_team_correction), ctx.getString(R.string.auto_team_objections),
                    ctx.getString(R.string.auto_team_passing), ctx.getString(R.string.auto_team_none), ctx.getString(R.string.auto_team_limitation))
                runAutoGoalTeam(job.getString("objective"), labels, { instructions, payload -> coroutineScope {
                    val call = AgentNativeToolCancellationSource()
                    val registration = cancel.token.invokeOnCancellation { call.cancel() }
                    // Provider HTTP calls need an explicit cancellation signal on sibling failure or timeout.
                    val guard = launch(start = CoroutineStart.UNDISPATCHED) {
                        try { awaitCancellation() } finally { call.cancel() }
                    }
                    try { withContext(Dispatchers.IO) {
                        synchronized(lock) { check(!stopped() && own()?.optString("state") == "running" &&
                            valid(ctx, chat)) }
                        if (job.optBoolean("pinned_cloud")) check(PinnedCloudTeamAdmission.current(ctx, chat, route))
                        val round = calls.incrementAndGet()
                        check(round <= 12)
                        when (JSONObject(payload).getString("stage")) {
                            "role", "audit" -> roles.incrementAndGet()
                        }
                        ConversationGoalRunner.text(ctx, route, chat, id, round,
                            instructions, payload, call.token)
                    } } finally { guard.cancel(); registration.dispose() }
                } })
            }.also { check(it.isNotBlank() && it.length <= 64_000) }.let { result ->
                ctx.getString(R.string.auto_team_job_receipt, roles.get(), calls.get()) +
                    "\n\n" + result
            }
        } catch (_: TeamFinalAuditMissing) {
            ctx.getString(R.string.auto_team_final_audit_missing)
        } catch (e: TeamAnswerWithheld) {
            ctx.getString(R.string.auto_team_job_withheld, e.reservation) + e.publicObjections
        } catch (e: TeamTableMismatch) {
            ctx.getString(R.string.auto_team_table_mismatch, e.verified) + e.publicObjections
        } catch (_: Exception) {
            cancel.cancel()
            ctx.getString(R.string.auto_team_job_failed, route.label)
        } finally {
            live.remove(id, cancel)
        }
        synchronized(lock) {
            if (stopped() || own()?.optString("state") != "running") return
            finish(ctx, chat, job, answer)
        }
    }
}

class AutoGoalTeamWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    private val cancellation = AgentNativeToolCancellationSource()
    override fun onStopped() { cancellation.cancel(); super.onStopped() }
    override fun doWork(): Result {
        val chat = inputData.getString("chat") ?: return Result.failure()
        val id = inputData.getString("id") ?: return Result.failure()
        AutoGoalTeamJobs.execute(applicationContext, chat, id, { isStopped }, cancellation)
        return Result.success()
    }
}
