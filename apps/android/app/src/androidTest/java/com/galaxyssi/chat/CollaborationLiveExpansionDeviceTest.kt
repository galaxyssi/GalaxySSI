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
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
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

/**
 * Opt in with -e collaborationLiveExpansion true and this class's instrumentation filter.
 * Real paired Codex/MQTT + DeepSeek calls; only the unrelated local gate is synthetic.
 * Uses its own execution database and never starts the automatic goal-loop service.
 * The 12-minute timeout bounds this harness, not the product's planning or goal horizon.
 * Tool restrictions are prompt-only; recorded observations cannot prove a tool-free Desktop history.
 * Cleanup has a separate 90-second stop-acknowledgment bound and retains ownership on failure.
 */
@RunWith(AndroidJUnit4::class)
class CollaborationLiveExpansionDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun realPlannerAppendsIndependentReviewBeforeUnrelatedGateRelease(): Unit = runBlocking {
        assumeTrue("Requires explicit authorization for real providers and MQTT",
            InstrumentationRegistry.getArguments().getString("collaborationLiveExpansion") == "true")
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        val token = UUID.randomUUID().toString()
        val run = "live-expansion-$token"
        val turn = "turn-$token"
        val database = AgentEncryptedDatabase(context, run)
        val store = EncryptedAgentTeamExecutionStore(database)
        val audit = Audit(File(context.getExternalFilesDir(null), "$run.json"), run)
        val gateStarted = CompletableDeferred<Unit>()
        val releaseGate = CompletableDeferred<Unit>()
        val reviewPersisted = CompletableDeferred<Unit>()
        val gateReleasedAt = AtomicLong()
        val plannerReturnedAt = AtomicLong()
        val reviewReturnedAt = AtomicLong()
        val plannedTask = AtomicReference<String>()
        val plannerNode = AtomicReference<String>()
        val plannerOutput = AtomicReference<String>()
        val reviewerNode = AtomicReference<String>()
        val finalStarted = AtomicLong()
        val plannerCalls = AtomicInteger()
        val calls = ConcurrentHashMap<String, Int>()
        var group = ""
        var previous = ""
        var keptScreenOn = false
        var touchedWindow = false
        var runtime: AgentTeamExecutionRuntime? = null
        var handle: AgentTeamExecutionHandle? = null
        var fixtureFailure: Throwable? = null
        try {
            audit.event("tool_policy_scope", JSONObject()
                .put("enforcement", "PROMPT_ONLY_NOT_A_DISPATCH_SANDBOX")
                .put("provider_tool_history_completeness", "NOT_ESTABLISHED")
                .put("assertion_scope", "Reject prohibited recorded observations; no absence guarantee for unrecorded provider tools"))
            waitUntil("activity hydration") {
                var ready = false
                scenario.onActivity { ready = !it.initialAgentHydrationPending &&
                    it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE }
                ready
            }
            scenario.onActivity {
                keptScreenOn = (it.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
                it.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                touchedWindow = true
                previous = it.agentTranscriptStore.activeConversation().id
                it.createAgentConversation()
                group = it.agentTranscriptStore.activeConversation().id
            }
            assertNotEquals("Fixture must not reuse the selected conversation", previous, group)
            AgentTranscriptStore(context).apply {
                append(AgentTranscriptRole.PROCESS, "Opt-in live expansion fixture; synthetic document, real providers",
                    dedupeKey = run, conversationId = group)
                renameConversation(group, "Live expansion fixture")
            }
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
            assertNotEquals(codex.id, deepseek.id)
            val author = CollaborationMember(name = "Turing", agentId = codex.id, providerLabel = codex.title,
                role = "Synthetic document author and incremental coordinator")
            val reviewer = CollaborationMember(name = "Curie", agentId = deepseek.id, providerLabel = deepseek.title,
                role = "Independent read-only documentary reviewer", independentReview = true)
            CollaborationGroupStore(context).update(group) { it.copy(members = listOf(author, reviewer),
                coordinatorId = author.id, workflow = CollaborationWorkflow.RESEARCH) }
            assertEquals(2, CollaborationGroupStore(context).load(group)!!.members.size)
            scenario.onActivity { it.refreshCollaborationStrip(); it.refreshAgentTranscriptWindow(group) }

            val requirement = "Save and independently review a clearly synthetic document for fixture $token, " +
                "containing the supplied values 1,2,4,8 and explicitly stating that no experiment or external source was observed. " +
                "Retain the exact ASCII marker $SYNTHETIC_MARKER verbatim in body.content; do not translate or alter it."
            val criteria = JSONArray().put(JSONObject().put("id", "doc").put("requirement", requirement)
                .put("verification", "documentary").put("evidence_kind", "observed")
                .put("status", "open").put("evidence", JSONArray())).toString()
            val safety = "This is a read-only synthetic-document fixture. No contacts, contact messages, shell commands, " +
                "repository inspection, filesystem writes, web/network tools, device controls, purchases or external uploads. " +
                "Host publication of the requested collaboration workspace JSON is allowed. Do not simulate teammates or invent receipts. "
            val goal = requirement + " " + safety +
                "The initial work IDs are author-document and fixture-only-gate. The latter is an unrelated LOCAL HARNESS " +
                "synchronization gate, not a person, model result or documentary evidence. It must not block a review of the completed author. " +
                "When author-document completes, the incremental coordinator must append exactly one NEW VERIFY task for person " +
                "${reviewer.id}, independent_review=true, depending only on author-document with dependency_policy=success. " +
                "Choose its fresh stable work ID; do not reproduce or modify existing assignments. Its assignment must require " +
                "the real reviewer to use only the read-only collaboration_recall tool, mode=workspace, to fetch the author's exact " +
                "object_id/revision from the dependency workspace_receipt, then publish an acceptance_review for criterion doc " +
                "and the exact preserved requirement, citing the author's version in target and parents and the read receipt in observations. " +
                "The review rationale must discuss token $token, the four supplied values and the synthetic/no-experiment limitation. " +
                "Do not make the new review depend on fixture-only-gate. Once this independent review exists, append no redundant " +
                "or unrelated work at later incremental checkpoints; an empty work array is then appropriate. No recruitment. " +
                "The final coordinator must assess all completed dependencies, including the explicitly local gate, preserve the " +
                "criteria, and distinguish host documentary acceptance from graph execution. Claim achieved only with exact " +
                "saved delivery/review references satisfying the evidence gate; otherwise leave the criterion open and explain the gap."

            fun person(member: CollaborationMember) = AgentTeamMember(member.agentId, AgentDeliveryMode.IGNORE,
                instanceId = member.id, role = member.role, context = mapOf(
                    "collaboration_group_id" to group, "collaboration_name" to member.name,
                    "collaboration_provider" to member.providerLabel,
                    CollaborationResearchWorkflow.PERSON to member.id,
                    CollaborationResearchWorkflow.STAGE to "DELIVER", CollaborationGoalLoop.ENABLED to "1",
                    CollaborationGoalLoop.ROSTER to "true", CollaborationLiveGraph.ENABLED to "1"))
            fun work(member: AgentTeamMember, id: String, assignment: String) = member.copy(instanceId = id,
                deliveryMode = AgentDeliveryMode.OBSERVE, objective = assignment, context = member.context + mapOf(
                    CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to id,
                    CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationWorkGraph.POLICY to "success"))
            val authorPerson = person(author)
            val reviewerPerson = person(reviewer)
            val authorTask = work(authorPerson, AUTHOR, safety + "Use no tools. Author one concise research-artifact JSON " +
                "with exactly one new workspace kind=artifact, id=fixture-document, body.content containing token $token, " +
                "the supplied numbers 1,2,4,8, and a clear statement that these are synthetic inputs, not observed experimental " +
                "results. Retain the exact ASCII marker $SYNTHETIC_MARKER verbatim in body.content; do not translate or alter it. " +
                "Do not claim independent review or achievement. The host saves the document after your response.")
            val gateTask = work(reviewerPerson, GATE, "FIXTURE_ONLY local synchronization gate; no provider invocation or evidence claim.")
            val finalTask = authorPerson.copy(instanceId = FINAL, deliveryMode = AgentDeliveryMode.RESPOND,
                objective = safety + "Use no tools. Assess this fixture using ALL dependency results and saved workspace receipts. " +
                    "The local gate is not verification. Preserve criterion doc and its original requirement. " +
                    "Return a goal-assessment JSON; do not equate successful dispatch with documentary acceptance.",
                dependsOnAgentIds = setOf(AUTHOR, GATE),
                context = authorPerson.context + (CollaborationGoalLoop.ROSTER to "false"))
            // Seed only the authorized starting graph; no fake initial model assessment or pre-created review.
            val definition = AgentTeamDefinition(run, codex.id,
                listOf(authorPerson, reviewerPerson, authorTask, gateTask, finalTask), primaryInstanceId = FINAL,
                visibilityMode = AgentTeamVisibilityMode.VISIBLE)
            val initialIds = definition.members.mapTo(hashSetOf()) { it.memberId }
            val request = AgentRunRequest(group, turn, turn, runId = run, goal = goal, idempotencyKey = run,
                context = mapOf(CollaborationGoalLoop.CRITERIA to criteria, CollaborationGoalLoop.ROUND to "1"))
            val inspect = CollaborationWorkspaceAccess(group, run, turn, 2, "fixture-inspector", reviewer.id)
            val real = ActionExecutorAgentTeamMemberWorker(context)
            val publisher = CollaborationTranscriptPublisher(context)
            val executionRuntime = AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 2), onSnapshot = { snapshot ->
                publisher.publish(snapshot)
                audit.snapshot(snapshot)
                val added = reviewerNode.get()
                if (added != null && snapshot.members.any { it.memberId == added && it.status == AgentSubagentStatus.SUCCEEDED }) {
                    reviewPersisted.complete(Unit)
                }
            })
            runtime = executionRuntime
            val worker = AgentTeamMemberWorker { execution ->
                val member = execution.member
                calls.merge(member.memberId, 1, Int::plus)
                try {
                    when {
                        member.memberId == GATE -> {
                            gateStarted.complete(Unit)
                            audit.event("fixture_gate_held", JSONObject().put("fixture_only", true))
                            execution.suspendExecutionPermit { releaseGate.await() }
                            AgentSubagentOutput(GATE_OUTPUT)
                        }
                        member.memberId == AUTHOR -> {
                            execution.suspendExecutionPermit { gateStarted.await() }
                            val output = real.execute(execution)
                            audit.event("real_author_returned", JSONObject().put("output", output.content))
                            val saved = savedObject(output.content, CollaborationWorkspaceAccess.from(execution), "artifact")
                            assertEquals(author.id, saved.getString("person_id"))
                            val content = saved.getJSONObject("body").getString("content")
                            assertTrue("Author's saved document must carry this run's token", content.contains(token))
                            // A machine-readable marker avoids a locale-specific assertion on the author's prose.
                            assertTrue("The saved document must retain the exact synthetic-input marker", content.contains(SYNTHETIC_MARKER))
                            listOf(1, 2, 4, 8).forEach { value ->
                                assertTrue("Supplied value $value missing from the saved document",
                                    Regex("(?<!\\d)$value(?!\\d)").containsMatchIn(content.replace(token, "")))
                            }
                            output
                        }
                        CollaborationLiveGraph.planner(member) -> {
                            val first = plannerCalls.incrementAndGet() == 1
                            if (first) {
                                assertTrue(gateStarted.isCompleted)
                                assertFalse("Unrelated gate must still be held at planning", releaseGate.isCompleted)
                                assertTrue(execution.handoff.dependencies.any { it.childId == AUTHOR && !it.outputTruncated })
                            }
                            val output = real.execute(execution)
                            audit.event("real_planner_returned", JSONObject().put("node_id", member.memberId)
                                .put("gate_held", !releaseGate.isCompleted).put("raw_output", output.content))
                            val expansion = CollaborationLiveGraph.decode(output.content)
                            val jobs = expansion.getJSONArray("work")
                            if (first) {
                                assertFalse("Actual planner JSON must arrive before release", releaseGate.isCompleted)
                                assertEquals("Fixture requires one genuinely model-planned independent task", 1, jobs.length())
                                val item = jobs.getJSONObject(0)
                                assertTrue(item.getString("id").isNotBlank() && item.getString("id") !in initialIds)
                                assertEquals(reviewer.id, item.getString("member"))
                                assertEquals("VERIFY", item.getString("stage"))
                                assertTrue(item.getBoolean("independent_review"))
                                assertEquals(setOf(AUTHOR), CollaborationWorkGraph.dependencies(item))
                                assertEquals("success", item.optString("dependency_policy", "success"))
                                assertTrue(item.getString("assignment").isNotBlank())
                                val compiled = CollaborationWorkGraph.compile(listOf(item), setOf(AUTHOR), mapOf(AUTHOR to author.id))
                                assertEquals("Actual planner's dependency contract must validate", "", compiled.error)
                                plannedTask.set(item.toString())
                                plannerNode.set(member.memberId)
                                plannerOutput.set(output.content)
                                plannerReturnedAt.set(SystemClock.elapsedRealtime())
                            } else assertEquals("No redundant expansion is needed for this fixture", 0, jobs.length())
                            output // Never repair, inject or rewrite the model's returned plan.
                        }
                        member.memberId == FINAL -> {
                            assertTrue("Final cannot start while the local gate is held", releaseGate.isCompleted)
                            assertTrue("Final cannot bypass the persisted live review", reviewPersisted.isCompleted)
                            val added = requireNotNull(reviewerNode.get())
                            val dependencies = execution.handoff.dependencies.associateBy { it.childId }
                            val expected = store.snapshot(run)!!.members.filter {
                                it.deliveryMode != AgentDeliveryMode.IGNORE && it.memberId != FINAL
                            }.mapTo(hashSetOf()) { it.memberId }
                            assertEquals("Final must receive every persisted executable node, including later planners", expected, dependencies.keys)
                            assertTrue(dependencies.keys.containsAll(setOf(AUTHOR, GATE, added, requireNotNull(plannerNode.get()))))
                            assertFalse("Final handoff must retain all dependency evidence", execution.handoff.truncated)
                            assertEquals(GATE_OUTPUT, dependencies.getValue(GATE).output)
                            listOf(AUTHOR, added).forEach {
                                assertEquals(AgentSubagentStatus.SUCCEEDED, dependencies.getValue(it).status)
                                assertFalse(dependencies.getValue(it).outputTruncated)
                            }
                            finalStarted.set(SystemClock.elapsedRealtime())
                            audit.event("real_final_handoff", JSONObject().put("dependency_nodes", JSONArray(dependencies.keys.toList())))
                            real.execute(execution).also { audit.event("real_final_returned", JSONObject().put("output", it.content)
                                .put("host_acceptance", it.collaborationAcceptance?.encode() ?: JSONObject.NULL)) }
                        }
                        else -> {
                            val item = JSONObject(requireNotNull(plannedTask.get()) { "No real planner proposal was captured" })
                            assertEquals(item.getString("id"), member.context[CollaborationGoalLoop.WORK_ID])
                            assertEquals(item.getString("assignment"), member.objective)
                            assertEquals(reviewer.agentId, member.agentId)
                            assertEquals(reviewer.id, member.context[CollaborationResearchWorkflow.PERSON])
                            assertEquals("true", member.context[CollaborationWorkGraph.INDEPENDENT])
                            assertEquals(setOf(AUTHOR), member.dependsOnAgentIds)
                            assertFalse(initialIds.contains(member.memberId))
                            assertFalse("Reviewer must execute before unrelated work is released", releaseGate.isCompleted)
                            // Reopen the real encrypted store; an in-memory proposal alone is insufficient.
                            val persisted = requireNotNull(EncryptedAgentTeamExecutionStore(database).snapshot(run))
                            assertTrue(persisted.members.any { it.memberId == member.memberId && it.objective == item.getString("assignment") })
                            val planner = persisted.members.single { it.memberId == plannerNode.get() }
                            assertEquals(AgentSubagentStatus.SUCCEEDED, planner.status)
                            assertEquals(plannerOutput.get(), planner.output)
                            val dependency = execution.handoff.dependencies.single()
                            assertEquals(AUTHOR, dependency.childId)
                            assertEquals(AgentSubagentStatus.SUCCEEDED, dependency.status)
                            assertFalse(dependency.outputTruncated)
                            val delivery = savedObject(dependency.output, CollaborationWorkspaceAccess.from(execution), "artifact")
                            reviewerNode.set(member.memberId)
                            audit.event("persisted_reviewer_dispatched", JSONObject().put("node_id", member.memberId)
                                .put("planned_work_id", item.getString("id")).put("author_object", reference(delivery)))
                            val output = real.execute(execution)
                            audit.event("real_reviewer_returned", JSONObject().put("output", output.content))
                            assertFalse("Gate remains held for the entire real review", releaseGate.isCompleted)
                            val reviewed = savedObject(output.content, CollaborationWorkspaceAccess.from(execution), "acceptance_review")
                            assertEquals(reviewer.id, reviewed.getString("person_id"))
                            val check = reviewed.getJSONObject("body").getJSONObject("acceptance_review")
                            assertEquals("doc", check.getString("criterion_id"))
                            assertEquals(requirement, check.getString("requirement"))
                            assertReference(delivery, check.getJSONObject("target"))
                            val parents = reviewed.getJSONArray("parents")
                            val sourceParent = (0 until parents.length()).map { parents.getJSONObject(it) }.firstOrNull {
                                it.getString("object_id") == delivery.getString("object_id") &&
                                    it.getInt("revision") == delivery.getInt("revision")
                            }
                            assertNotNull("Saved review must link the exact author revision in parents", sourceParent)
                            val parent = requireNotNull(sourceParent)
                            // Parent links use object ID/revision; resolve that immutable version to verify its digest.
                            val parentRevision = requireNotNull(CollaborationResearchWorkspace(context).read(
                                CollaborationWorkspaceAccess.from(execution), parent.getString("object_id"), parent.getInt("revision")))
                            assertReference(delivery, reference(parentRevision))
                            if (parent.has("sha256")) assertEquals(delivery.getString("sha256"), parent.getString("sha256"))
                            assertTrue(check.getString("rationale").contains(token))
                            val observations = observations(inspect)
                            assertRecordedToolPolicy(observations, reviewer.id, member.memberId)
                            val reads = observations.filter { observed ->
                                val input = JSONObject(observed.getString("input_json"))
                                observed.getString("run_id") == run && observed.getString("turn_id") == turn &&
                                    observed.getString("person_id") == reviewer.id && observed.getString("node_id") == member.memberId &&
                                    observed.getString("tool") == CollaborationCloudRecall.NAME && observed.getString("status") == "returned" &&
                                    input.optString("mode") == "workspace" && input.optString("object_id") == delivery.getString("object_id") &&
                                    input.optInt("revision") == delivery.getInt("revision") && observed.getString("output_json").contains(token)
                            }
                            assertTrue("Real reviewer must fetch the exact author document, not merely claim to have read it", reads.isNotEmpty())
                            val hostObservations = reviewed.getJSONArray("host_observations")
                            val linkedReads = (0 until hostObservations.length()).map { hostObservations.getJSONObject(it) }.filter { ref ->
                                reads.any { read -> read.getString("evidence_id") == ref.getString("evidence_id") &&
                                    read.getString("sha256") == ref.getString("sha256") }
                            }
                            assertTrue("Saved review must cite the exact ID and digest of its real author-document read", linkedReads.isNotEmpty())
                            linkedReads.forEach { ref ->
                                assertEquals(reviewer.id, ref.getString("person_id"))
                                assertEquals(member.memberId, ref.getString("node_id"))
                            }
                            audit.event("reviewer_observed_author", JSONObject().put("read_receipts", JSONArray(reads))
                                .put("review_parents", parents).put("linked_host_observations", JSONArray(linkedReads))
                                .put("review_object", reference(reviewed)).put("gate_held", true))
                            reviewReturnedAt.set(SystemClock.elapsedRealtime())
                            output
                        }
                    }
                } catch (failure: Throwable) {
                    reviewPersisted.completeExceptionally(failure)
                    audit.event("worker_failure", JSONObject().put("node_id", member.memberId).put("error", failure.toString()))
                    throw failure
                }
            }
            withTimeout(12 * 60_000L) {
                val active = executionRuntime.start(definition, request, worker)
                handle = active
                reviewPersisted.await()
                assertTrue(plannerReturnedAt.get() > 0 && reviewReturnedAt.get() >= plannerReturnedAt.get())
                assertFalse(releaseGate.isCompleted)
                assertEquals("Final must not start before explicit gate release", 0L, finalStarted.get())
                assertEquals(AgentSubagentStatus.RUNNING, store.snapshot(run)!!.members.single { it.memberId == GATE }.status)
                gateReleasedAt.set(SystemClock.elapsedRealtime())
                audit.event("fixture_gate_released", JSONObject().put("fixture_only", true))
                releaseGate.complete(Unit)
                val result = active.await()
                audit.snapshot(result.snapshot)
                assertEquals("Graph execution is distinct from documentary acceptance; inspect $run.json",
                    AgentSubagentRunStatus.SUCCEEDED, result.subagentResult.status)
                assertTrue(finalStarted.get() >= gateReleasedAt.get())
                assertTrue(plannerReturnedAt.get() <= gateReleasedAt.get() && reviewReturnedAt.get() <= gateReleasedAt.get())
                assertEquals(1, calls[AUTHOR] ?: 0)
                assertEquals(1, calls[GATE] ?: 0)
                assertEquals(1, calls[requireNotNull(reviewerNode.get())] ?: 0)
                assertEquals(1, calls[FINAL] ?: 0)
                val finalResult = result.subagentResult.results.single { it.childId == FINAL }
                assertFalse(finalResult.outputTruncated)
                val assessment = requireNotNull(CollaborationGoalLoop.decode(finalResult.output)) { "Real coordinator returned invalid assessment" }
                val receipt = finalResult.collaborationAcceptance
                val accepted = receipt?.let { it.accepted && it.matches(finalResult.output, criteria, goal, run, turn, FINAL) } == true
                audit.event("outcome", JSONObject().put("graph_runtime_success", true)
                    .put("documentary_accepted", accepted).put("model_decision", assessment.getString("decision"))
                    .put("goal_disposition", result.snapshot.goalDisposition)
                    .put("host_acceptance", receipt?.encode() ?: JSONObject.NULL)
                    .put("planner_returned_at_elapsed_ms", plannerReturnedAt.get())
                    .put("review_returned_at_elapsed_ms", reviewReturnedAt.get())
                    .put("gate_released_at_elapsed_ms", gateReleasedAt.get()))
                assertTrue("Goal achievement requires the matching host evidence receipt, not merely successful graph execution",
                    result.snapshot.goalDisposition != "achieved" || accepted)
                assertRecordedToolPolicy(observations(inspect), reviewer.id, requireNotNull(reviewerNode.get()))
            }
        } catch (failure: Throwable) {
            fixtureFailure = failure
            audit.event("fixture_failed", JSONObject().put("error", failure.toString()))
            throw failure
        } finally {
            withContext(NonCancellable) {
                var cleanupFailure: Throwable? = null
                var fixtureDataRemoved = false
                fun remember(failure: Throwable) {
                    val prior = cleanupFailure
                    if (prior == null) cleanupFailure = failure else prior.addSuppressed(failure)
                }
                try {
                    check(stopFixture(run, group, store, handle, releaseGate, audit)) {
                        "Fixture stop was not acknowledged within 90 seconds; retained execution database $run, " +
                            "conversation $group, durable STOP and managed response ownership. Inspect $run.json."
                    }
                    runtime?.close()
                    if (group.isNotBlank()) {
                        CollaborationGroupStore(context).remove(group)
                        AgentTranscriptStore(context).deleteConversation(group)
                    }
                    database.clear()
                    fixtureDataRemoved = true
                } catch (failure: Throwable) {
                    remember(failure)
                } finally {
                    // Closing the local runtime never substitutes for a remote terminal acknowledgment.
                    runCatching { runtime?.close() }.exceptionOrNull()?.let(::remember)
                    releaseGate.complete(Unit)
                    runCatching {
                        if (previous.isNotBlank()) {
                            AgentTranscriptStore(context).switchConversation(previous)
                            scenario.onActivity {
                                it.agentTranscriptStore.switchConversation(previous)
                                it.refreshCollaborationStrip()
                                it.refreshAgentTranscriptWindow(previous)
                            }
                        }
                    }.exceptionOrNull()?.let(::remember)
                    runCatching {
                        if (touchedWindow && !keptScreenOn) scenario.onActivity {
                            it.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }.exceptionOrNull()?.let(::remember)
                    runCatching { scenario.close() }.exceptionOrNull()?.let(::remember)
                }
                cleanupFailure?.let { failure ->
                    runCatching {
                        audit.event("fixture_cleanup_failed", JSONObject().put("error", failure.toString())
                            .put("execution_database", run).put("conversation_id", group)
                            .put("fixture_data_removed", fixtureDataRemoved)
                            .put("managed_response_ownership_removed", false))
                    }.exceptionOrNull()?.let(failure::addSuppressed)
                    val original = fixtureFailure
                    if (original == null) throw failure else original.addSuppressed(failure)
                }
            }
        }
        audit.event("fixture_passed", JSONObject().put("scope", "live expansion, persistence, exact review evidence links, recorded-tool audit and final handoff")
            .put("fixture_cleanup_completed", true).put("read_only_enforcement_verified", false))
    }

    private suspend fun stopFixture(
        run: String,
        group: String,
        store: AgentTeamExecutionStore,
        handle: AgentTeamExecutionHandle?,
        releaseGate: CompletableDeferred<Unit>,
        audit: Audit
    ): Boolean {
        val controls = AgentTeamDurableControl(context)
        controls.set(run, AgentTeamUserControl.STOP)
        check(controls.get(run) == AgentTeamUserControl.STOP)
        handle?.cancel("Authorized live expansion fixture finished; durable STOP requested")
        releaseGate.complete(Unit)
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val recovery = AgentTeamRemoteStopRecovery(context)
        val acknowledged = withTimeoutOrNull(90_000L) {
            var settled: Boolean
            do {
                val snapshot = store.snapshot(run)
                if (snapshot != null) {
                    recovery.reconcile(listOf(snapshot), ledger) { id ->
                        id == run && controls.get(id) == AgentTeamUserControl.STOP
                    }
                }
                val localFinished = handle?.let { !it.isActive } ?: (snapshot == null)
                settled = localFinished && ledger.pendingForSupervisor(run).isEmpty()
                if (!settled) delay(250L)
            } while (!settled)
            true
        } == true
        val snapshot = store.snapshot(run)
        snapshot?.let(audit::snapshot)
        val pending = ledger.pendingForSupervisor(run)
        audit.event("fixture_stop_recovery", JSONObject().put("acknowledged", acknowledged)
            .put("durable_control", controls.get(run).name)
            .put("local_finished", handle?.let { !it.isActive } ?: (snapshot == null))
            .put("execution_database", run).put("conversation_id", group)
            .put("retained_for_recovery", !acknowledged)
            .put("pending_remote_owners", JSONArray(pending.map { record ->
                JSONObject().put("owner_run_id", record.ownerRunId).put("supervisor_run_id", record.supervisorRunId)
                    .put("source_message_id", record.sourceMessageId).put("contact_id", record.contactId)
                    .put("conversation_id", record.conversationId).put("turn_id", record.turnId).put("task_id", record.taskId)
                    .put("production_stop_scope_valid", snapshot?.let { AgentTeamRemoteStopPolicy.owns(it, record) } == true)
            })))
        return acknowledged
    }

    private fun savedObject(raw: String, access: CollaborationWorkspaceAccess, kind: String): JSONObject {
        val artifact = requireNotNull(CollaborationResearchArtifact.decode(raw)) { "Missing real structured artifact" }
        assertFalse("Unstructured provider output is not a validated artifact", artifact.optBoolean("unstructured"))
        val receipt = artifact.getJSONObject("workspace_receipt")
        assertEquals("recorded", receipt.getString("status"))
        val refs = receipt.getJSONArray("revisions")
        assertEquals("Fixture expects one exact saved object", 1, refs.length())
        val ref = refs.getJSONObject(0)
        val saved = requireNotNull(CollaborationResearchWorkspace(context).read(access, ref.getString("object_id"), ref.getInt("revision")))
        assertEquals(kind, saved.getString("kind"))
        assertReference(saved, ref)
        return saved
    }

    private fun reference(saved: JSONObject) = JSONObject().put("object_id", saved.getString("object_id"))
        .put("revision", saved.getInt("revision")).put("sha256", saved.getString("sha256"))

    private fun assertReference(saved: JSONObject, ref: JSONObject) {
        listOf("object_id", "revision", "sha256").forEach { assertEquals("Exact version reference: $it", saved.get(it), ref.get(it)) }
    }

    private fun observations(access: CollaborationWorkspaceAccess): List<JSONObject> {
        val ledger = CollaborationEvidenceLedger(context)
        val result = mutableListOf<JSONObject>()
        var cursor = ""
        do {
            val page = ledger.browse(access, cursor)
            result += page.first.map { requireNotNull(ledger.read(access, it.getString("evidence_id"), it.getString("sha256"))) }
            cursor = page.second ?: ""
        } while (cursor.isNotBlank())
        return result
    }

    private fun assertRecordedToolPolicy(observations: List<JSONObject>, reviewer: String, reviewNode: String) {
        assertTrue("Recorded tools must be reviewer-scoped recall; this does not establish absence of unrecorded provider tools",
            observations.all { it.getString("tool") == CollaborationCloudRecall.NAME &&
                it.getString("person_id") == reviewer && it.getString("node_id") == reviewNode })
    }

    private fun waitUntil(label: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 60_000L
        while (SystemClock.elapsedRealtime() < until) {
            if (condition()) return
            SystemClock.sleep(250)
        }
        fail("Timed out: $label")
    }

    private class Audit(private val file: File, run: String) {
        private val data = JSONObject().put("run_id", run).put("fixture", "real-provider-live-expansion")
            .put("fixture_status", "IN_PROGRESS")
            .put("gate_evidence_kind", "FIXTURE_ONLY_LOCAL_SYNCHRONIZATION_NOT_ACCEPTANCE")
            .put("graph_runtime_success", "UNVERIFIED").put("documentary_accepted", "UNVERIFIED")
            .put("events", JSONArray())

        @Synchronized fun event(kind: String, details: JSONObject) {
            data.getJSONArray("events").put(JSONObject().put("kind", kind)
                .put("elapsed_ms", SystemClock.elapsedRealtime()).put("details", details))
            if (kind == "outcome") {
                data.put("graph_runtime_success", details.getBoolean("graph_runtime_success"))
                data.put("documentary_accepted", details.getBoolean("documentary_accepted"))
            }
            if (kind == "fixture_passed") data.put("fixture_status", "PASSED")
            if (kind == "fixture_failed" || kind == "fixture_cleanup_failed") data.put("fixture_status", "FAILED")
            file.writeText(data.toString(2))
        }

        @Synchronized fun snapshot(snapshot: AgentTeamExecutionSnapshot) {
            data.put("snapshot", JSONObject().put("state", snapshot.state.name).put("goal_disposition", snapshot.goalDisposition)
                .put("members", JSONArray(snapshot.members.map { member -> JSONObject().put("node_id", member.memberId)
                    .put("person_id", member.personId).put("status", member.status.name)
                    .put("output", member.output).put("error", member.errorMessage) })))
            file.writeText(data.toString(2))
        }
    }

    companion object {
        private const val SYNTHETIC_MARKER = "SYNTHETIC_INPUTS_NO_EXPERIMENT_NO_EXTERNAL_SOURCE"
        private const val AUTHOR = "author-document"
        private const val GATE = "fixture-only-gate"
        private const val FINAL = "final-coordinator"
        private const val GATE_OUTPUT = "FIXTURE_ONLY: local synchronization gate released; no model output, tool observation or documentary acceptance."
    }
}
