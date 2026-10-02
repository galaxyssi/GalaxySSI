package com.galaxyssi.chat

import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.WindowManager
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in live fixture: real providers and MQTT, no contacts, physical controls or original research. */
@RunWith(AndroidJUnit4::class)
class CollaborationLiveEvidenceDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun remoteAuthorIndependentReviewerAndHostAcceptance() = runBlocking {
        assumeTrue("Requires explicit authorization for real provider calls",
            InstrumentationRegistry.getArguments().getString("collaborationLiveEvidence") == "true")
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        val token = UUID.randomUUID().toString()
        val run = "live-evidence-$token"
        val turn = "turn-$token"
        var group = ""
        var previous = ""
        val database = AgentEncryptedDatabase(context, run)
        var handle: AgentTeamExecutionHandle? = null
        var runtime: AgentTeamExecutionRuntime? = null
        try {
            waitUntil("activity hydration") {
                var ready = false
                scenario.onActivity { ready = !it.initialAgentHydrationPending &&
                    it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE }
                ready
            }
            scenario.onActivity {
                it.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                previous = it.agentTranscriptStore.activeConversation().id
                it.createAgentConversation()
                group = it.agentTranscriptStore.activeConversation().id
            }
            val transcripts = AgentTranscriptStore(context)
            transcripts.append(AgentTranscriptRole.PROCESS, "Live evidence acceptance fixture",
                dedupeKey = run, conversationId = group)
            transcripts.renameConversation(group, "Evidence acceptance")
            waitUntil("secure MQTT") { GalaxySSIMqttClient.isConnected() && GalaxySSIMqttClient.isSecureReady() }
            assertTrue(GalaxySSIMqttClient.requestCapabilityManifestRefresh(force = true))
            var targets = emptyList<AgentCallableTarget>()
            waitUntil("paired Codex and DeepSeek") {
                targets = AppStoreAgentConnectorRegistry(context).availableTargets()
                    .filter { it.status == AgentConnectorStatus.AVAILABLE }
                targets.any { it.id.contains("codex", true) && ':' in it.id } &&
                    targets.any { it.id.contains("deepseek", true) || it.title.contains("deepseek", true) }
            }
            val codex = targets.first { it.id.contains("codex", true) && ':' in it.id }
            val deepseek = targets.first { it.id.contains("deepseek", true) || it.title.contains("deepseek", true) }
            val author = CollaborationMember(name = "Turing", agentId = codex.id, providerLabel = codex.title,
                role = "Document author and coordinator")
            val reviewer = CollaborationMember(name = "Curie", agentId = deepseek.id, providerLabel = deepseek.title,
                role = "Independent documentary reviewer", independentReview = true)
            CollaborationGroupStore(context).update(group) { it.copy(members = listOf(author, reviewer),
                coordinatorId = author.id, workflow = CollaborationWorkflow.RESEARCH) }
            scenario.onActivity { it.refreshCollaborationStrip(); it.refreshAgentTranscriptWindow(group) }
            val requirement = "Document the observed command output for fixture $token, including numbers 1,2,4,8, their sum and mean, and the observation limitations."
            val criteria = JSONArray().put(JSONObject().put("id", "doc").put("requirement", requirement)
                .put("verification", "documentary").put("evidence_kind", "observed").put("status", "open")
                .put("evidence", JSONArray())).toString()
            fun member(person: CollaborationMember, node: String, stage: String, objective: String,
                       dependencies: Set<String> = emptySet()) = AgentTeamMember(person.agentId,
                if (node == "deliver") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                instanceId = node, role = person.role, objective = objective, dependsOnAgentIds = dependencies,
                context = mapOf("collaboration_group_id" to group, "collaboration_name" to person.name,
                    "collaboration_provider" to person.providerLabel, CollaborationResearchWorkflow.PERSON to person.id,
                    CollaborationResearchWorkflow.STAGE to stage, CollaborationGoalLoop.ENABLED to "1"))
            val definition = AgentTeamDefinition(run, codex.id, listOf(
                member(author, "author", "EXECUTE", "Use the terminal to print fixture token $token " +
                    "and compute the sum and mean of 1,2,4,8. In PowerShell use Write-Output '$token'; Write-Output (1+2+4+8); Write-Output ((1+2+4+8)/4). " +
                    "Avoid nested shells and variable quoting. A failed read-only attempt may be corrected; do not repeat a successful command. " +
                    "Do not inspect repository files, use the web, operate the phone, or write files. " +
                    "Publish one workspace artifact with id=fixture-document and body.content documenting the actual returned output and its limits. " +
                    "This is documentary evidence, not a qualified computational or scientific certification. Do not invent receipt IDs; " +
                    "the host imports Desktop observations after your final reply. Return the research-artifact JSON."),
                member(reviewer, "review", "RECHECK", "Independently review the author's exact saved document from the dependency workspace_receipt. " +
                    "Use the available collaboration_recall tool with mode=evidence to inspect the original recorded Desktop command observation, " +
                    "not just the author's prose. Read the original by evidence_id and sha256 when needed. Check token $token and the numbers. " +
                    "Publish a decision id=fixture-review with body.acceptance_review for criterion_id=doc and exact requirement: $requirement " +
                    "Copy the delivery reference into target and parents; cite the actual host evidence in observations. " +
                    "Use verdict=supported only if the document agrees with the recorded output, otherwise refuted/not_tested with unresolved issues. " +
                    "Do not run another command, browse the web, or operate other apps.", setOf("author")),
                member(author, "deliver", "DELIVER", "Assess only this documentary fixture. Use the exact saved author/review versions " +
                    "in the dependency workspace receipts. If valid, return achieved with the preserved criterion and delivery/review references. " +
                    "No new tools, experiments, members or unrelated work. Do not claim scientific or general team superiority.", setOf("author", "review"))
            ), primaryInstanceId = "deliver", visibilityMode = AgentTeamVisibilityMode.VISIBLE)
            val request = AgentRunRequest(group, turn, turn, runId = run,
                goal = requirement, idempotencyKey = run, context = mapOf(CollaborationGoalLoop.CRITERIA to criteria,
                    CollaborationGoalLoop.ROUND to "1"))
            val publisher = CollaborationTranscriptPublisher(context)
            // Use the real member worker and graph, but a dedicated store so a failed fixture cannot auto-expand later.
            runtime = AgentTeamExecutionRuntime(EncryptedAgentTeamExecutionStore(database), onSnapshot = { snapshot ->
                publisher.publish(snapshot)
                report(snapshot)
            })
            handle = runtime.start(definition, request, ActionExecutorAgentTeamMemberWorker(context))
            val result = withTimeout(12 * 60_000L) { handle.await() }
            report(result.snapshot)
            assertEquals(reportText(result.snapshot), AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
            val authorResult = result.snapshot.members.single { it.memberId == "author" }
            val artifact = requireNotNull(CollaborationResearchArtifact.decode(authorResult.output))
            val imports = artifact.getJSONArray("remote_evidence_import")
            assertTrue("Real remote evidence must be imported", (0 until imports.length()).any {
                imports.getJSONObject(it).optLong("imported_observations") > 0 })
            val access = CollaborationWorkspaceAccess(group, run, turn, 2, "inspect", reviewer.id)
            val ledger = CollaborationEvidenceLedger(context)
            val observations = ledger.browse(access).first.map { ledger.read(access, it.getString("evidence_id"), it.getString("sha256"))!! }
            assertTrue("Actual Codex observation missing", observations.any { it.getString("origin") == "desktop_codex_tool" &&
                it.getString("status") == "returned" && it.getString("output_json").contains(token) })
            val reviewed = requireNotNull(CollaborationResearchArtifact.decode(result.snapshot.members.single { it.memberId == "review" }.output))
            val reviewRef = reviewed.getJSONObject("workspace_receipt").getJSONArray("revisions").getJSONObject(0)
            val review = CollaborationResearchWorkspace(context).read(access, reviewRef.getString("object_id"), reviewRef.getInt("revision"))!!
            assertTrue("Review must reference observed evidence", review.getJSONArray("host_observations").length() > 0)
            assertEquals(reportText(result.snapshot), "achieved", result.snapshot.goalDisposition)
            assertTrue(result.subagentResult.results.single { it.childId == "deliver" }.collaborationAcceptance?.accepted == true)
            scenario.onActivity { it.refreshAgentTranscriptWindow(group) }
            screenshot()
        } finally {
            handle?.let { if (it.isActive) it.cancel("Authorized live fixture finished") }
            runtime?.close()
            if (group.isNotBlank()) {
                CollaborationGroupStore(context).remove(group)
                AgentTranscriptStore(context).deleteConversation(group)
            }
            if (previous.isNotBlank()) AgentTranscriptStore(context).switchConversation(previous)
            database.clear()
            scenario.close()
        }
        Unit
    }

    private fun reportText(snapshot: AgentTeamExecutionSnapshot) = "run=${snapshot.supervisorRunId}\nstate=${snapshot.state}\ndisposition=${snapshot.goalDisposition}\n" +
        snapshot.members.joinToString("\n\n") { "${it.displayName}/${it.memberId}: ${it.status}\n${it.output}\n${it.errorMessage}" }

    private fun report(snapshot: AgentTeamExecutionSnapshot) {
        File(context.getExternalFilesDir(null), "collaboration-live-evidence.txt").writeText(reportText(snapshot))
    }

    private fun screenshot() {
        instrumentation.waitForIdleSync()
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
            try { File(context.getExternalFilesDir(null), "collaboration-live-evidence.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            } } finally { bitmap.recycle() }
        }
    }

    private fun waitUntil(label: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 60_000L
        while (SystemClock.elapsedRealtime() < until) {
            if (condition()) return
            SystemClock.sleep(250)
        }
        fail("Timed out: $label")
    }
}
