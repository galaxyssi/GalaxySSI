package com.galaxyssi.watch

import android.content.Context
import com.galaxyssi.chat.AgentRemoteRecoveryClient
import com.galaxyssi.chat.AgentResultRecoveryClient
import com.galaxyssi.chat.AgentResultPageDatabase
import com.galaxyssi.chat.AgentRemoteOutcomeCodec
import kotlinx.coroutines.*
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/** Same read-only recovery protocol as Android; recovery never reruns the user's task. */
internal class WatchRemoteRecovery(context: Context,
    private val publish: (String, JSONObject) -> Boolean,
    private val accept: (String, JSONObject) -> Unit,
    private val current: (String) -> WatchTask?
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val queries = AgentRemoteRecoveryClient()
    private val results = AgentResultRecoveryClient()
    private val pages = AgentResultPageDatabase(context)
    private val running = ConcurrentHashMap.newKeySet<String>()
    private val last = ConcurrentHashMap<String, Long>()

    fun receive(desktop: String, payload: JSONObject): Boolean = when (payload.optString("type")) {
        "agent_task_recovery_result" -> { queries.receive(payload, desktop); true }
        "agent_task_result_page" -> { results.receive(payload, desktop); true }
        else -> false
    }

    fun refresh(tasks: List<WatchTask>) {
        val now = android.os.SystemClock.elapsedRealtime()
        tasks.filter { it.desktopId !in setOf("api", "watch-location") && it.localOperation.isEmpty() &&
            (!it.state.terminal || (it.remoteTaskId.isNotBlank() && it.reply.isBlank())) }
            .takeLast(32).forEach { task ->
                if (now - (last[task.id] ?: Long.MIN_VALUE / 2) < 30_000 || !running.add(task.id)) return@forEach
                last[task.id] = now
                scope.launch {
                    try {
                        val fields = task.request("").put("task_id", task.remoteTaskId.ifBlank { task.id })
                            .put("source_message_id", task.sourceId.toString())
                        queries.query(task.desktopId, task.routeId, listOf(fields), includeResultPage = true,
                            onResponse = { observations -> observations.forEach { observation ->
                                scope.launch { recover(task, observation) }
                            } }, publish = { publish(task.desktopId, it) })
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (error: Exception) { android.util.Log.w("WatchRecovery", "Query deferred: ${error.javaClass.simpleName}") }
                    finally { running.remove(task.id) }
                }
            }
    }

    private suspend fun recover(task: WatchTask, observation: JSONObject) {
        val status = observation.optString("status")
        if (status == "unavailable" || current(task.id) == null) return
        val event = JSONObject(observation.toString()).put("type", "agent_task_event")
            .put("task_status", status).put("status_seq", observation.optLong("status_sequence", -1))
        accept(task.desktopId, event)
        if (status !in AgentRemoteOutcomeCodec.TERMINAL) return
        val fields = JSONObject(observation.toString()).put("expected_status", status)
        val result = results.fetch(task.desktopId, fields,
            stillPending = { current(task.id)?.let { it.routeId == task.routeId && it.reply.isBlank() &&
                it.executionGeneration <= observation.optLong("execution_generation", 1) } == true },
            checkpoint = pages.checkpoint(task.desktopId, fields), firstPage = observation.optJSONObject("result_page"),
            publish = { publish(task.desktopId, it) }) ?: return
        accept(task.desktopId, result)
    }
}
