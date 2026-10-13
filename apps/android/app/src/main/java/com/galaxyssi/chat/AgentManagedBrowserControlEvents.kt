package com.galaxyssi.chat

import android.app.NotificationManager
import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import org.json.JSONObject

/** Indexed routing hints, never authorization. Each browser generation has its own encrypted row. */
internal class AgentManagedBrowserWakeIndex(context: Context) {
    private val app = context.applicationContext
    private val rows = AgentEncryptedDatabase(app, "managed_browser_control_wakes_v1")

    fun track(record: AgentBrowserUserRequest) {
        if (record.managedOwnerRunId.isBlank() || record.localDispatchId.isBlank()) return
        val dispatch = AgentLocalBrowserDispatchStore(app).load(record.localDispatchId) ?: return
        val owner = dispatch.managedOwner ?: return
        if (!AgentLocalBrowserDispatchPolicy.matches(dispatch, record)) return
        val key = prefix(owner.supervisorRunId) + record.key
        synchronized(LOCK) {
            val previous = rows.readString(key, "").takeIf(String::isNotEmpty)?.let(::JSONObject)
            val released = record.state == "returned" || previous?.let {
                it.optString("generation") == record.generation && it.optBoolean("released")
            } == true
            val value = JSONObject().put("run", owner.supervisorRunId).put("key", record.key)
                .put("generation", record.generation).put("released", released).toString()
            if (rows.readString(key, "") != value) rows.writeString(key, value)
        }
    }

    fun records(runId: String): Sequence<AgentBrowserUserRequest> = sequence {
        val prefix = prefix(runId)
        var after = ""
        while (true) {
            val page = rows.keysAfter(prefix, after, 64)
            if (page.isEmpty()) break
            for (key in page) {
                val hint = rows.readString(key, "").takeIf(String::isNotEmpty)?.let(::JSONObject) ?: continue
                check(hint.getString("run") == runId && key == prefix + hint.getString("key"))
                val record = AgentBrowserUserRequestStore(app).load(hint.getString("key"))
                if (record == null || record.generation != hint.getString("generation")) continue
                val dispatch = AgentLocalBrowserDispatchStore(app).load(record.localDispatchId) ?: continue
                if (dispatch.managedOwner?.supervisorRunId == runId && AgentLocalBrowserDispatchPolicy.matches(dispatch, record))
                    yield(record)
            }
            after = page.last()
        }
    }

    fun released(record: AgentBrowserUserRequest) {
        val dispatch = AgentLocalBrowserDispatchStore(app).load(record.localDispatchId) ?: return
        val run = dispatch.managedOwner?.supervisorRunId ?: return
        val key = prefix(run) + record.key
        val acknowledged = AgentBrowserUserRequestStore(app).load(record.key)?.let {
            it.generation == record.generation && it.runWakeAcknowledged
        } == true
        synchronized(LOCK) {
            val value = rows.readString(key, "").takeIf(String::isNotEmpty)?.let(::JSONObject) ?: return
            if (value.getString("generation") != record.generation) return
            if (acknowledged) rows.remove(key)
            else rows.writeString(key, value.put("released", true).toString())
        }
    }

    fun committed(record: AgentBrowserUserRequest) {
        if (!record.runWakeAcknowledged || record.managedOwnerRunId.isBlank()) return
        val dispatch = AgentLocalBrowserDispatchStore(app).load(record.localDispatchId) ?: return
        val key = prefix(dispatch.managedOwner?.supervisorRunId ?: return) + record.key
        synchronized(LOCK) {
            val value = rows.readString(key, "").takeIf(String::isNotEmpty)?.let(::JSONObject) ?: return
            if (value.getString("generation") == record.generation &&
                (value.optBoolean("released") || record.interruptionCode != "browser_owner_stopped")) rows.remove(key)
        }
    }

    fun pendingRuns(): Sequence<String> = sequence {
        var after = ""
        while (true) {
            val page = rows.keysAfter("run:", after, 64)
            if (page.isEmpty()) break
            for (key in page) {
                val value = rows.readString(key, "").takeIf(String::isNotEmpty)?.let(::JSONObject) ?: continue
                yield(value.getString("run"))
            }
            after = page.last()
        }
    }.distinct()

    /** Exact-generation cleanup, also used by isolated framework fixtures. */
    fun remove(record: AgentBrowserUserRequest) {
        val dispatch = AgentLocalBrowserDispatchStore(app).load(record.localDispatchId) ?: return
        val key = prefix(dispatch.managedOwner?.supervisorRunId ?: return) + record.key
        synchronized(LOCK) {
            val value = rows.readString(key, "").takeIf(String::isNotEmpty)?.let(::JSONObject) ?: return
            if (value.getString("generation") == record.generation) rows.remove(key)
        }
    }

    private fun prefix(run: String): String { require(run.isNotBlank()); return "run:${AgentNativeJsonCodec.sha256(run)}:" }
    private companion object { val LOCK = Any() }
}

internal object AgentManagedBrowserControlEvents {
    fun recoverIndexed(context: Context) {
        AgentManagedBrowserWakeIndex(context).pendingRuns().forEach { run ->
            if (AgentTeamDurableControl(context).get(run) != AgentTeamUserControl.PAUSE) enqueue(context, run)
        }
    }

    fun enqueue(context: Context, run: String): Operation {
        require(run.isNotBlank())
        val work = OneTimeWorkRequestBuilder<AgentManagedBrowserControlWorker>()
            .setInputData(workDataOf("run" to run))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build()
        // A fresh control event must not wait behind an earlier worker's retry backoff.
        return WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(workName(run),
            ExistingWorkPolicy.REPLACE, work)
    }

    internal fun workName(run: String) = "managed-browser-control-${AgentNativeJsonCodec.sha256(run)}"

    internal fun reconcile(context: Context, run: String,
        enqueue: (AgentBrowserUserRequest) -> Unit = { AgentLocalBrowserRecovery.enqueue(context, it, replace = true) },
        release: (AgentBrowserUserRequest) -> Unit = { AgentBrowserUserControl(context).releaseStopped(it) }): Boolean {
        val app = context.applicationContext
        val index = AgentManagedBrowserWakeIndex(app)
        val browsers = AgentBrowserUserRequestStore(app)
        var complete = true
        for (indexed in index.records(run)) {
            val control = AgentTeamDurableControl(app).get(run)
            if (control == AgentTeamUserControl.PAUSE) continue
            if (control == AgentTeamUserControl.RUN && indexed.interruptionCode != "browser_owner_stopped") {
                if (indexed.pendingRunWake) enqueue(indexed)
                continue
            }
            val dispatch = AgentLocalBrowserDispatchStore(app).load(indexed.localDispatchId) ?: continue
            AgentLocalDispatchRegistry.cancelExact(dispatch.identity)
            // The initial host begin and the STOP transition cannot pass one another in flight.
            AgentWorkspaceScope.withLock("browser-handoff:${indexed.key}") {
                val current = browsers.load(indexed.key)?.takeIf { it.generation == indexed.generation } ?: return@withLock
                if (AgentTeamDurableControl(app).get(run) != AgentTeamUserControl.STOP &&
                    current.interruptionCode != "browser_owner_stopped") return@withLock
                val stopped = browsers.interruptOwner(current) ?: current
                AgentBrowserRuntimeEvents.forContext(app).unwatch(current)
                AgentBrowserSessionEvents.forContext(app).unwatch(current)
                app.getSystemService(NotificationManager::class.java).cancel(current.key, 1)
                // Publish cancellation independently of a slow/unavailable browser host.
                if (stopped.pendingRunWake) enqueue(stopped)
                try { release(stopped); index.released(stopped) }
                catch (error: Exception) {
                    if (error is CancellationException) throw error
                    complete = false
                }
            }
        }
        return complete
    }
}

class AgentManagedBrowserControlWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val run = inputData.getString("run")?.takeIf(String::isNotBlank) ?: return Result.failure()
        return try {
            if (AgentManagedBrowserControlEvents.reconcile(applicationContext, run)) Result.success() else Result.retry()
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            android.util.Log.w("GalaxySSIBrowserRecovery", "Managed browser control reconciliation deferred", error)
            Result.retry()
        }
    }
}
