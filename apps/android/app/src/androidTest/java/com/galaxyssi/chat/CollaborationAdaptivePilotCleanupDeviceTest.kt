package com.galaxyssi.chat

import android.os.Build
import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Reconcile only an already stopped trial; never resume execution or rewrite its verdict. */
@RunWith(AndroidJUnit4::class)
class CollaborationAdaptivePilotCleanupDeviceTest {
    @Test fun reconcileStoppedTrial() = runBlocking<Unit> {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("adaptivePilotCleanup") == "true")
        CollaborationTrialDeviceBinding.requireOperatorTarget(Build.MODEL, args.getString("pilotDeviceModel"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        fun read(nameKey: String, hashKey: String): JSONObject {
            val name = args.getString(nameKey).orEmpty()
            require(name.matches(Regex("[a-zA-Z0-9_-]+\\.json")))
            val source = File(context.getExternalFilesDir(null), name)
            require(source.length() in 1..16_777_216)
            val raw = source.readBytes()
            require(CollaborationRemotePilotDispatch.sha256(raw) == args.getString(hashKey))
            return JSONObject(raw.toString(Charsets.UTF_8))
        }
        val protocol = read("adaptivePilotInput", "adaptivePilotSha256")
        val original = read("cleanupReportInput", "cleanupReportSha256")
        val plan = CollaborationAdaptivePilotPlan.from(protocol,
            requireNotNull(args.getString("adaptivePilotMaxDispatches")?.toIntOrNull()),
            requireNotNull(args.getString("adaptivePilotMaxMillis")?.toLongOrNull()))
        plan.requireDevice(Build.MODEL, args.getString("pilotDeviceModel"))
        val run = "adaptive-pilot-${plan.id}"
        require(original.getString("format") == "galaxyssi.adaptive-pilot-report.v1" && original.getBoolean("finished"))
        require(original.getString("pilot_id") == plan.id && original.getString("run_id") == run &&
            original.getString("execution_database") == run && original.getString("device") == Build.MODEL &&
            original.getString("protocol_sha256") == args.getString("adaptivePilotSha256"))
        val control = AgentTeamDurableControl(context)
        require(original.getString("durable_control") == "STOP" && control.get(run) == AgentTeamUserControl.STOP)
        val store = CollaborationAdaptivePilotMilestones.executionStore(context, AgentEncryptedDatabase(context, run))
        val snapshot = requireNotNull(store.snapshot(run)) { "No retained stopped trial; do not reconstruct it" }
        require(snapshot.conversationId == original.getString("conversation_id"))
        val wait = requireNotNull(args.getString("cleanupMaxMillis")?.toLongOrNull())
        require(wait in 1..120_000)
        val name = args.getString("cleanupOutput").orEmpty()
        require(name.matches(Regex("[a-zA-Z0-9_-]+\\.json")))
        val file = File(context.getExternalFilesDir(null), name)
        check(!File(file.path + ".bak").exists() && !File(file.path + ".new").exists() && file.createNewFile())
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val windows = CollaborationPilotWindowSnapshot.read(context)
        val before = ledger.pendingForSupervisor(run).map { it.ownerRunId }
        val recovery = AgentTeamRemoteStopRecovery(context)
        GalaxySSIMqttClient.connect(context)
        val confirmed = withTimeoutOrNull(wait) {
            while (true) {
                require(control.get(run) == AgentTeamUserControl.STOP)
                recovery.reconcile(listOf(snapshot), ledger) { it == run }
                if (ledger.pendingForSupervisor(run).isEmpty()) break
                delay(250)
            }
            true
        } == true
        val result = JSONObject().put("format", "galaxyssi.adaptive-pilot-cleanup.v1")
            .put("pilot_id", plan.id).put("source_report_sha256", args.getString("cleanupReportSha256"))
            .put("original_verdict_preserved", true).put("model_dispatches", 0).put("execution_resumed", false)
            .put("pending_before", JSONArray(before)).put("cleanup_confirmed", confirmed)
            .put("pending_after", JSONArray(ledger.pendingForSupervisor(run).map { it.ownerRunId }))
            .put("window_selections_preserved", windows == CollaborationPilotWindowSnapshot.read(context))
            .put("records_retained", true).put("recorded_at", System.currentTimeMillis())
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(result.toString().toByteArray(Charsets.UTF_8)); atomic.finishWrite(stream) }
        catch (failure: Throwable) { atomic.failWrite(stream); throw failure }
        assertTrue("Remote stop receipts remain pending; original report and checkpoint retained", confirmed)
        assertTrue("Persisted window selections changed during stop reconciliation",
            result.getBoolean("window_selections_preserved"))
    }
}
