package com.galaxyssi.chat

import android.os.Build
import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit test-only report recovery; never starts a connector or invokes a model. */
@RunWith(AndroidJUnit4::class)
class CollaborationPilotReportRecoveryDeviceTest {
    @Test fun recoverCompletedReportArtifacts() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("candidateReportRecovery") == "true")
        require(Build.MODEL == "SM-S9480" && args.getString("pilotDeviceModel") == "SM-S9480")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        fun read(nameKey: String, digestKey: String): String {
            val name = args.getString(nameKey).orEmpty()
            require(name.matches(Regex("[a-zA-Z0-9_-]+\\.json")))
            val file = File(context.getExternalFilesDir(null), name)
            require(file.length() in 1..1_000_000)
            val bytes = file.readBytes()
            require(CollaborationRemotePilotDispatch.sha256(bytes) == args.getString(digestKey))
            return bytes.toString(Charsets.UTF_8)
        }
        val protocol = read("remotePilotInput", "remotePilotSha256")
        val raw = read("recoveryReportInput", "recoveryReportSha256")
        val allowance = requireNotNull(args.getString("remotePilotMaxDispatches")?.toIntOrNull())
        val plan = CollaborationRemotePilotPlan.from(JSONObject(protocol), allowance)
        val artifacts = plan.slots.map { slot ->
            CollaborationPilotArtifact.recoverReport(plan, slot, args.getString("remotePilotSha256")!!,
                raw, args.getString("recoveryReportSha256")!!)
        }
        val store = CollaborationPilotArtifactStore(context, plan.id)
        val sources = JSONArray()
        artifacts.forEach { artifact ->
            val ref = store.freeze(artifact)
            check(store.read(artifact.source, ref).finalOutput == artifact.finalOutput)
            sources.put(JSONObject().put("id", artifact.source.slotId).put("source", artifact.source.json())
                .put("reference", ref.json()).put("final_output_sha256",
                    CollaborationRemotePilotDispatch.sha256(artifact.finalOutput.toByteArray(Charsets.UTF_8))))
        }
        val output = JSONObject().put("format", "galaxyssi.pilot-report-recovery.v1")
            .put("source_report_sha256", args.getString("recoveryReportSha256"))
            .put("source_protocol_sha256", args.getString("remotePilotSha256"))
            .put("trust", "unverified_candidate").put("provider_attested", false)
            .put("model_calls", 0).put("sources", sources)
        val file = AtomicFile(File(context.getExternalFilesDir(null), "recovered-${plan.id}.json"))
        if (file.baseFile.exists()) {
            check(JSONObject(file.readFully().toString(Charsets.UTF_8)).toString() == output.toString())
        } else {
            val stream = file.startWrite()
            try { stream.write(output.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(stream) }
            catch (failure: Throwable) { file.failWrite(stream); throw failure }
        }
    }
}
