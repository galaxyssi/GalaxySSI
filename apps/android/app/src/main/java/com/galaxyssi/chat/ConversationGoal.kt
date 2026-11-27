package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal sealed interface GoalCommand {
    data class Start(val text: String) : GoalCommand
    data class Resume(val note: String) : GoalCommand
    data object Status : GoalCommand
    data object Pause : GoalCommand
    data object Stop : GoalCommand
    data object Help : GoalCommand

    companion object {
        fun parse(input: String): GoalCommand? {
            val match = Regex("""^/goal(?:\s+([\s\S]*))?$""", RegexOption.IGNORE_CASE)
                .matchEntire(input.trim()) ?: return null
            val text = match.groupValues[1].trim()
            if (text.length > 4000) return Help
            val action = text.takeWhile { !it.isWhitespace() }
            val rest = text.drop(action.length).trim()
            return when (action.lowercase()) {
                "", "status", "状态" -> if (rest.isEmpty()) Status else Help
                "help", "帮助" -> Help
                "pause", "暂停" -> if (rest.isEmpty()) Pause else Help
                "stop", "停止" -> if (rest.isEmpty()) Stop else Help
                "resume", "继续" -> Resume(rest)
                else -> Start(text)
            }
        }
    }
}

internal enum class GoalPhase { RUNNING, PAUSED, BLOCKED, DONE, STOPPED }

internal data class GoalRoute(val target: String, val model: String, val endpointHash: String, val host: String = "") {
    val label get() = listOf(model, host).filter(String::isNotEmpty).joinToString(" · ")
    fun json() = JSONObject().put("target", target).put("model", model).put("endpoint", endpointHash).put("host", host)
}

internal data class ConversationGoal(
    val chat: String, val objective: String, val route: GoalRoute,
    val id: String = UUID.randomUUID().toString(), val generation: Int = 1,
    val phase: GoalPhase = GoalPhase.RUNNING, val rounds: Int = 0, val allowance: Int = BUDGET,
    val inFlight: Boolean = false, val checkpoints: List<String> = emptyList(),
    val next: String = "", val note: String = "", val revision: Int = 0, val review: Boolean = false,
    val issue: String = ""
) {
    val terminal get() = phase == GoalPhase.DONE || phase == GoalPhase.STOPPED
    fun halt(why: String) = copy(phase = GoalPhase.BLOCKED, inFlight = false, issue = why, revision = revision + 1)
    fun accept(raw: String): ConversationGoal {
        check(phase == GoalPhase.RUNNING && inFlight)
        val json = JSONObject(raw.trim().removePrefix("```json").removePrefix("```").removeSuffix("```").trim())
        val state = json.getString("state")
        val work = (json.opt("result") as? String).orEmpty().trim()
        val pending = (json.opt("next") as? String).orEmpty().trim()
        if (state == "verified") {
            require(review && checkpoints.isNotEmpty() && work.isEmpty() && pending.isEmpty())
            return copy(phase = GoalPhase.DONE, inFlight = false, review = false, next = "", issue = "", revision = revision + 1)
        }
        require(state in setOf("continue", "done", "blocked") && (!review || state != "done") &&
            work.length <= 12000 && pending.length <= 1000)
        require((state == "blocked" || work.isNotEmpty()) && (state == "done" || pending.isNotEmpty()))
        if (work.isNotEmpty() && work in checkpoints) return halt("模型重复了已有成果，没有取得新进展。")
        val history = checkpoints + listOf(work).filter(String::isNotEmpty)
        // All delivered stages remain in chat. Bound only the model handoff, preserving the first stage.
        val result = copy(inFlight = false, checkpoints = if (history.size <= 16) history else history.take(1) + history.takeLast(15),
            next = pending, issue = "", review = state == "done", revision = revision + 1)
        return when {
            state == "blocked" -> result.copy(phase = GoalPhase.BLOCKED)
            rounds >= allowance -> result.copy(phase = GoalPhase.PAUSED)
            else -> result
        }
    }

    fun json() = JSONObject().put("id", id).put("chat", chat).put("objective", objective).put("route", route.json())
        .put("generation", generation).put("phase", phase.name).put("rounds", rounds).put("allowance", allowance)
        .put("flight", inFlight).put("checkpoints", JSONArray(checkpoints)).put("next", next)
        .put("note", note).put("revision", revision).put("review", review).put("issue", issue)

    companion object {
        const val BUDGET = 6
        fun decode(raw: String): ConversationGoal {
            val j = JSONObject(raw)
            val r = j.getJSONObject("route")
            val steps = j.getJSONArray("checkpoints")
            return ConversationGoal(j.getString("chat"), j.getString("objective"),
                GoalRoute(r.getString("target"), r.getString("model"), r.getString("endpoint"), r.optString("host")), j.getString("id"),
                j.getInt("generation"), GoalPhase.valueOf(j.getString("phase")), j.getInt("rounds"),
                j.getInt("allowance"), j.getBoolean("flight"), List(steps.length()) { steps.getString(it) },
                j.getString("next"), j.getString("note"), j.getInt("revision"), j.optBoolean("review"), j.optString("issue"))
        }
    }
}

internal class ConversationGoalStore(context: Context) {
    private val database = AgentEncryptedDatabase(context, "galaxyssi_conversation_goals_v1")
    fun get(chat: String) = database.readString(chat, "").takeIf(String::isNotEmpty)?.let(ConversationGoal::decode)
    fun put(goal: ConversationGoal) = database.writeString(goal.chat, goal.json().toString())
    fun remove(chat: String) = synchronized(lock) { database.remove(chat) }
    companion object { val lock = Any() }
}
