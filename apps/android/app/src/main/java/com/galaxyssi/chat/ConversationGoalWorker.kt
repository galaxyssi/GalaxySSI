package com.galaxyssi.chat

import android.content.Context
import android.os.SystemClock
import androidx.work.*
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import java.util.concurrent.TimeUnit

internal object ConversationGoalRunner {
    fun eligible(context: Context, chat: AgentConversation?) = chat != null &&
        chat.status == AgentConversationStatus.ACTIVE && chat.globalTopicKey.isEmpty() && !chat.privateMode &&
        chat.mergedIntoConversationId.isEmpty() && CollaborationGroupStore(context).load(chat.id) == null

    private fun cloud(context: Context, id: String, model: String): JSONObject? =
        AppStore.selectedCloudModelContact(context, id)?.let { CloudModelRequestRoutingPolicy.resolve(it, model, false) }

    fun routes(context: Context, chat: String): List<GoalRoute> {
        val selection = AgentModelSelectionSettings.selection(context, chat)
        return AppStoreAgentConnectorRegistry(context).availableTargets()
            .filter { it.status == AgentConnectorStatus.AVAILABLE }
            .sortedBy { it.id != selection.targetId }.mapNotNull { target ->
                if (target.id == "local-llm") {
                    val profiles = LocalModelCooperativeRuntime.readyProfiles(context, LocalModelWorkClass.BACKGROUND)
                    val preferred = LocalModelRuntimeSettings.selectedProfile(context).id
                    val selected = profiles.firstOrNull { it.id == preferred } ?: profiles.firstOrNull()
                    selected?.let { GoalRoute(target.id, it.id, "") }
                } else if (AppStore.isCloudApiContact(context, target.id)) {
                    val config = AgentModelSelectionSettings.configurationForTarget(context, chat, target.id)
                    val c = cloud(context, target.id, config?.modelId.orEmpty()) ?: return@mapNotNull null
                    GoalRoute(target.id, c.getString("cloud_model"), fingerprint(c),
                        android.net.Uri.parse(c.getString("cloud_endpoint")).host ?: return@mapNotNull null)
                } else null
            }
    }

    internal fun fingerprint(c: JSONObject) = AgentNativeJsonCodec.sha256(
        c.getString("cloud_endpoint") + "|" + c.optString("cloud_api_style"))

    suspend fun step(context: Context, g: ConversationGoal, token: AgentNativeToolCancellationToken,
        resolveCloud: (Context, String, String) -> JSONObject? = ::cloud): String {
        val system = "Work on one persistent, text-only goal. Produce actual work in the user's language each round. " +
            "The only available inputs are the objective, checkpoints and user clarification. No tools, web access, " +
            "device actions, other chats or health records. Never claim an action, search or verification you did not perform. " +
            "When an external action, fresh source, permission or missing input is essential, return blocked and say what is needed. " +
            "Return one JSON object: state (continue, done, blocked), result (concrete new work or full final deliverable, " +
            "not a promise), next (next step or specific blocking question). Finish as soon as the objective is met." +
            if (g.review) " This is a separate FINAL REVIEW. Inspect the last checkpoint against the full objective and user clarification. " +
                "If the deliverable is complete, return exactly {\"state\":\"verified\",\"result\":\"\",\"next\":\"\"}. " +
                "Promises and unsupported external claims do not pass. Otherwise return continue with concrete corrections, or blocked. Do not return done." else ""
        val previous = g.checkpoints
        val history = previous.mapIndexed { i, s -> when {
            g.review && i == previous.lastIndex -> s
            i >= previous.size - 2 -> s.take(8000)
            else -> s.take(480)
        } }
        val prompt = JSONObject().put("objective", g.objective).put("checkpoints", org.json.JSONArray(history))
            .put("pending", g.next).put("clarification", g.note).put("remaining_rounds", g.allowance - g.rounds).toString()
        return text(context, g.route, g.chat, g.id, g.rounds, system, prompt, token, resolveCloud)
    }

    internal suspend fun text(context: Context, route: GoalRoute, chat: String, run: String, round: Int,
        system: String, prompt: String, token: AgentNativeToolCancellationToken,
        resolveCloud: (Context, String, String) -> JSONObject? = ::cloud): String {
        check(!token.isCancellationRequested)
        if (route.target == "local-llm") {
            val profile = LocalModelCooperativeRuntime.readyProfiles(context, LocalModelWorkClass.BACKGROUND)
                .singleOrNull { it.id == route.model } ?: error("model unavailable")
            return LocalModelInferenceRuntime.generate(context, profile, system, prompt, maximumTokens = 2048,
                workClass = LocalModelWorkClass.BACKGROUND, taskId = run).text
        }
        val c = resolveCloud(context, route.target, route.model) ?: error("model unavailable")
        check(c.getString("cloud_model") == route.model && fingerprint(c) == route.endpointHash)
        val endpoint = c.getString("cloud_endpoint")
        val wire = teamPlanWire(system, endpoint, c.optString("cloud_api_style", "openai"))
        val format = if (wire == null) teamAuditOutputFormat(system, endpoint) else wire.requestFormat
        val response = CloudModelClient.nativeToolAdapter(context, c, emptyList(), textOnlyResponseFormat = format).complete(
            AgentModelRequest(run, chat, "$run-$round", run, chat, round,
                listOf(AgentModelMessage.system(wire?.system ?: system), AgentModelMessage.user(prompt)), "[]",
                AgentNativeJsonCodec.sha256("[]"), 0, 3000, 120_000, 0, token))
        check(response.toolCalls.isEmpty())
        return wire?.decode(response.assistantText) ?: response.assistantText
    }

    fun name(g: ConversationGoal) = "conversation-goal:${g.id}:${g.generation}"
    // Queue first under the same lock as the state change. The worker cannot claim an uncommitted goal.
    fun schedule(context: Context, g: ConversationGoal) {
        val request = OneTimeWorkRequestBuilder<ConversationGoalWorker>()
            .setInputData(workDataOf("chat" to g.chat, "goal" to g.id, "generation" to g.generation))
            .setConstraints(Constraints.Builder().apply {
                if (g.route.target != "local-llm") setRequiredNetworkType(NetworkType.CONNECTED)
            }.build()).build()
        WorkManager.getInstance(context).enqueueUniqueWork(name(g), ExistingWorkPolicy.KEEP, request)
            .result.get(15, TimeUnit.SECONDS)
    }
}

class ConversationGoalWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    private val cancellation = AgentNativeToolCancellationSource()
    override fun onStopped() { cancellation.cancel(); super.onStopped() }

    override fun doWork(): Result {
        val ctx = applicationContext
        val chat = inputData.getString("chat") ?: return Result.failure()
        val id = inputData.getString("goal") ?: return Result.failure()
        val epoch = inputData.getInt("generation", -1)
        val transcript = AgentTranscriptStore(ctx)
        return execute(ctx, chat, id, epoch, ConversationGoalStore(ctx), { isStopped },
            { ConversationGoalRunner.eligible(ctx, transcript.conversation(chat)) },
            { g -> runBlocking { ConversationGoalRunner.step(ctx, g, cancellation.token) } }) { g ->
            if (g.review && g.phase == GoalPhase.RUNNING) return@execute
            val text = buildString {
                append(ctx.getString(R.string.goal_round, g.rounds, ctx.getString(g.phase.label())))
                g.checkpoints.lastOrNull()?.let { append("\n\n").append(it) }
                if (g.next.isNotEmpty()) append("\n\n").append(g.next)
                if (g.issue.isNotEmpty()) append("\n\n").append(g.issue)
                if (g.phase == GoalPhase.PAUSED && g.rounds >= g.allowance)
                    append("\n\n").append(ctx.getString(R.string.goal_budget))
            }
            transcript.append(AgentTranscriptRole.ASSISTANT, text, "goal:${g.id}:${g.revision}",
                conversationId = chat, turnId = "${g.id}-${g.rounds}")
        }
    }

    internal companion object {
      fun execute(ctx: Context, chat: String, id: String, epoch: Int, store: ConversationGoalStore,
          stopped: () -> Boolean, eligible: () -> Boolean, infer: (ConversationGoal) -> String,
          deliver: (ConversationGoal) -> Unit): Result {
        fun current() = store.get(chat)?.takeIf { it.id == id && it.generation == epoch }
        fun publish(g: ConversationGoal) { if (g.revision > 0) deliver(g) }
        val start = SystemClock.elapsedRealtime()
        while (!stopped()) {
            val claimed = synchronized(ConversationGoalStore.lock) {
                val g = current() ?: return Result.success()
                if (!eligible()) {
                    if (g.phase == GoalPhase.RUNNING) store.put(g.halt(ctx.getString(R.string.goal_chat_unavailable)))
                    return Result.success()
                }
                if (g.inFlight) {
                    val blocked = g.halt(ctx.getString(R.string.goal_interrupted))
                    store.put(blocked); publish(blocked)
                    return Result.success()
                }
                publish(g)
                if (g.phase != GoalPhase.RUNNING) return Result.success()
                if (SystemClock.elapsedRealtime() - start > 180_000L) return Result.retry()
                g.copy(rounds = g.rounds + 1, inFlight = true).also(store::put)
            }
            val updated = try {
                val raw = infer(claimed)
                runCatching { claimed.accept(raw) }.getOrElse { claimed.halt(ctx.getString(R.string.goal_invalid)) }
            } catch (_: Exception) {
                if (stopped()) return Result.success()
                claimed.halt(ctx.getString(R.string.goal_provider_error, claimed.route.model))
            }
            synchronized(ConversationGoalStore.lock) {
                if (current() != claimed || stopped()) return Result.success()
                store.put(updated)
            }
        }
        return Result.success()
      }
    }
}

internal fun GoalPhase.label() = when (this) {
    GoalPhase.RUNNING -> R.string.goal_running
    GoalPhase.PAUSED -> R.string.goal_paused
    GoalPhase.BLOCKED -> R.string.goal_blocked
    GoalPhase.DONE -> R.string.goal_done
    GoalPhase.STOPPED -> R.string.goal_stopped
}
