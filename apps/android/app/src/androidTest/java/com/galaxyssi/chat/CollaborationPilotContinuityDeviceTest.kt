package com.galaxyssi.chat

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import com.galaxyssi.chat.CollaborationPilotContinuityFixtures as F

/** Two separately launched instrumentation processes; synthetic data, no model dispatch. */
@RunWith(AndroidJUnit4::class)
class CollaborationPilotContinuityDeviceTest {
    @Test fun retainedMethodAcrossFreshTaskAndProcess() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("continuityPhase").orEmpty()
        assumeTrue(phase in setOf("seed", "recover"))
        val token = args.getString("continuityToken").orEmpty()
        require(token.matches(Regex("[a-z0-9-]{1,32}")))
        val context = instrumentation.targetContext
        val database = AgentEncryptedDatabase(context, "test-continuity-$token")
        val journal = CollaborationPilotContinuity({ database.readString(it, "").takeIf(String::isNotBlank) },
            { key, value -> database.mutateStrings(mapOf(key to value)) })
        val groups = CollaborationGroupStore(context)
        val transcripts = AgentTranscriptStore(context)
        val plan = F.plan(F.input(token, if (phase == "seed") 1 else 2, retain = phase == "seed")
            .put("initial_identity_policy", "run_scoped"))
        val before = CollaborationPilotWindowSnapshot.read(context)
        val lease = journal.open(plan, F.protocolHash, {
            val id = transcripts.createAgentConversation("Continuity fixture $token").id
            groups.update(id) { it.copy(members = plan.members, coordinatorId = "lead") }
            id
        }, { groups.load(it) != null }, { F.reportHash })
        val workspace = CollaborationResearchWorkspace(context)
        val run = "adaptive-pilot-${plan.id}"
        val initial = plan.definition(lease.groupId, run)
        val ids = initial.members.map { it.memberId }
        assertEquals(listOf("lead", "peer"), initial.members.map { it.context[CollaborationResearchWorkflow.PERSON] })
        assertTrue(ids.none { it in setOf("lead", "peer") })
        val access = CollaborationWorkspaceAccess(lease.groupId, run, "turn-adaptive-pilot-${plan.id}", 0, initial.primaryMemberId, "lead")
        if (phase == "seed") {
            assertEquals("recorded", workspace.publish(access, F.workflow().toString()).getString("status"))
            database.mutateStrings(mapOf("seed_pid" to android.os.Process.myPid().toString(),
                "seed_initial_ids" to JSONArray(ids).toString()))
            journal.finish(lease, F.report(lease), F.reportHash)
        } else try {
            assertNotEquals(database.readString("seed_pid", ""), android.os.Process.myPid().toString())
            val priorIds = JSONArray(database.readString("seed_initial_ids", ""))
            assertTrue(ids.toSet().intersect((0 until priorIds.length()).map(priorIds::getString).toSet()).isEmpty())
            val found = workspace.searchCapabilities(access, "immutable corpus").getJSONArray("records")
            assertEquals(1, found.length())
            val ref = found.getJSONObject(0)
            val original = workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))!!
            assertNotEquals(access.runId, original.getString("run_id"))
            assertNotEquals(access.turnId, original.getString("turn_id"))
            assertEquals("Mutable corpus", original.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND).getString("avoid_when"))
            assertEquals("unverified_workflow_candidate", original.getJSONObject(CollaborationEvolutionContract.HOST).getString("state"))
            val recalled = CollaborationScopedRecall.read(context, mapOf("mode" to "workspace",
                "object_id" to ref.getString("object_id"), "revision" to ref.getInt("revision")), access)
            assertTrue(JSONObject(recalled.output).toString(), recalled.isSuccess)
            journal.finish(lease, F.report(lease), F.reportHash)
        } finally {
            groups.remove(lease.groupId)
            transcripts.deleteConversation(lease.groupId)
            database.clear()
        }
        assertEquals(before, CollaborationPilotWindowSnapshot.read(context))
        instrumentation.sendStatus(0, Bundle().apply {
            putString("continuity_phase", phase)
            putString("fixture_pid", android.os.Process.myPid().toString())
            putString("model_dispatches", "0")
            putString("initial_identity_policy", plan.initialIdentityPolicy)
            putString("fresh_provider_thread_verified", "false")
            putString("autonomous_learning_proven", "false")
        })
    }
}
