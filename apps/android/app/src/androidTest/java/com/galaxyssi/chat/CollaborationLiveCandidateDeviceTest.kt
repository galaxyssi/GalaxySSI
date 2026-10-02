package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import android.view.WindowManager
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in negative-control fixture. Real providers; the unrelated gate is local, not evidence. */
@RunWith(AndroidJUnit4::class)
class CollaborationLiveCandidateDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun realCandidatesAreChallengedRepairedAndRechecked(): Unit = runBlocking {
        assumeTrue("Requires authorization for real Codex and DeepSeek calls",
            InstrumentationRegistry.getArguments().getString("collaborationLiveCandidates") == "true")
        val token = UUID.randomUUID().toString()
        val run = "live-candidates-$token"
        val turn = "turn-$token"
        val database = AgentEncryptedDatabase(context, run)
        val store = EncryptedAgentTeamExecutionStore(database, candidateWorkspace = { CollaborationResearchWorkspace(context) })
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        val gateStarted = CompletableDeferred<Unit>()
        val releaseGate = CompletableDeferred<Unit>()
        val revisedAndReviewed = CompletableDeferred<Unit>()
        val calls = ConcurrentHashMap<String, Int>()
        val operations = ConcurrentHashMap<String, JSONObject>()
        val audit = JSONObject().put("run", run).put("fixture_token", token)
            .put("tool_policy", "prompt_only_not_a_sandbox").put("scientific_validation", false)
            .put("multi_agent_advantage_measured", false)
        val reportFile = File(context.getExternalFilesDir(null), "$run.json")
        val started = SystemClock.elapsedRealtime()
        var group = ""
        var previous = ""
        var keepScreen = false
        var windowChanged = false
        var runtime: AgentTeamExecutionRuntime? = null
        var handle: AgentTeamExecutionHandle? = null
        var failure: Throwable? = null
        fun report(snapshot: AgentTeamExecutionSnapshot? = null) = synchronized(audit) {
            audit.put("elapsed_ms", SystemClock.elapsedRealtime() - started)
            audit.put("calls", JSONObject(calls.toMap())).put("candidate_outputs", JSONArray(operations.values.toList()))
            snapshot?.let {
                audit.put("state", it.state.name).put("goal_disposition", it.goalDisposition)
                audit.put("members", JSONArray(it.members.map { member -> JSONObject()
                    .put("id", member.memberId).put("status", member.status.name)
                    .put("output", member.output).put("error", member.errorMessage) }))
            }
            reportFile.writeText(audit.toString())
        }
        try {
            waitUntil("activity hydration") {
                var ready = false
                scenario.onActivity { ready = !it.initialAgentHydrationPending &&
                    it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE }
                ready
            }
            scenario.onActivity {
                keepScreen = it.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0
                it.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                windowChanged = true
                previous = it.agentTranscriptStore.activeConversation().id
                it.createAgentConversation()
                group = it.agentTranscriptStore.activeConversation().id
            }
            assertNotEquals(previous, group)
            AgentTranscriptStore(context).apply {
                append(AgentTranscriptRole.PROCESS, "Real candidate negative-control fixture", dedupeKey = run, conversationId = group)
                renameConversation(group, "Candidate repair acceptance")
            }
            waitUntil("secure MQTT") { GalaxySSIMqttClient.isConnected() && GalaxySSIMqttClient.isSecureReady() }
            assertTrue(GalaxySSIMqttClient.requestCapabilityManifestRefresh(force = true))
            var targets = emptyList<AgentCallableTarget>()
            waitUntil("paired Codex and DeepSeek") {
                targets = AppStoreAgentConnectorRegistry(context).availableTargets().filter { it.status == AgentConnectorStatus.AVAILABLE }
                targets.any { it.id.contains("codex", true) && ':' in it.id } &&
                    targets.any { it.id.contains("deepseek", true) || it.title.contains("deepseek", true) }
            }
            val codex = targets.first { it.id.contains("codex", true) && ':' in it.id }
            val deepseek = targets.first { it.id.contains("deepseek", true) || it.title.contains("deepseek", true) }
            val author = CollaborationMember(name = "Turing", agentId = codex.id, providerLabel = codex.title, role = "Author and coordinator")
            val reviewer = CollaborationMember(name = "Curie", agentId = deepseek.id, providerLabel = deepseek.title,
                role = "Independent source reviewer", independentReview = true)
            val editor = CollaborationMember(name = "Hopper", agentId = deepseek.id, providerLabel = deepseek.title, role = "Document repair editor")
            val people = listOf(author, reviewer, editor)
            CollaborationGroupStore(context).update(group) { it.copy(members = people, coordinatorId = author.id,
                workflow = CollaborationWorkflow.RESEARCH) }
            scenario.onActivity { it.refreshCollaborationStrip(); it.refreshAgentTranscriptWindow(group) }
            val requirement = "The candidate document for fixture $token must accurately record the observed sum and mean of 1,2,4,8 and state that this is synthetic documentary evidence, not scientific validation."
            val criterion = JSONObject().put("id", "accuracy").put("requirement", requirement)
                .put("verification", "documentary").put("status", "open").put("evidence_kind", "observed").put("evidence", JSONArray())
                .put("required_observations", JSONArray().put(JSONObject().put("origin", "desktop_codex_tool").put("tool", "codex.commandExecution")))
            val safety = "Only this synthetic fixture is authorized. No contacts, doors, device controls, repository inspection, external web or file writes. " +
                "The author may run the single specified read-only arithmetic command. Other members may only use scoped collaboration recall. " +
                "Do not repeat a successful command, invent receipts, simulate teammates or claim scientific verification. "
            val goal = "$requirement $safety Keep two distinct candidates. One is an explicitly supplied negative control with sum=16 and mean=4; " +
                "it must be repaired to the actual observation without deleting its original revision. The other starts with the correct observed values and must remain unchanged. " +
                "Every candidate body.content uses the literal fields sum=<number> and mean=<number> for its current proposed values. " +
                "At the first incremental checkpoint after producer succeeds, enroll BOTH exact saved candidates through candidate_cycles, criterion_id=accuracy, " +
                "editor=${editor.id}, reviewer=${reviewer.id}, producer_work_ids=[\"producer\"]. Use their exact workspace_receipt references, not guessed IDs/hashes. " +
                "work=[]; no recruitment or additional tasks. Later checkpoints return no new cycles or redundant work. " +
                "The unrelated fixture-only gate is local harness synchronization, not evidence; never depend on it for candidate work. " +
                "The program schedules review, correction when refuted, then independent recheck. Read exact candidate originals AND original Desktop observations. " +
                "Final assessment must distinguish these member reviews from host goal acceptance; do not claim achieved without qualified acceptance and semantic coverage."
            fun person(p: CollaborationMember) = AgentTeamMember(p.agentId, AgentDeliveryMode.IGNORE, instanceId = p.id,
                role = p.role, context = mapOf("collaboration_group_id" to group, "collaboration_name" to p.name,
                    "collaboration_provider" to p.providerLabel, CollaborationResearchWorkflow.PERSON to p.id,
                    CollaborationResearchWorkflow.STAGE to "DELIVER", CollaborationGoalLoop.ENABLED to "1",
                    CollaborationGoalLoop.ROSTER to "true", CollaborationLiveGraph.ENABLED to "1",
                    CollaborationTeamOrganization.ENABLED to "1"))
            val roster = people.map(::person)
            fun work(p: AgentTeamMember, id: String, assignment: String) = p.copy(instanceId = id,
                deliveryMode = AgentDeliveryMode.OBSERVE, objective = assignment, context = p.context + mapOf(
                    CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to id,
                    CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationWorkGraph.POLICY to "success"))
            val producer = work(roster[0], "producer", safety + "Run exactly this PowerShell command once successfully: " +
                "Write-Output '$token'; Write-Output (1+2+4+8); Write-Output ((1+2+4+8)/4). " +
                "Publish exactly two workspace kind=candidate proposals with IDs candidate-a and candidate-b. " +
                "Both body.content values must retain token $token and SYNTHETIC_DOCUMENTARY_NOT_SCIENTIFIC. " +
                "For candidate-a, deliberately state sum=16 and mean=4 as this authorized negative-control test input; do not present it as verified. " +
                "For candidate-b, document the actual returned sum and mean. body.candidate.criteria must contain the exact criterion requirement: $requirement " +
                "Set body.candidate.operation=propose; no parents, no invented observations. The host imports original tool observations after your response.")
            val gate = work(roster[2], "gate", "Local harness gate only; no model call or evidence.")
            val final = roster[0].copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
                objective = safety + "Use supplied dependencies only, no tools. Briefly assess preserved alternatives, correction and recheck. " +
                    "Return goal-assessment JSON. These candidate reviews alone are NOT host acceptance or semantic coverage; " +
                    "keep the original criterion open with decision=continue and no new work in this isolated test run.",
                dependsOnAgentIds = setOf("producer", "gate"), context = roster[0].context + (CollaborationGoalLoop.ROSTER to "false"))
            val definition = AgentTeamDefinition(run, codex.id, roster + listOf(producer, gate, final), primaryInstanceId = "final")
            val request = AgentRunRequest(group, turn, turn, runId = run, goal = goal, idempotencyKey = run,
                context = mapOf(CollaborationGoalLoop.CRITERIA to JSONArray().put(criterion).toString(), CollaborationGoalLoop.ROUND to "1"))
            val workspace = CollaborationResearchWorkspace(context)
            val inspect = CollaborationWorkspaceAccess(group, run, turn, 2, "fixture-inspector", reviewer.id)
            val originals = ConcurrentHashMap<String, JSONObject>()
            val real = ActionExecutorAgentTeamMemberWorker(context)
            val publisher = CollaborationTranscriptPublisher(context)
            runtime = AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 2), onSnapshot = { snapshot ->
                publisher.publish(snapshot)
                report(snapshot)
                if (operations.size == 4 && operations.keys.all { id ->
                        snapshot.members.any { it.memberId == id && it.status == AgentSubagentStatus.SUCCEEDED } }) revisedAndReviewed.complete(Unit)
            })
            handle = runtime.start(definition, request) { execution ->
                val member = execution.member
                calls.merge(member.memberId, 1, Int::plus)
                when {
                    member.memberId == "gate" -> {
                        gateStarted.complete(Unit)
                        execution.suspendExecutionPermit { releaseGate.await() }
                        AgentSubagentOutput("LOCAL_HARNESS_GATE_RELEASED_NOT_EVIDENCE")
                    }
                    else -> {
                        if (member.memberId == "producer") execution.suspendExecutionPermit { gateStarted.await() }
                        val task = member.context[CollaborationCandidateEvolution.TASK]?.let(::JSONObject)
                        if (task != null) {
                            assertFalse("Candidate work must not wait for unrelated work", releaseGate.isCompleted)
                            assertTrue(EncryptedAgentTeamExecutionStore(database).snapshot(run)!!.members.any { it.memberId == member.memberId })
                        }
                        val output = real.execute(execution) // Preserve every provider's actual output unchanged.
                        workspace.publicationCheckpoint(CollaborationWorkspaceAccess.from(execution))?.let { checkpoint ->
                            synchronized(audit) {
                                val attempts = audit.optJSONObject("publication_attempts") ?: JSONObject().also { audit.put("publication_attempts", it) }
                                attempts.put(member.memberId, JSONObject().put("sequence", checkpoint.getLong("sequence"))
                                    .put("status", checkpoint.getJSONObject("receipt").getString("status")))
                            }
                        }
                        if (member.memberId == "producer" || task != null) {
                            val artifact = requireNotNull(CollaborationResearchArtifact.decode(output.content))
                            val receipt = artifact.getJSONObject("workspace_receipt")
                            assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
                            val refs = receipt.getJSONArray("revisions")
                            if (task == null) {
                                assertEquals(2, refs.length())
                                repeat(2) { index ->
                                    val ref = refs.getJSONObject(index)
                                    val saved = requireNotNull(workspace.read(inspect, ref.getString("object_id"), ref.getInt("revision")))
                                    originals[saved.getString("object_id")] = saved
                                }
                            } else {
                                assertEquals(1, refs.length())
                                val ref = refs.getJSONObject(0)
                                val saved = requireNotNull(workspace.read(inspect, ref.getString("object_id"), ref.getInt("revision")))
                                operations[member.memberId] = saved
                            }
                        }
                        output
                    }
                }
            }
            withTimeout(15 * 60_000L) {
                while (!revisedAndReviewed.isCompleted) {
                    val snapshot = store.snapshot(run)
                    val failed = snapshot?.members?.filter { it.status in setOf(AgentSubagentStatus.FAILED, AgentSubagentStatus.CANCELLED) }.orEmpty()
                    check(failed.isEmpty()) { "Real member failed: ${failed.joinToString { "${it.memberId}: ${it.errorMessage}" }}" }
                    check(handle.isActive) { "Real graph ended before the candidate correction and recheck" }
                    delay(500)
                }
                assertEquals(1, operations.values.count { it.getString("kind") == "candidate" })
                val events = operations.values.filter { it.getString("kind") == "candidate_event" }
                assertEquals(3, events.size)
                assertEquals(1, events.count { it.getJSONObject("body").getJSONObject("candidate_event").getString("outcome") == "refuted" })
                assertEquals(2, events.count { it.getJSONObject("body").getJSONObject("candidate_event").getString("outcome") == "supported" })
                val repair = operations.values.single { it.getString("kind") == "candidate" }
                val original = originals.getValue(repair.getString("object_id"))
                assertEquals(2, repair.getInt("revision"))
                assertEquals(original.getString("sha256"), repair.getString("previous_sha256"))
                assertEquals(editor.id, repair.getString("person_id"))
                val corrected = repair.getJSONObject("body").getString("content")
                assertTrue("Repair must actually correct the sum", Regex("sum\\s*=\\s*15(?![\\d.])").containsMatchIn(corrected))
                assertTrue("Repair must actually correct the mean", Regex("mean\\s*=\\s*3\\.75(?!\\d)").containsMatchIn(corrected))
                assertEquals(original.toString(), workspace.read(inspect, original.getString("object_id"), 1)!!.toString())
                val untouched = originals.values.single { it.getString("object_id") != repair.getString("object_id") }
                assertNull("Correct alternative must not be overwritten", workspace.read(inspect, untouched.getString("object_id"), 2))
                assertEquals(untouched.toString(), workspace.read(inspect, untouched.getString("object_id"), 1)!!.toString())
                val ledger = CollaborationEvidenceLedger(context)
                val observations = mutableListOf<JSONObject>()
                var cursor: String? = ""
                do {
                    val page = ledger.browse(inspect, cursor.orEmpty())
                    observations += page.first.map { ledger.read(inspect, it.getString("evidence_id"), it.getString("sha256"))!! }
                    cursor = page.second
                } while (cursor != null)
                val sourceIds = observations.filter { it.getString("origin") == "desktop_codex_tool" &&
                    it.getString("tool") == "codex.commandExecution" && it.getString("status") == "returned" &&
                    it.getString("output_json").contains(token) }.map { it.getString("evidence_id") }.toSet()
                assertTrue("Actual command observation required", sourceIds.isNotEmpty())
                events.forEach { event ->
                    assertEquals(reviewer.id, event.getString("person_id"))
                    val refs = event.getJSONArray("host_observations")
                    assertTrue("Review must cite original Desktop output", (0 until refs.length()).any { refs.getJSONObject(it).getString("evidence_id") in sourceIds })
                    assertTrue("Each review must fetch original evidence itself", observations.any { observation ->
                        val input = JSONObject(observation.getString("input_json"))
                        observation.getString("node_id") == event.getString("node_id") &&
                            observation.getString("tool") == CollaborationCloudRecall.NAME && input.optString("mode") == "evidence" &&
                            input.optString("evidence_id") in sourceIds && observation.getString("output_json").contains(token)
                    })
                }
                releaseGate.complete(Unit)
                val result = handle.await()
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.subagentResult.status)
                assertNotEquals("Candidate reviews must not be promoted to goal acceptance", "achieved", result.snapshot.goalDisposition)
                assertTrue("No successful model work should replay", calls.values.all { it == 1 })
                synchronized(audit) { audit.put("candidate_cycle_verified", true).put("original_evidence_count", sourceIds.size) }
                report(result.snapshot)
            }
        } catch (error: Throwable) {
            failure = error
            synchronized(audit) { audit.put("failure", error.toString()) }
            throw error
        } finally {
            withContext(NonCancellable) {
                val cleanup = runCatching {
                    val controls = AgentTeamDurableControl(context)
                    controls.set(run, AgentTeamUserControl.STOP)
                    handle?.cancel("Authorized fixture finished; durable STOP")
                    releaseGate.complete(Unit)
                    val ledger = EncryptedAgentManagedResponseLedger(context)
                    val recovery = AgentTeamRemoteStopRecovery(context)
                    val acknowledged = withTimeoutOrNull(90_000L) {
                        while (true) {
                            store.snapshot(run)?.let { recovery.reconcile(listOf(it), ledger) { id ->
                                id == run && controls.get(id) == AgentTeamUserControl.STOP } }
                            if (handle?.isActive != true && ledger.pendingForSupervisor(run).isEmpty()) break
                            delay(250)
                        }
                        true
                    } == true
                    synchronized(audit) { audit.put("stop_acknowledged", acknowledged).put("retained_for_recovery", !acknowledged) }
                    report(store.snapshot(run))
                    check(acknowledged) { "Retained fixture $run / $group for remote STOP recovery" }
                    runtime?.close()
                    if (group.isNotBlank()) {
                        CollaborationGroupStore(context).remove(group)
                        AgentTranscriptStore(context).deleteConversation(group)
                    }
                    database.clear()
                }.exceptionOrNull()
                runtime?.close()
                if (previous.isNotBlank()) scenario.onActivity {
                    it.agentTranscriptStore.switchConversation(previous)
                    it.refreshCollaborationStrip(); it.refreshAgentTranscriptWindow(previous)
                }
                if (windowChanged && !keepScreen) scenario.onActivity { it.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
                scenario.close()
                cleanup?.let { if (failure == null) throw it else failure!!.addSuppressed(it) }
            }
        }
    }

    private fun waitUntil(label: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 60_000
        while (SystemClock.elapsedRealtime() < until) {
            if (condition()) return
            SystemClock.sleep(250)
        }
        fail("Timed out: $label")
    }
}
