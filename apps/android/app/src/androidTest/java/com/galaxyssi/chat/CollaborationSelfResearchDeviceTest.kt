package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

/** Local synthetic evidence and encrypted restart only. No provider, native action or original research. */
@RunWith(AndroidJUnit4::class)
class CollaborationSelfResearchDeviceTest {
    @Test fun researchCycleAdoptionAndAdmittedActionSurviveEncryptedReopen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "self-research-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        val database = AgentEncryptedDatabase(context, "self-research-checkpoint-$group")
        groups.update(group) { it.copy(members = listOf("curator", "author", "planner", "executor", "analyst", "reviewer", "searcher", "lead", "peer").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "curator") }
        try {
            val f = CollaborationRetentionFixture(CollaborationResearchWorkspace(context), CollaborationEvidenceLedger(context), group)
            val s = CollaborationSelfResearchFixture(f)
            val retained = s.retain(s.study()); val channel = f.accepted(f.select(retained))
            val review = f.accepted(s.review(s.adoption(retained, channel), retained.study.observations))
            val cycle = s.next(review)
            val work = s.work(cycle)
            val admitted = CollaborationGoalLoop.advance(s.completed(s.record(), "lead", s.report(listOf(work)), true),
                "lead", 1000, true, candidateWorkspace = { f.workspace })!!
            val worker = admitted.definition.members.single { CollaborationSelfResearchWork.TASK in it.context }
            val store = EncryptedAgentTeamExecutionStore(database)
            store.create(admitted.definition, admitted.request)
            store.markInterrupted(admitted.request.runId, 1100)
            val restored = requireNotNull(EncryptedAgentTeamExecutionStore(database).resumeCheckpoint(admitted.request.runId))
            assertEquals(worker.context[CollaborationSelfResearchWork.TASK], restored.definition.members.single {
                it.memberId == worker.memberId }.context[CollaborationSelfResearchWork.TASK])
            assertEquals(admitted.request.context[CollaborationSelfResearchWork.CLAIMS], restored.request.context[CollaborationSelfResearchWork.CLAIMS])
            val reopened = CollaborationResearchWorkspace(context)
            assertEquals(review.toString(), reopened.read(f.access(), review.getString("object_id"), 1)!!.toString())
            assertEquals(retained.study.result.toString(), reopened.read(f.access(), retained.study.result.getString("object_id"), 1)!!.toString())
            assertFalse(review.getJSONObject(HOST).getBoolean("goal_verified"))
            val record = admitted.copy(request = restored.request)
            val same = CollaborationSelfResearchWork.plan(record, listOf(work), { reopened }, f.access())
            assertEquals(admitted.request.context[CollaborationSelfResearchWork.CLAIMS], same.claims)
            val renamed = JSONObject(work.toString()).put("id", "renamed")
            assertTrue(runCatching { CollaborationSelfResearchWork.plan(record, listOf(renamed), { reopened }, f.access()) }.isFailure)
        } finally { database.clear(); groups.remove(group) }
    }
}
