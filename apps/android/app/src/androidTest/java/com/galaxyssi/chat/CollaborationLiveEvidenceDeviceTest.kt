package com.galaxyssi.chat

import android.graphics.Bitmap
import android.app.KeyguardManager
import android.os.PowerManager
import android.os.SystemClock
import android.view.View
import android.view.WindowManager
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
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

/** Opt-in live fixture: real providers and MQTT, no contacts, physical controls or original research. */
@RunWith(AndroidJUnit4::class)
class CollaborationLiveEvidenceDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun remoteAuthorIndependentReviewerAndHostAcceptance() = runBlocking {
        assumeTrue("Requires explicit authorization for real provider calls",
            InstrumentationRegistry.getArguments().getString("collaborationLiveEvidence") == "true")
        val headless = InstrumentationRegistry.getArguments().getString("collaborationLiveHeadless") == "true"
        val multipart = InstrumentationRegistry.getArguments().getString("collaborationLiveMultipart") == "true"
        val scenario = if (headless) null else ActivityScenario.launch(MainActivity::class.java)
        val token = UUID.randomUUID().toString()
        val run = "live-evidence-$token"
        val turn = "turn-$token"
        var group = ""
        var previous = ""
        val database = AgentEncryptedDatabase(context, run)
        val store = EncryptedAgentTeamExecutionStore(database)
        var handle: AgentTeamExecutionHandle? = null
        var runtime: AgentTeamExecutionRuntime? = null
        var keptScreenOn = false
        var touchedWindow = false
        var fixtureFailure: Throwable? = null
        try {
            if (headless) {
                val transcripts = AgentTranscriptStore(context)
                previous = transcripts.activeConversation().id
                group = transcripts.createAgentConversation("Evidence acceptance").id
                assertEquals("Headless fixture must not change the active conversation", previous, transcripts.activeConversation().id)
                GalaxySSIMqttClient.connect(context)
            } else {
                waitUntil("activity hydration") {
                    var ready = false
                    scenario?.onActivity { ready = !it.initialAgentHydrationPending &&
                        it.findViewById<View>(R.id.startupConnectingView).visibility != View.VISIBLE }
                    ready
                }
                scenario?.onActivity {
                    keptScreenOn = (it.window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
                    it.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    touchedWindow = true
                    previous = it.agentTranscriptStore.activeConversation().id
                    it.createAgentConversation()
                    group = it.agentTranscriptStore.activeConversation().id
                }
            }
            File(context.getExternalFilesDir(null), "collaboration-live-evidence-mode.json").writeText(JSONObject()
                .put("run_id", run).put("headless", headless).put("multipart", multipart).put("activity_launched", scenario != null)
                .put("device_locked", context.getSystemService(KeyguardManager::class.java).isDeviceLocked)
                .put("interactive", context.getSystemService(PowerManager::class.java).isInteractive).toString())
            assertNotEquals("Fixture must not reuse the user's selected conversation", previous, group)
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
            scenario?.onActivity { it.refreshCollaborationStrip(); it.refreshAgentTranscriptWindow(group) }
            val requirement = if (multipart) "Document the observed command output for fixture $token. " +
                "Include numbers 1,2,4,8 and their sum and mean. State observation limitations." else
                "Document the observed command output for fixture $token, including numbers 1,2,4,8, their sum and mean, and the observation limitations."
            val criteria = JSONArray().put(JSONObject().put("id", "doc").put("requirement", requirement)
                .put("verification", "documentary").put("evidence_kind", "observed").put("status", "open")
                .put(CollaborationEvidenceRequirements.FIELD, JSONArray().put(JSONObject()
                    .put("origin", "desktop_codex_tool").put("tool", "codex.commandExecution")))
                .put("evidence", JSONArray())).toString()
            fun member(person: CollaborationMember, node: String, stage: String, objective: String,
                       dependencies: Set<String> = emptySet()) = AgentTeamMember(person.agentId,
                if (node == "deliver") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                instanceId = node, role = person.role, objective = objective, dependsOnAgentIds = dependencies,
                context = mapOf("collaboration_group_id" to group, "collaboration_name" to person.name,
                    "collaboration_provider" to person.providerLabel, CollaborationResearchWorkflow.PERSON to person.id,
                    CollaborationResearchWorkflow.STAGE to stage, CollaborationGoalLoop.ENABLED to "1"))
            val mappingInstruction = if (multipart) "Publish TWO separate mapping artifacts, id=fixture-goal-map-a for source-1/source-2 " +
                "and id=fixture-goal-map-b for source-3, each with body.semantic_goal_mapping and the same full host goal/criteria hashes. " else
                "Also publish a separate artifact id=fixture-goal-map, title=Original goal mapping, with body.semantic_goal_mapping. "
            val reviewInstruction = if (multipart) "Independently review BOTH saved mapping parts; publish separate acceptance_review objects " +
                "id=fixture-coverage-review-a and id=fixture-coverage-review-b, each targeting its corresponding exact mapping " +
                "and reviewing ONLY that mapping's source IDs. " else
                "Publish a SECOND workspace kind=acceptance_review object id=fixture-coverage-review with body.semantic_coverage_review, "
            val members = mutableListOf(
                member(author, "author", "EXECUTE", "Use the terminal to print fixture token $token " +
                    "and compute the sum and mean of 1,2,4,8. In PowerShell use Write-Output '$token'; Write-Output (1+2+4+8); Write-Output ((1+2+4+8)/4). " +
                    "Avoid nested shells and variable quoting. A failed read-only attempt may be corrected; do not repeat a successful command. " +
                    "Do not inspect repository files, use the web, operate the phone, or write files. " +
                    "Publish a workspace artifact with id=fixture-document and body.content documenting the actual returned output and its limits. " +
                    mappingInstruction +
                    "Copy goal_sha256 and criteria_sha256 from the host goal-coverage source in acceptance feedback; map every host source ID to criterion doc. " +
                    "Do not reproduce source text, count offsets or invent hashes. You author this mapping; the other member independently reviews it. " +
                    "This is documentary evidence, not a qualified computational or scientific certification. Do not invent receipt IDs; " +
                    "the host imports Desktop observations after your final reply. Return the research-artifact JSON."),
                member(reviewer, "review", "RECHECK", "Independently review the author's exact saved document from the dependency workspace_receipt. " +
                    "Use the available collaboration_recall tool with mode=evidence to inspect the original recorded Desktop command observation, " +
                    "not just the author's prose. Read the original by evidence_id and sha256 when needed. Check token $token and the numbers. " +
                    "Publish workspace kind=acceptance_review id=fixture-review with a JSON object body.acceptance_review (not prose) " +
                    "for criterion_id=doc and exact requirement: $requirement " +
                    "Copy the delivery reference into target and parents; cite the actual host evidence in observations. " +
                    "The required source is origin=desktop_codex_tool, tool=codex.commandExecution. Browse mode=evidence, " +
                    "read its original with evidence_id/sha256, and cite that original receipt, not just a receipt for reading the author's document. " +
                    "Use verdict=supported only if the document agrees with the recorded output, otherwise refuted/not_tested with unresolved issues. " +
                    "Also independently compare every host source segment against criterion doc and the author's saved mapping artifacts. " +
                    reviewInstruction + "Use body.semantic_coverage_review, " +
                    "targeting the exact mapping reference, citing it in parents, and explicitly reviewing each source ID assigned to that mapping and criterion_ids:[doc]. " +
                    "Keep global and per-segment verdict, rationale and unresolved fields. Do not author or edit the mapping you review. " +
                    "Do not run another command, browse the web, or operate other apps.", setOf("author"))
            )
            if (multipart) members += member(author, "catalogue", "EXECUTE", "Create only a saved coverage directory for the existing two mapping parts. " +
                "Read exact references from the author and reviewer dependency workspace_receipts. Publish ONE kind=artifact id=fixture-coverage-directory " +
                "with body.semantic_goal_manifest:{format:'galaxyssi.semantic-goal-manifest.v1',goal_sha256:the full host goal hash," +
                "criteria_sha256:the full host criteria hash,parts:[{mapping:exact map-a reference,review:exact coverage-review-a reference}," +
                "{mapping:exact map-b reference,review:exact coverage-review-b reference}]}. Cite all four references in parents. " +
                "Do not substitute the delivery review for a coverage review. Use only scoped collaboration_recall when receipts are omitted: " +
                "mode=goal_contract for paged dependency context, or mode=workspace for exact saved versions. " +
                "Before publishing, also independently read every original Desktop command evidence page using collaboration_recall mode=evidence. " +
                "Browse first for exact evidence_id and sha256; follow next_offset until null. Reading a document or goal summary is insufficient. " +
                "Cite that original command reference in the directory workspace object's observations list. " +
                "Do not run external tools, change mappings, add claims, or certify the result. " +
                "Return research-artifact JSON only.", setOf("author", "review"))
            val coverageInstruction = if (multipart) "plus goal_coverage:{manifest:exact saved fixture-coverage-directory reference from catalogue}. " else
                "plus goal_coverage:{mapping:exact author mapping reference,review:exact peer coverage-review reference}. "
            members += member(author, "deliver", "DELIVER", "Assess only this documentary fixture. Use the exact saved author/review versions " +
                    "in the dependency workspace receipts. If valid, return achieved with the preserved criterion and delivery/review references, " +
                    coverageInstruction +
                    "The peer's delivery review and coverage review are separate objects; do not interchange them. " +
                    "Only scoped collaboration_recall is allowed to read missing dependency receipts or saved originals. " +
                    "No external tools, experiments, members or unrelated work. Do not claim scientific or general team superiority.",
                if (multipart) setOf("author", "review", "catalogue") else setOf("author", "review"))
            val definition = AgentTeamDefinition(run, codex.id, members, primaryInstanceId = "deliver", visibilityMode = AgentTeamVisibilityMode.VISIBLE)
            val request = AgentRunRequest(group, turn, turn, runId = run,
                goal = requirement, idempotencyKey = run, context = mapOf(CollaborationGoalLoop.CRITERIA to criteria,
                    CollaborationGoalLoop.ROUND to "1", CollaborationGoalLoop.ACCEPTANCE_FEEDBACK to
                        CollaborationGoalLoop.acceptanceContext(requirement, JSONArray(criteria))))
            val publisher = CollaborationTranscriptPublisher(context)
            // Use the real member worker and graph, but a dedicated store so a failed fixture cannot auto-expand later.
            runtime = AgentTeamExecutionRuntime(store, onSnapshot = { snapshot ->
                publisher.publish(snapshot)
                report(snapshot)
            })
            handle = runtime.start(definition, request, fixtureWorker(headless))
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
            val workspace = CollaborationResearchWorkspace(context)
            val reviewRefs = reviewed.getJSONObject("workspace_receipt").getJSONArray("revisions")
            val savedReviews = (0 until reviewRefs.length()).map { index -> reviewRefs.getJSONObject(index).let { ref ->
                workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))!!
            } }
            val review = savedReviews.single { it.getJSONObject("body").has("acceptance_review") }
            val coverageReviews = savedReviews.filter { it.getJSONObject("body").has(CollaborationSemanticGoalCoverage.REVIEW) }
            assertEquals(if (multipart) 2 else 1, coverageReviews.size)
            coverageReviews.forEach { coverageReview ->
                assertEquals(reviewer.id, coverageReview.getString("person_id"))
                val mappingRef = coverageReview.getJSONObject("body").getJSONObject(CollaborationSemanticGoalCoverage.REVIEW).getJSONObject("target")
                val mapping = workspace.read(access, mappingRef.getString("object_id"), mappingRef.getInt("revision"))!!
                assertEquals(author.id, mapping.getString("person_id"))
                assertEquals(CollaborationSemanticGoalCoverage.source(requirement).getString("goal_sha256"),
                    mapping.getJSONObject("body").getJSONObject(CollaborationSemanticGoalCoverage.MAPPING).getString("goal_sha256"))
            }
            val assessment = requireNotNull(CollaborationGoalLoop.decode(result.snapshot.members.single { it.memberId == "deliver" }.output))
            val resolvedCoverage = CollaborationGoalCoverageManifest.resolve(assessment.getJSONObject("goal_coverage"),
                assessment.getJSONArray("criteria"), requirement) { ref ->
                requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision")))
            }
            assertEquals(coverageReviews.map { it.getString("object_id") }.toSet(),
                resolvedCoverage.parts.map { it.review.getString("object_id") }.toSet())
            assertEquals(if (multipart) 1 else 0, resolvedCoverage.manifests.size)
            if (multipart) assertEquals("catalogue", workspace.read(access,
                resolvedCoverage.manifests.single().getString("object_id"), 1)!!.getString("node_id"))
            assertTrue("Review must reference observed evidence", review.getJSONArray("host_observations").length() > 0)
            val directRefs = review.getJSONArray("host_observations")
            val originals = observations.filter { it.getString("origin") == "desktop_codex_tool" &&
                it.getString("tool") == "codex.commandExecution" && it.getString("output_json").contains(token) }
            assertTrue("Review must cite the actual Desktop observation, not a peer-document read receipt", originals.any { original ->
                (0 until directRefs.length()).any { directRefs.getJSONObject(it).getString("evidence_id") == original.getString("evidence_id") } })
            repeat(directRefs.length()) { index ->
                val ref = directRefs.getJSONObject(index)
                val original = ledger.read(access, ref.getString("evidence_id"), ref.getString("sha256"))!!
                CollaborationEvidenceReadCoverage.requireComplete(ref, review, original)
                assertEquals("scoped_pages", ref.getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getString("mode"))
            }
            val remoteRefs = org.json.JSONArray()
            if (multipart) {
                val manifest = resolvedCoverage.manifests.single()
                val directory = workspace.read(access, manifest.getString("object_id"), manifest.getInt("revision"))!!
                val refs = directory.getJSONArray("host_observations")
                assertTrue("Codex catalogue must confirm receiving the original evidence", refs.length() > 0)
                repeat(refs.length()) { index ->
                    val ref = refs.getJSONObject(index)
                    val original = originals.single { it.getString("evidence_id") == ref.getString("evidence_id") }
                    CollaborationEvidenceReadCoverage.requireComplete(ref, directory, original)
                    assertEquals("scoped_pages", ref.getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getString("mode"))
                    remoteRefs.put(ref)
                }
            }
            File(context.getExternalFilesDir(null), "collaboration-live-evidence-read-coverage.json").writeText(JSONObject()
                .put("run_id", run).put("review_node", review.getString("node_id"))
                .put("observations", directRefs).put("coverage_frozen_at_publication", true)
                .put("remote_confirmed_observations", remoteRefs)
                .put("trust", "host_served_pages_not_scientific_validation").toString())
            assertTrue("Reviewer must actually fetch the original, not merely browse or cite its ID", observations.any { observation ->
                val input = JSONObject(observation.getString("input_json"))
                observation.getString("person_id") == reviewer.id && observation.getString("tool") == CollaborationCloudRecall.NAME &&
                    input.optString("mode") == "evidence" && originals.any { it.getString("evidence_id") == input.optString("evidence_id") } &&
                    observation.getString("status") == "returned" && observation.getString("output_json").contains(token)
            })
            assertEquals(reportText(result.snapshot), "achieved", result.snapshot.goalDisposition)
            assertTrue(result.subagentResult.results.single { it.childId == "deliver" }.collaborationAcceptance?.accepted == true)
            scenario?.onActivity { it.refreshAgentTranscriptWindow(group) }
            if (!headless) screenshot()
            else assertEquals("Background fixture changed the active conversation", previous, AgentTranscriptStore(context).activeConversation().id)
        } catch (failure: Throwable) {
            fixtureFailure = failure
            throw failure
        } finally {
            withContext(NonCancellable) {
                var cleanupFailure: Throwable? = null
                fun remember(failure: Throwable) {
                    val original = cleanupFailure
                    if (original == null) cleanupFailure = failure else original.addSuppressed(failure)
                }
                try {
                    check(stopFixture(run, group, store, handle)) {
                        "Remote STOP was not acknowledged; retained fixture $run and conversation $group for recovery"
                    }
                    runtime?.close()
                    if (group.isNotBlank()) {
                        CollaborationGroupStore(context).remove(group)
                        AgentTranscriptStore(context).deleteConversation(group)
                    }
                    database.clear()
                } catch (failure: Throwable) {
                    remember(failure)
                } finally {
                    runCatching { runtime?.close() }.exceptionOrNull()?.let(::remember)
                    runCatching {
                        if (!headless && previous.isNotBlank()) {
                            AgentTranscriptStore(context).switchConversation(previous)
                            scenario?.onActivity {
                                it.agentTranscriptStore.switchConversation(previous)
                                it.refreshCollaborationStrip()
                                it.refreshAgentTranscriptWindow(previous)
                            }
                        }
                    }.exceptionOrNull()?.let(::remember)
                    runCatching {
                        if (touchedWindow && !keptScreenOn) scenario?.onActivity {
                            it.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }.exceptionOrNull()?.let(::remember)
                    runCatching { scenario?.close() }.exceptionOrNull()?.let(::remember)
                }
                cleanupFailure?.let { failure ->
                    val original = fixtureFailure
                    if (original == null) throw failure else original.addSuppressed(failure)
                }
            }
        }
        Unit
    }

    private fun fixtureWorker(headless: Boolean): ActionExecutorAgentTeamMemberWorker {
        if (!headless) return ActionExecutorAgentTeamMemberWorker(context)
        val provider = ActionExecutorAgentProvider(
            registrationSource = { AppStoreAgentConnectorRegistry(context).registrations() },
            delegate = AndroidAgentActionExecutor(context),
            runStartReceipts = EncryptedAgentRunStartReceiptStore(context),
            healthLedger = EncryptedAgentProviderHealthLedger(context),
            managedResponses = EncryptedAgentManagedResponseLedger(context),
            globalRunSlots = AgentGlobalRunSlotStore(context)
        )
        return ActionExecutorAgentTeamMemberWorker(provider, AgentAdapterDirectory().apply { register(provider) },
            screenProvider = { ScreenContext(foregroundApp = "GalaxySSI fixture", pageTitle = "Synthetic evidence acceptance") },
            progressContext = context.applicationContext)
    }

    private suspend fun stopFixture(run: String, group: String, store: AgentTeamExecutionStore,
                                    handle: AgentTeamExecutionHandle?): Boolean {
        val controls = AgentTeamDurableControl(context)
        controls.set(run, AgentTeamUserControl.STOP)
        check(controls.get(run) == AgentTeamUserControl.STOP)
        handle?.let { if (it.isActive) it.cancel("Authorized live fixture finished; durable STOP requested") }
        val ledger = EncryptedAgentManagedResponseLedger(context)
        val recovery = AgentTeamRemoteStopRecovery(context)
        val acknowledged = withTimeoutOrNull(90_000L) {
            while (true) {
                val snapshot = store.snapshot(run)
                if (snapshot != null) recovery.reconcile(listOf(snapshot), ledger) { id ->
                    id == run && controls.get(id) == AgentTeamUserControl.STOP
                }
                val localFinished = handle?.let { !it.isActive } ?: (snapshot == null)
                if (localFinished && ledger.pendingForSupervisor(run).isEmpty()) break
                delay(250L)
            }
            true
        } == true
        store.snapshot(run)?.let(::report)
        val pending = ledger.pendingForSupervisor(run)
        File(context.getExternalFilesDir(null), "$run-cleanup.json").writeText(JSONObject()
            .put("acknowledged", acknowledged).put("execution_database", run).put("conversation_id", group)
            .put("durable_control", controls.get(run).name).put("retained_for_recovery", !acknowledged)
            .put("pending_remote_owners", JSONArray(pending.map { it.ownerRunId })).toString())
        return acknowledged
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
