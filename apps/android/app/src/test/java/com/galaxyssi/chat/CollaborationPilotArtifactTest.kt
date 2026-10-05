package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationPilotArtifactTest {
    private fun fixture() = runBlocking {
        val plan = CollaborationPilotArtifactFixture.plan()
        CollaborationPilotArtifactFixture.execute(plan, plan.slots.first())
    }
    private fun rejected(block: () -> Unit) { assertThrows(RuntimeException::class.java, block) }

    @Test fun actualSyntheticGraphsFreezeBothArmsWithExactTextAndExplicitTrust() = runBlocking {
        val plan = CollaborationPilotArtifactFixture.plan()
        for (slot in plan.slots) {
            val result = CollaborationPilotArtifactFixture.execute(plan, slot)
            val artifact = result.capture()
            val restored = CollaborationPilotArtifact.restore(artifact.envelope(), result.source, artifact.reference)
            assertEquals(result.snapshot.finalOutput, restored.finalOutput)
            assertEquals(artifact.payload, restored.payload)
            assertTrue(restored.finalOutput.startsWith("  ") && restored.finalOutput.endsWith("\n"))
            val body = JSONObject(restored.payload)
            assertEquals("unverified_candidate", body.getString("trust"))
            assertFalse(body.getBoolean("grants_permissions"))
            assertEquals(3, body.getJSONArray("members").length())
        }
    }

    @Test fun incompleteFailedPausedAndTruncatedRunsCannotFreeze() {
        val f = fixture()
        AgentTeamExecutionState.values().filter { it != AgentTeamExecutionState.SUCCEEDED }.forEach { state ->
            rejected { f.copy(snapshot = f.snapshot.copy(state = state)).capture() }
        }
        rejected { f.copy(snapshot = f.snapshot.copy(paused = true)).capture() }
        rejected { f.copy(truncated = true).capture() }
        rejected { f.copy(snapshot = f.snapshot.copy(members = f.snapshot.members.dropLast(1))).capture() }
        AgentSubagentStatus.values().filter { it != AgentSubagentStatus.SUCCEEDED }.forEach { state ->
            rejected { f.copy(snapshot = f.snapshot.copy(members = f.snapshot.members.map { it.copy(status = state) })).capture() }
        }
    }

    @Test fun sourceAndMemberAttributionMustMatchRuntime() {
        val f = fixture()
        val s = f.snapshot
        val wrong = listOf(s.copy(supervisorRunId = "other"), s.copy(teamId = "other"), s.copy(taskId = "other"),
            s.copy(conversationId = "other"), s.copy(goal = "other"), s.copy(primaryAgentId = "other"),
            s.copy(primaryInstanceId = "draft"), s.copy(members = s.members.reversed()),
            s.copy(members = s.members.map { it.copy(personId = "other") }),
            s.copy(members = s.members.map { it.copy(agentId = "other") }),
            s.copy(members = s.members.map { it.copy(collaborationGroupId = "other") }))
        wrong.forEach { rejected { f.copy(snapshot = it).capture() } }
    }

    @Test fun finalAnswerMustBeNonblankAndEqualToFinalNodeWithoutTrimming() {
        val f = fixture()
        for (output in listOf("", " ", "different", f.snapshot.finalOutput.trim())) {
            rejected { f.copy(snapshot = f.snapshot.copy(finalOutput = output)).capture() }
        }
    }

    @Test fun everyDispatchIdentityAndControlIsBound() {
        val f = fixture()
        val fields = listOf("node_id", "person_id", "transport_instance_id", "parent_run_id", "turn_id",
            "conversation_id", "task_id", "target_id", "requested_model", "requested_reasoning_effort",
            "accounting_scope", "prepared_prompt_sha256", "source_message_id")
        fields.forEach { key ->
            val changed = JSONArray(f.dispatches.toString())
            changed.getJSONObject(0).put(key, "changed")
            rejected { f.copy(dispatches = changed).capture() }
        }
    }

    @Test fun missingDuplicateOrExtraDispatchCannotFreeze() {
        val f = fixture()
        rejected { f.copy(dispatches = JSONArray(f.dispatches.toString()).also { it.remove(1) }).capture() }
        rejected { f.copy(dispatches = JSONArray(f.dispatches.toString()).put(f.dispatches.getJSONObject(0))).capture() }
        for (field in listOf("owner_run_id", "idempotency_key", "source_message_id")) {
            val changed = JSONArray(f.dispatches.toString())
            changed.getJSONObject(1).put(field, changed.getJSONObject(0).get(field))
            rejected { f.copy(dispatches = changed).capture() }
        }
    }

    @Test fun corruptedPayloadCannotBeReadWithOriginalReference() {
        val artifact = fixture().capture()
        val envelope = JSONObject(artifact.envelope()).put("payload_json", artifact.payload + " ")
        rejected { CollaborationPilotArtifact.restore(envelope.toString(), artifact.source, artifact.reference) }
        rejected { CollaborationPilotArtifact.restore("{}", artifact.source, artifact.reference) }
    }

    @Test fun differentProtocolRunArmOrTaskCannotReuseReference() = runBlocking {
        val plan = CollaborationPilotArtifactFixture.plan()
        val f = CollaborationPilotArtifactFixture.execute(plan, plan.slots.first())
        val artifact = f.capture()
        val s = f.source
        val alternatives = listOf(
            CollaborationPilotArtifact.Source.of(plan, plan.slots.first(), s["conversation_id"], s["run_id"], s["turn_id"], "b".repeat(64)),
            CollaborationPilotArtifact.Source.of(plan, plan.slots.first(), "other", s["run_id"], s["turn_id"], s["protocol_sha256"]),
            CollaborationPilotArtifact.Source.of(plan, plan.slots.first(), s["conversation_id"], "other", s["turn_id"], s["protocol_sha256"]),
            CollaborationPilotArtifact.Source.of(plan, plan.slots.last(), s["conversation_id"], s["run_id"], s["turn_id"], s["protocol_sha256"]))
        alternatives.forEach { rejected { CollaborationPilotArtifact.restore(artifact.envelope(), it, artifact.reference) } }
    }

    @Test fun rehashedPayloadStillCannotClaimReviewOrPermissionsOrChangeSource() {
        val artifact = fixture().capture()
        for (key in listOf("trust", "grants_permissions", "source", "final_output_sha256")) {
            val body = JSONObject(artifact.payload).put(key, "changed")
            val payload = body.toString()
            val ref = artifact.reference.copy(sha256 = CollaborationRemotePilotDispatch.sha256(payload.toByteArray(Charsets.UTF_8)))
            val envelope = JSONObject().put("payload_json", payload).put("reference", ref.json())
            rejected { CollaborationPilotArtifact.restore(envelope.toString(), artifact.source, ref) }
        }
    }
}
