package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationPilotContinuityFixtures as F

class CollaborationPilotContinuityTest {
    private val rows = mutableMapOf<String, String>()
    private fun journal() = CollaborationPilotContinuity(rows::get) { k, v -> rows[k] = v }
    private fun open(phase: Int = 1, retain: Boolean = true, input: JSONObject = F.input(phase = phase, retain = retain)) =
        journal().open(F.plan(input), F.protocolHash, { "owned-group" }, { it == "owned-group" }, { F.reportHash })
    private fun seed(retain: Boolean = true, change: (JSONObject) -> Unit = {}) = open(retain = retain).also {
        journal().finish(it, F.report(it).apply(change), F.reportHash)
    }
    private fun rejects(block: () -> Unit) = assertNotNull(runCatching(block).exceptionOrNull())

    @Test fun futureTaskKeepsOwnedGroupButNotExecutionIdentityOrGoal() {
        val first = seed()
        val next = open(2)
        assertEquals(first.groupId, next.groupId)
        assertNotEquals(first.pilotId, next.pilotId)
        assertNotEquals(F.plan().goal, F.plan(F.input(phase = 2)).goal)
        assertFalse(next.descriptor().getBoolean("old_answers_injected_by_harness"))
        assertFalse(next.descriptor().getBoolean("autonomous_retrieval_proven"))
        assertFalse(next.descriptor().getBoolean("retained_learning_proven"))
        assertFalse(next.descriptor().getBoolean("fresh_provider_thread_verified"))
    }

    @Test fun unchangedTrialsRemainStatelessByDefault() {
        assertNull(F.plan(F.input().apply { remove("continuity") }).continuity)
    }

    @Test fun malformedOwnershipAndImplicitDispositionAreRejected() {
        for (mutation in listOf<(JSONObject) -> Unit>(
            { it.put("study_id", "../user-group") }, { it.put("phase", 0) }, { it.put("phase", "1") },
            { it.put("phase", 1.5) }, { it.put("previous_report_sha256", F.reportHash) },
            { it.remove("retain_history") }, { it.put("retain_history", "true") }, { it.put("conversation_id", "user") }
        )) rejects { F.plan(F.input().apply { mutation(getJSONObject("continuity")) }) }
        rejects { F.plan(F.input(phase = 2).apply { getJSONObject("continuity").put("previous_report_sha256", "") }) }
    }

    @Test fun existingOrActiveStudyCannotBeRestartedOrOverlapped() {
        open()
        rejects { open() }
        rejects { open(2) }
    }

    @Test fun futurePhaseCannotAdoptAnUnregisteredConversationOrSkipAPhase() {
        rejects { open(2) }
        seed()
        rejects { open(3) }
    }

    @Test fun changedPredecessorFileOrFrozenDigestIsRejected() {
        seed()
        rejects { journal().open(F.plan(F.input(phase = 2)), F.protocolHash, { error("No creation") }, { true }, { "c".repeat(64) }) }
        rejects { open(2, input = F.input(phase = 2).apply { getJSONObject("continuity").put("previous_report_sha256", "c".repeat(64)) }) }
        open(2)
    }

    @Test fun lostGroupIsNotRecreated() {
        seed()
        rejects { journal().open(F.plan(F.input(phase = 2)), F.protocolHash, { error("Must not recreate") }, { false }, { F.reportHash }) }
    }

    @Test fun changingModelTargetDeviceOrRosterRequiresAnotherStudy() {
        seed()
        for ((key, value) in listOf("model_id" to "other", "target_id" to "another:codex", "device_model" to "other", "reasoning_effort" to "xhigh"))
            rejects { open(2, input = F.input(phase = 2).put(key, value)) }
        rejects { open(2, input = F.input(phase = 2).apply { getJSONArray("members").getJSONObject(0).put("role", "Changed") }) }
    }

    @Test fun incompleteStopOrArchiveBlocksFollowingPhaseWithoutRewritingOriginalFailure() {
        for (mutation in listOf<(JSONObject) -> Unit>(
            { it.put("cleanup_confirmed", false) }, { it.put("milestone_archive_complete", false) },
            { it.put("durable_control", "CONTINUE") }, { it.put("pending_remote_owners", JSONArray().put("remote")) }
        )) {
            rows.clear(); seed(change = mutation)
            assertEquals("failed", JSONObject(rows.values.single()).getString("last_verdict"))
            rejects { open(2) }
        }
    }

    @Test fun terminalNegativeResultMayBeStudiedButDoesNotBecomeSuccess() {
        seed()
        assertEquals("failed", JSONObject(rows.values.single()).getString("last_verdict"))
        open(2)
    }

    @Test fun lastPhaseSealsStudyAgainstLaterReuse() {
        seed(retain = false)
        assertEquals("closed", JSONObject(rows.values.single()).getString("state"))
        rejects { open(2) }
    }

    @Test fun reportFromAnotherRunCannotReleaseActiveOwnership() {
        val lease = open()
        for (key in listOf("pilot_id", "conversation_id", "protocol_sha256", "run_id", "turn_id"))
            rejects { journal().finish(lease, F.report(lease).put(key, "foreign"), F.reportHash) }
        rejects { journal().finish(lease, F.report(lease).put("finished", false), F.reportHash) }
        rejects { open(2) }
    }

    @Test fun creationFailureLeavesAReservationNotAnImplicitRetry() {
        rejects { journal().open(F.plan(), F.protocolHash, { error("Creation failed") }, { true }, { F.reportHash }) }
        assertEquals("reserved", JSONObject(rows.values.single()).getString("state"))
        rejects { open() }
    }

    @Test fun observerSnapshotKeepsOriginalMethodWithoutClaimingAnAgentRead() {
        val f = CollaborationWorkflowTest.Fixture()
        val access = f.f.access().copy(runId = "observer", turnId = "observer")
        val snapshot = CollaborationPilotHistorySnapshot.capture(f.f.workspace, access)
        val originals = snapshot.getJSONArray("originals")
        val method = (0 until originals.length()).map(originals::getJSONObject)
            .single { it.getString("object_id") == f.method.getString("object_id") }
        assertEquals(f.method.getString("sha256"), method.getString("sha256"))
        assertEquals(f.spec.toString(), method.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND).toString())
        assertFalse(snapshot.getBoolean("agent_read_proven"))
        assertFalse(snapshot.getBoolean("capability_gain_proven"))
    }

    @Test fun observerSnapshotDoesNotImportAnotherGroupsMethods() {
        val f = CollaborationWorkflowTest.Fixture()
        val snapshot = CollaborationPilotHistorySnapshot.capture(f.f.workspace, f.f.access().copy(groupId = "another-group"))
        assertEquals(0, snapshot.getJSONArray("originals").length())
    }
}
