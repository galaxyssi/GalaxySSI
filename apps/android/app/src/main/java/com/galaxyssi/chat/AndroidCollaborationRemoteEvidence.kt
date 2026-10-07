package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject

/** Authenticated managed Codex assignments can import live evidence; ordinary chat has no extra queries. */
internal object AndroidCollaborationRemoteEvidence {
    private val client = CollaborationRemoteEvidenceClient()
    private val recoveryLock = Mutex()
    private val recoveryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val liveRecovery = java.util.concurrent.atomic.AtomicBoolean()
    @Volatile private var nextLiveRecoveryAt = 0L
    private const val PREFERENCES = "collaboration_remote_evidence_capabilities"

    fun manifest(context: Context, desktop: String, payload: JSONObject) {
        if (desktop.isBlank() || GalaxySSILinkProtocol.serverLink(context, desktop)?.paired != true) return
        val features = payload.optJSONArray("features") ?: return
        val supported = (0 until features.length()).any { features.optString(it) == CollaborationRemoteEvidenceProtocol.CAPABILITY }
        val route = GalaxySSILinkProtocol.serverLink(context, desktop)?.routes?.clientRouteId.orEmpty()
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
            .putString(desktop, route).putBoolean("$desktop:supported", supported).apply()
    }

    fun needsManifest(context: Context, desktop: String, route: String): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(desktop, "") != route

    private fun supported(context: Context, desktop: String, route: String): Boolean =
        !needsManifest(context, desktop, route) &&
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean("$desktop:supported", false)

    /** Persist the read-only intent before publishing the final model reply, never acknowledge false evidence. */
    fun capture(context: Context, payload: JSONObject, authenticatedDesktop: String) {
        if (!CollaborationRemoteEvidenceProtocol.validScope(payload) || payload.optBoolean("peer_chat") ||
            payload.optString("task_status") !in AgentRemoteOutcomeCodec.TERMINAL ||
            !AgentTaskIdentityStore.matchesRegistered(context, payload) || !paired(context, authenticatedDesktop, payload)) return
        if (!supported(context, authenticatedDesktop, payload.getString("client_route_id"))) return
        val source = payload.getString("source_message_id").toLongOrNull() ?: return
        val binding = CollaborationEvidenceLedger(context).binding(source, payload.getString("conversation_id"),
            payload.getString("turn_id")) ?: return
        if (!current(context, payload)) return
        val created = CollaborationRemoteEvidenceStore(context).createIntent(authenticatedDesktop, payload, binding).second
        enqueue(context, wake = created)
    }

    fun receive(context: Context, payload: JSONObject, desktop: String) {
        if (!paired(context, desktop, payload)) {
            Log.w("GalaxySSIEvidence", "Read-only evidence response rejected: paired_route_mismatch")
            return
        }
        client.receive(payload, desktop) { outcome ->
            Log.i("GalaxySSIEvidence", "Read-only evidence response: $outcome")
        }
    }

    internal suspend fun refresh(context: Context, request: JSONObject, desktop: String,
        binding: CollaborationWorkspaceAccess): JSONObject? {
        if (!CollaborationLiveEvidenceSync.needed(request)) return null
        if (AndroidCollaborationRemoteRecall.access(context, request, desktop) != binding)
            return CollaborationLiveEvidenceSync.report(null)
        if (!supported(context, desktop, request.getString("client_route_id")))
            return CollaborationLiveEvidenceSync.report(null, "unsupported")
        val budget = CollaborationLiveEvidenceSync.budget(request, System.currentTimeMillis())
        if (budget == 0L) return CollaborationLiveEvidenceSync.report(null, "deferred")
        val store = CollaborationRemoteEvidenceStore(context)
        val key = store.createIntent(desktop, request, binding, terminal = false).first
        try {
            withTimeoutOrNull(budget) {
                CollaborationRemoteEvidenceImporter(store, CollaborationEvidenceLedger(context)).run(key, allowed = {
                    CollaborationRemoteRecallProtocol.valid(request, System.currentTimeMillis()) &&
                        AndroidCollaborationRemoteRecall.access(context, request, desktop) == binding
                }) { target, fields, selection -> query(context, target, fields, selection) }
            }
        } finally {
            if (store.read(key)?.optString("status") == "pending") enqueue(context)
        }
        return CollaborationLiveEvidenceSync.report(store.read(key))
    }

    internal fun queryReadiness(context: Context, desktop: String, fields: JSONObject): String {
        val link = GalaxySSILinkProtocol.serverLink(context, desktop) ?: return "desktop_unavailable"
        if (!link.paired) return "desktop_unpaired"
        if (link.routes.clientRouteId != fields.optString("client_route_id")) return "stale_route_identity"
        if (AppStore.contactById(context, fields.optString("contact_id"))?.optString("desktop_id") != desktop)
            return "contact_binding_changed"
        if (!GalaxySSICrypto.hasDesktopSession(context, desktop)) return "signal_session_unavailable"
        return GalaxySSIMqttClient.transportQueryReadiness(fields.getString("contact_id"))
    }

    internal suspend fun query(context: Context, desktop: String, fields: JSONObject, selection: JSONObject,
        onDiagnostic: (String) -> Unit = {}): JSONObject? {
        var published = false
        val response = client.query(desktop, fields, selection) { request ->
            (paired(context, desktop, request) && GalaxySSIMqttClient.publishJsonForTransport(request,
                GalaxySSIMqttClient.outgoingTopicFor(request.getString("contact_id")), request.getString("contact_id")))
                .also { published = it }
        }
        val diagnostic = when {
            response != null -> "response_${response.optString("status")}"
            published -> "response_timeout"
            else -> "publish_rejected:${queryReadiness(context, desktop, fields)}"
        }
        onDiagnostic(diagnostic)
        if (response == null) Log.w("GalaxySSIEvidence", "Read-only evidence query deferred: $diagnostic")
        return response
    }

    fun pending(context: Context, group: String, source: Long): Boolean =
        CollaborationRemoteEvidenceStore(context).states(group, source).any { it.optString("status") == "pending" }

    fun summary(context: Context, execution: AgentTeamMemberExecutionContext): JSONArray {
        val source = AgentTeamDispatchIds.sourceMessageId("member:${execution.request.idempotencyKey}")
        return JSONArray(CollaborationRemoteEvidenceStore(context).states(execution.request.conversationId, source).map { job ->
            JSONObject().put("status", job.getString("status")).put("imported_observations", job.getLong("imported"))
                .put("large_originals_not_imported", job.getLong("skipped_large"))
                .put("archive_final", job.optBoolean("archive_final"))
                .put("synced_through_sequence", job.getLong("cursor"))
                .put("provider_history_complete", false).put("trust", CollaborationRemoteEvidenceProtocol.TRUST)
                .put("retrieval", "collaboration.recall mode=evidence; missing observations are not verified")
        })
    }

    suspend fun await(context: Context, execution: AgentTeamMemberExecutionContext) {
        val group = execution.member.context["collaboration_group_id"].orEmpty()
        if (group.isBlank()) return
        val source = AgentTeamDispatchIds.sourceMessageId("member:${execution.request.idempotencyKey}")
        if (!pending(context, group, source)) return
        CollaborationProgressStore.evidenceWaiting(context, execution)
        enqueue(context, wake = true)
        execution.suspendExecutionPermit {
            val control = AgentTeamDurableControl(context)
            while (pending(context, group, source)) {
                control.awaitDispatch(execution.request.parentRunId)
                delay(1_000)
            }
        }
    }

    fun enqueue(context: Context, wake: Boolean = false) {
        // WorkManager backoff survives disconnects. A live task must not wait hours for that old backoff.
        nudge(context, wake)
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork("collaboration-remote-evidence-v1",
            ExistingWorkPolicy.KEEP, OneTimeWorkRequestBuilder<CollaborationRemoteEvidenceWorker>()
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS).build())
    }

    private fun nudge(context: Context, wake: Boolean) {
        if (!wake && android.os.SystemClock.elapsedRealtime() < nextLiveRecoveryAt) return
        if (!liveRecovery.compareAndSet(false, true)) return
        val app = context.applicationContext
        recoveryScope.launch {
            try {
                withTimeoutOrNull(120_000) { recover(app) }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { Log.w("GalaxySSIEvidence", "Live evidence sync deferred: ${error.javaClass.simpleName}") }
            finally {
                nextLiveRecoveryAt = android.os.SystemClock.elapsedRealtime() + 30_000
                liveRecovery.set(false)
            }
        }
    }

    internal suspend fun recover(context: Context): Boolean = recoveryLock.withLock { recoverSerially(context) }

    private suspend fun recoverSerially(context: Context): Boolean {
        val store = CollaborationRemoteEvidenceStore(context)
        val ledger = CollaborationEvidenceLedger(context)
        val control = AgentTeamDurableControl(context)
        val importer = CollaborationRemoteEvidenceImporter(store, ledger)
        var after = store.schedulerCursor()
        var batch = store.pending(after)
        if (batch.isEmpty()) { after = ""; store.schedulerCursor(after); batch = store.pending() }
        for ((index, key) in batch) {
            after = index
            // Persist round-robin position before I/O, so one offline executor cannot starve later jobs after a worker timeout.
            store.schedulerCursor(after)
            val job = store.read(key) ?: continue
            val fields = job.getJSONObject("fields")
            val desktop = job.getString("desktop")
            val group = fields.getString("conversation_id")
            val binding = ledger.binding(fields.getString("source_message_id").toLong(), group, fields.getString("turn_id"))
            val revoked = binding == null || !paired(context, desktop, fields) ||
                CollaborationGroupStore(context).load(group)?.members?.none { it.id == binding.personId } != false
            val status = when {
                revoked -> "revoked"
                !supported(context, desktop, fields.getString("client_route_id")) -> "unsupported"
                !AgentTaskIdentityStore.matchesRegistered(context, fields) || !current(context, fields) -> "superseded"
                control.get(job.getString("run_id")) == AgentTeamUserControl.STOP -> "stopped"
                else -> null
            }
            if (status != null) {
                store.save(key, job.put("status", status)); AgentTeamBackgroundRecovery.enqueue(context); continue
            }
            if (control.get(job.getString("run_id")) == AgentTeamUserControl.PAUSE) continue
            if (job.optBoolean("terminal_requested", true))
                CollaborationProgressStore.evidenceTransfer(context, fields, job.getLong("imported"))
            val finished = importer.run(key, allowed = { latest ->
                control.get(latest.getString("run_id")) == AgentTeamUserControl.RUN &&
                    paired(context, desktop, fields) && current(context, fields) &&
                    CollaborationGroupStore(context).load(group)?.members?.any { it.id == binding?.personId } == true
            }, progress = { latest ->
                if (latest.optBoolean("terminal_requested", true))
                    CollaborationProgressStore.evidenceTransfer(context, fields, latest.getLong("imported"))
            }) {
                target, scope, selection -> query(context, target, scope, selection)
            }
            if (finished) AgentTeamBackgroundRecovery.enqueue(context)
        }
        if (store.pending(after).isEmpty()) store.schedulerCursor("")
        AgentTeamBackgroundRecovery.enqueue(context)
        return store.pending().isEmpty()
    }

    private fun paired(context: Context, desktop: String, fields: JSONObject): Boolean {
        val link = GalaxySSILinkProtocol.serverLink(context, desktop) ?: return false
        return link.paired && link.routes.clientRouteId == fields.optString("client_route_id") &&
            AppStore.contactById(context, fields.optString("contact_id"))?.optString("desktop_id") == desktop
    }
    private fun current(context: Context, fields: JSONObject): Boolean = AgentRemoteOutcomeCodec.observation(fields)?.let {
        AgentConnectorResponseStore.isCurrentExecution(context, it)
    } == true
}

class CollaborationRemoteEvidenceWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = try {
        // Yield the Android worker periodically; checkpoints survive and there is no total attempt limit.
        val complete = withTimeoutOrNull(120_000) { AndroidCollaborationRemoteEvidence.recover(applicationContext) } == true
        if (complete) Result.success() else Result.retry()
    } catch (cancelled: CancellationException) { throw cancelled }
    catch (error: Exception) {
        Log.w("GalaxySSIEvidence", "Read-only evidence recovery deferred: ${error.javaClass.simpleName}")
        Result.retry()
    }
}
