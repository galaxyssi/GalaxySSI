package com.galaxyssi.chat

import android.content.Context
import android.os.Bundle
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Separate test processes and isolated encrypted rows; never invokes providers or user actions. */
@RunWith(AndroidJUnit4::class)
class CollaborationPublicationRetirementDeviceTest {
    private class Rows(private val db: AgentEncryptedDatabase) : CollaborationWorkspaceRows {
        override fun read(key: String) = db.readString(key, "").takeIf(String::isNotBlank)
        override fun commit(values: Map<String, String>) = db.mutateStrings(values)
        override fun page(prefix: String, after: String, limit: Int) = db.keysAfter(prefix, after, limit)
    }

    @Test fun retiredWriterRemainsFencedAcrossRealProcessReplacement(): Unit = runBlocking {
        val phase = InstrumentationRegistry.getArguments().getString("retirementPhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "candidate-retirement-process-fixture"
        val teamDb = AgentEncryptedDatabase(context, "$name-team")
        val workspaceDb = AgentEncryptedDatabase(context, "$name-workspace")
        val evidenceDb = AgentEncryptedDatabase(context, "$name-evidence")
        val prefs = context.getSharedPreferences(name, Context.MODE_PRIVATE)
        val f = CandidateRuntimeFixture(Rows(workspaceDb), Rows(evidenceDb))
        val store = EncryptedAgentTeamExecutionStore(teamDb, candidateWorkspace = { f.workspace })
        fun task(member: AgentTeamMember) = JSONObject(member.context.getValue(CollaborationCandidateEvolution.TASK))
        fun access(member: AgentTeamMember) = f.access.copy(nodeId = member.memberId,
            personId = task(member).getString("member"), dependencyNodes = member.dependsOnAgentIds)
        if (phase == "seed") {
            require(store.snapshot(f.access.runId) == null) { "Recover the existing isolated fixture before seeding" }
            val staged = CandidateReviewReassignmentFixture.seed(store, f)
            val next = CandidateReviewReassignmentFixture.replacement(staged)
            val old = staged.definition.members.single { it.memberId == task(next).getJSONObject("review_reassignment").getString("node_id") }
            val original = f.draft(old)
            f.workspace.enrollPublication(access(next), CollaborationResearchStage.VERIFY, task(next))
            check(prefs.edit().putInt("seed_pid", android.os.Process.myPid()).putString("old_raw", original).commit())
        } else {
            try {
                assertNotEquals(prefs.getInt("seed_pid", -1), android.os.Process.myPid())
                store.markInterrupted(f.access.runId, System.currentTimeMillis())
                val checkpoint = requireNotNull(store.resumeCheckpoint(f.access.runId))
                val next = CandidateReviewReassignmentFixture.replacement(checkpoint)
                val old = checkpoint.definition.members.single { it.memberId == task(next).getJSONObject("review_reassignment").getString("node_id") }
                assertTrue(old.memberId in checkpoint.completed)
                val raw = requireNotNull(prefs.getString("old_raw", null))
                val rejected = f.workspace.publish(access(old), raw, candidateTask = task(old))
                assertTrue(rejected.getBoolean("retired"))
                assertTrue(f.workspace.publicationRevisions(access(old), old.memberId).isEmpty())
                assertEquals(raw, f.workspace.publicationCheckpoint(access(old))!!.getString("raw"))
                assertThrows(IllegalArgumentException::class.java) {
                    f.workspace.replayCandidateTask(access(old), task(old))
                }
                assertThrows(IllegalArgumentException::class.java) { CollaborationPublicationRecovery(f.workspace, access(old)) }
                // Idempotent enrollment and actual candidate publication after the process boundary.
                f.workspace.enrollPublication(access(next), CollaborationResearchStage.VERIFY, task(next))
                f.execute(next)
                assertNotNull(f.workspace.replayCandidateTask(access(next), task(next)))
                assertEquals(1, f.workspace.publicationRevisions(access(next), next.memberId).size)
                assertTrue(f.workspace.submitPublication(access(old), raw).getBoolean("retired"))
                assertEquals(1, f.workspace.publicationCheckpoint(access(old))!!.getLong("sequence"))
            } finally {
                teamDb.clear(); workspaceDb.clear(); evidenceDb.clear(); prefs.edit().clear().commit()
            }
        }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
            putString("retirement_phase", phase); putInt("process_id", android.os.Process.myPid())
        })
    }
}
