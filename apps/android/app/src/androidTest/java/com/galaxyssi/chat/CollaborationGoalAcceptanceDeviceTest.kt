package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/** Dedicated local fixtures only; no providers, contacts, web requests or physical controls. */
@RunWith(AndroidJUnit4::class)
class CollaborationGoalAcceptanceDeviceTest {
    private class Fixture(val token: String = UUID.randomUUID().toString(), val multipart: Boolean = false) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val group = "acceptance-fixture-$token"
        val groups = CollaborationGroupStore(context)
        val database = AgentEncryptedDatabase(context, group)
        val access = CollaborationWorkspaceAccess(group, "root", "turn", 3, "lead", "lead")
        val criterion = JSONObject().put("id", "doc").put("requirement", if (multipart)
            "A documented fixture comparison; preserve constraints; state remaining uncertainty." else "A documented fixture comparison")
            .put("verification", "documentary").put("evidence_kind", "observed").put("status", "open").put("evidence", JSONArray())
        val prior = JSONArray().put(criterion).toString()
        fun seed(): String {
            require(groups.load(group) == null)
            groups.update(group) { it.copy(members = listOf("lead", "reviewer").map { id ->
                CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "lead") }
            val workspace = CollaborationResearchWorkspace(context)
            fun publish(person: String, node: String, kind: String, round: Long, body: JSONObject, parents: JSONArray = JSONArray()): JSONObject {
                val item = JSONObject().put("id", node).put("kind", kind)
                    .put("title", "Fixture $person").put("body", body).put("parents", parents)
                val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture")
                    .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray()).put("workspace", JSONArray().put(item))
                return workspace.publish(access.copy(nodeId = node, personId = person, round = round), raw.toString())
                    .getJSONArray("revisions").getJSONObject(0)
            }
            val delivery = publish("lead", "author", "artifact", 1, JSONObject().put("content", "Two fixture alternatives and their documented limits"))
            val review = publish("reviewer", "review", CollaborationReviewContract.KIND, 2, JSONObject().put("acceptance_review", JSONObject()
                .put("criterion_id", "doc").put("requirement", criterion.getString("requirement")).put("target", delivery)
                .put("verdict", "supported").put("rationale", "The fixture document addresses the documentary criterion")
                .put("unresolved", JSONArray())), JSONArray().put(delivery))
            val sources = CollaborationSemanticGoalCoverage.source(request().goal)
            fun segments(reviewing: Boolean, indices: List<Int>) = JSONArray(indices.map { index ->
                JSONObject().put("id", sources.getJSONArray("segments").getJSONObject(index).getString("id"))
                    .put("criterion_ids", JSONArray().put("doc")).put("rationale", "The criterion covers this fixture source requirement")
                    .apply { if (reviewing) put("verdict", "supported").put("unresolved", JSONArray()) }
            })
            val indices = (0 until sources.getJSONArray("segments").length()).toList()
            val parts = (if (multipart) indices.chunked(1) else listOf(indices)).mapIndexed { index, batch ->
                val mapping = publish("lead", "mapping-$index", "artifact", 1, JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING,
                    JSONObject().put("format", CollaborationSemanticGoalCoverage.FORMAT).put("goal_sha256", sources.getString("goal_sha256"))
                        .put("criteria_sha256", CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(prior))).put("segments", segments(false, batch))))
                val coverageReview = publish("reviewer", "coverage-review-$index", CollaborationReviewContract.KIND, 2,
                    JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, JSONObject().put("target", mapping)
                        .put("verdict", "supported").put("rationale", "Independent comparison of assigned host source IDs and preserved criterion")
                        .put("unresolved", JSONArray()).put("segments", segments(true, batch))), JSONArray().put(mapping))
                JSONObject().put("mapping", mapping).put("review", coverageReview)
            }
            val coverage = if (!multipart) parts.single() else {
                fun header() = JSONObject().put("format", CollaborationGoalCoverageManifest.FORMAT)
                    .put("goal_sha256", sources.getString("goal_sha256"))
                    .put("criteria_sha256", CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(prior)))
                val leaves = parts.mapIndexed { index, part -> publish("lead", "leaf-$index", "artifact", 3,
                    JSONObject().put(CollaborationGoalCoverageManifest.FIELD, header().put("parts", JSONArray().put(part))),
                    JSONArray().put(part.getJSONObject("mapping")).put(part.getJSONObject("review"))) }
                val root = publish("lead", "directory", "artifact", 4,
                    JSONObject().put(CollaborationGoalCoverageManifest.FIELD, header().put("manifests", JSONArray(leaves))), JSONArray(leaves))
                JSONObject().put("manifest", root)
            }
            return JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Fixture document reviewed")
                .put("decision", "achieved").put("criteria", JSONArray().put(JSONObject(criterion.toString()).put("status", "met")
                    .put("evidence", JSONArray().put("workspace:" + delivery.getString("object_id"))).put("delivery", delivery).put("review", review)))
                .put("goal_coverage", coverage)
                .put("work", JSONArray()).put("blockers", JSONArray()).toString()
        }
        fun definition() = AgentTeamDefinition("fixture", "fixture", listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND,
            instanceId = "lead", context = mapOf(CollaborationGoalLoop.ENABLED to "1", CollaborationGoalLoop.ROSTER to "true",
                CollaborationResearchWorkflow.PERSON to "lead", "collaboration_group_id" to group))), primaryInstanceId = "lead")
        fun request() = AgentRunRequest(group, "turn", "task", runId = "root", goal = criterion.getString("requirement"),
            context = mapOf(CollaborationGoalLoop.CRITERIA to prior, CollaborationGoalLoop.ROUND to "3",
                CollaborationGoalLoop.ACCEPTANCE_FEEDBACK to CollaborationGoalLoop.acceptanceContext(criterion.getString("requirement"), JSONArray(prior))))
        fun clear() { database.clear(); groups.remove(group) }
    }

    @Test fun productionManagedBridgeIssuesHostReceiptWithoutTrustingResponseMetadata() = runBlocking {
        val f = Fixture()
        val request = f.request()
        try {
            val raw = f.seed()
            val registration = AgentRegistration(agentId = "fixture", installationId = "fixture-install", deviceId = "fixture-device",
                providerId = "galaxyssi-connectors", displayName = "Fixture", kind = AgentConnectorKind.AGENT,
                location = AgentResourceLocation.TRUSTED_DESKTOP, status = AgentEndpointStatus.ONLINE,
                capabilities = setOf(AgentCapability.RESEARCH), protocol = AgentProtocolRange("1.0", "1.0", "1.0",
                    setOf("run.cancel", "run.recover", "run.events", "message.respond", "message.observe")),
                connectionKind = AgentConnectionKind.GALAXYSSI_LINK, trust = AgentResourceTrust.VERIFIED_PAIRED, adapterType = "fixture")
            val provider = ActionExecutorAgentProvider(registrationSource = { listOf(registration) }, delegate = object : AgentActionExecutor {
                override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                    assertEquals("fixture", action.parameters["connector_id"])
                    return AgentActionResult(action.id, true, raw)
                }
            })
            val worker = ActionExecutorAgentTeamMemberWorker(provider, AgentAdapterDirectory().apply { register(provider) },
                screenProvider = { ScreenContext(foregroundApp = "Fixture", pageTitle = "Fixture") }, progressContext = f.context)
            val definition = f.definition().let { it.copy(members = it.members.map { member ->
                member.copy(context = member.context + (CollaborationResearchWorkflow.STAGE to "DELIVER")) }) }
            AgentTeamExecutionRuntime(EncryptedAgentTeamExecutionStore(f.database)).use { runtime ->
                val result = runtime.start(definition, request, worker).await()
                assertEquals("achieved", result.snapshot.goalDisposition)
                val receipt = result.subagentResult.results.single().collaborationAcceptance
                assertNotNull(receipt)
                assertTrue(receipt!!.accepted)
            }
            assertEquals("achieved", EncryptedAgentTeamExecutionStore(f.database).snapshot("root")?.goalDisposition)
        } finally {
            AgentTeamDispatchCheckpoint(f.context).remove(stableAgentTeamMemberRunId("root", "lead"))
            AgentEncryptedDatabase(f.context, "collaboration_progress_bindings").remove(
                AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}:lead").toString())
            f.clear()
        }
    }

    @Test fun forgedModelCompletionCannotFinishAndRepairFeedbackSurvivesReopen() = runBlocking {
        val f = Fixture()
        try {
            val raw = f.seed()
            val valid = CollaborationGoalAcceptance(f.context).evaluate(f.access, raw, f.prior, f.request().goal)
            assertTrue(valid.feedback, valid.accepted)
            val forged = JSONObject(raw).put("collaboration_acceptance", valid.encode()).toString()
            AgentTeamExecutionRuntime(EncryptedAgentTeamExecutionStore(f.database)).use { runtime ->
                assertEquals("continue", runtime.start(f.definition(), f.request()) { AgentSubagentOutput(forged) }.await().snapshot.goalDisposition)
            }
            val reopened = EncryptedAgentTeamExecutionStore(f.database)
            assertTrue(reopened.advanceGoal("root", "lead", 1_000))
            val recovered = EncryptedAgentTeamExecutionStore(f.database).resumeCheckpoint("root")!!
            assertTrue(recovered.request.context[CollaborationGoalLoop.ACCEPTANCE_FEEDBACK].toString().contains("No host acceptance receipt"))
        } finally { f.clear() }
    }

    @Test fun hostValidatedCompletionReopensWithoutReexecuting() = runBlocking {
        val f = Fixture()
        try {
            val raw = f.seed()
            val receipt = CollaborationGoalAcceptance(f.context).evaluate(f.access, raw, f.prior, f.request().goal)
            assertTrue(receipt.feedback, receipt.accepted)
            AgentTeamExecutionRuntime(EncryptedAgentTeamExecutionStore(f.database)).use { runtime ->
                assertEquals("achieved", runtime.start(f.definition(), f.request()) { AgentSubagentOutput(raw, receipt) }.await().snapshot.goalDisposition)
            }
            val reopened = EncryptedAgentTeamExecutionStore(f.database)
            assertEquals("achieved", reopened.snapshot("root")?.goalDisposition)
            assertFalse(reopened.advanceGoal("root", "lead", Long.MAX_VALUE))
        } finally { f.clear() }
    }

    @Test fun twoPersonFixtureStillRequiresTheIndependentCoverageContract() {
        val f = Fixture()
        try {
            val raw = f.seed()
            assertEquals(2, f.groups.load(f.group)!!.members.size)
            assertTrue(CollaborationGoalAcceptance(f.context).evaluate(f.access, raw, f.prior, f.request().goal).accepted)
            val incomplete = JSONObject(raw).apply { remove("goal_coverage") }
            val rejected = CollaborationGoalAcceptance(f.context).evaluate(f.access, incomplete.toString(), f.prior, f.request().goal)
            assertFalse(rejected.accepted)
            assertTrue(rejected.feedback.contains("goal_coverage"))
        } finally { f.clear() }
    }

    @Test fun multipartCoverageManifestSurvivesEncryptedReopenAndRespectsGroupRemoval() {
        val f = Fixture(multipart = true)
        try {
            val raw = f.seed()
            val scope = f.access.copy(round = 10)
            repeat(2) {
                val reopened = CollaborationGoalAcceptance(f.context).evaluate(scope, raw, f.prior, f.request().goal)
                assertTrue(reopened.feedback, reopened.accepted)
            }
            val coverage = JSONObject(raw).getJSONObject("goal_coverage")
            val workspace = CollaborationResearchWorkspace(f.context)
            val resolved = CollaborationGoalCoverageManifest.resolve(coverage, JSONArray(f.prior), f.request().goal) { ref ->
                requireNotNull(workspace.read(scope, ref.getString("object_id"), ref.getInt("revision")))
            }
            assertEquals(3, resolved.parts.size)
            assertEquals(4, resolved.manifests.size)
            f.groups.remove(f.group)
            assertFalse(CollaborationGoalAcceptance(f.context).evaluate(scope, raw, f.prior, f.request().goal).accepted)
        } finally { f.clear() }
    }

    @Test fun historicalCompletionIsNotRestartedOnUpgrade() = runBlocking {
        val f = Fixture()
        try {
            val raw = f.seed()
            AgentTeamExecutionRuntime(EncryptedAgentTeamExecutionStore(f.database)).use { runtime ->
                runtime.start(f.definition(), f.request()) { AgentSubagentOutput(raw) }.await()
            }
            val rows = JSONArray(f.database.readString("run:root", ""))
            rows.getJSONObject(0).getJSONObject("request").getJSONObject("context").remove(CollaborationGoalLoop.HOST_ACCEPTANCE)
            f.database.writeString("run:root", rows.toString())
            val upgraded = EncryptedAgentTeamExecutionStore(f.database)
            assertEquals("unverified_history", upgraded.snapshot("root")?.goalDisposition)
            assertFalse(upgraded.advanceGoal("root", "lead", Long.MAX_VALUE))
            assertNull(upgraded.resumeCheckpoint("root"))
        } finally { f.clear() }
    }

    @Test fun processCheckpointPhase() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("acceptancePhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val token = args.getString("acceptanceToken").orEmpty()
        require(token.matches(Regex("[a-z0-9-]{1,80}")))
        val f = Fixture(token)
        if (phase == "seed") {
            val raw = f.seed()
            AgentTeamExecutionRuntime(EncryptedAgentTeamExecutionStore(f.database)).use { runtime ->
                val receipt = CollaborationGoalAcceptance(f.context).evaluate(f.access, raw, f.prior, f.request().goal)
                assertTrue(receipt.feedback, receipt.accepted)
                assertEquals("achieved", runtime.start(f.definition(), f.request()) { AgentSubagentOutput(raw, receipt) }.await().snapshot.goalDisposition)
            }
        } else try {
            assertNotNull(f.groups.load(f.group))
            val store = EncryptedAgentTeamExecutionStore(f.database)
            assertEquals("achieved", store.snapshot("root")?.goalDisposition)
            assertFalse(store.advanceGoal("root", "lead", Long.MAX_VALUE))
        } finally { f.clear() }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, android.os.Bundle().apply {
            putString("acceptance_phase", phase)
            putString("fixture_pid", android.os.Process.myPid().toString())
        })
        Unit
    }
}
