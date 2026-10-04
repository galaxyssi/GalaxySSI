package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

/** Local synthetic regression/selection/persistence only; no models, contacts or original research. */
@RunWith(AndroidJUnit4::class)
class CollaborationRetentionDeviceTest {
    @Test fun protectedVersionsAndPinnedWorkSurviveEncryptedReopen() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "retention-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        val database = AgentEncryptedDatabase(context, "retention-checkpoint-$group")
        groups.update(group) { it.copy(members = listOf("curator", "author", "planner", "executor", "analyst", "reviewer", "lead", "peer").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "curator") }
        try {
            val f = CollaborationRetentionFixture(CollaborationResearchWorkspace(context), CollaborationEvidenceLedger(context), group)
            val first = f.retain(f.study()); val initial = f.accepted(f.select(first))
            val work = f.work(first, initial); val record = f.record()
            val admitted = CollaborationProcedureWork.plan(record, listOf(work), { f.workspace }, f.access())
            val worker = record.definition.members.last().copy(context = record.definition.members.last().context + CollaborationProcedureWork.context(admitted.work.single()))
            val pinned = record.copy(definition = record.definition.copy(members = listOf(record.definition.members.first(), worker)),
                request = record.request.copy(context = record.request.context + (CollaborationProcedureWork.CLAIMS to admitted.claims)))
            val store = EncryptedAgentTeamExecutionStore(database)
            store.create(pinned.definition, pinned.request)
            store.markInterrupted(pinned.request.runId, 1000)
            val second = f.retain(f.study(first)); val promoted = f.accepted(f.select(second, initial))
            val bad = f.study(second, editReport = { report -> val samples = report.getJSONArray("measurements"); repeat(samples.length()) { i ->
                val sample = samples.getJSONObject(i)
                if (sample.getString("case_id") == "legacy" && sample.getString("variant") == "candidate") sample.put("value", 0)
            } })
            assertEquals("regressed", bad.result.getJSONObject(HOST).getString("state"))
            assertEquals("rejected", f.lesson(bad).getString("status"))
            val rolled = f.accepted(f.rollback(promoted, initial))
            val reopened = CollaborationResearchWorkspace(context)
            assertEquals(rolled.toString(), reopened.read(f.access(), rolled.getString("object_id"), rolled.getInt("revision"))!!.toString())
            assertNotNull(reopened.read(f.access(), initial.getString("object_id"), 1))
            assertNotNull(reopened.read(f.access(), bad.result.getString("object_id"), 1))
            assertEquals(second.suite.getString("sha256"), rolled.getJSONObject(HOST).getJSONObject("suite").getString("sha256"))
            val checkpoint = requireNotNull(EncryptedAgentTeamExecutionStore(database).resumeCheckpoint(pinned.request.runId))
            assertEquals(worker.context[CollaborationProcedureWork.TASK], checkpoint.definition.members.last().context[CollaborationProcedureWork.TASK])
            val restored = pinned.copy(request = checkpoint.request)
            assertEquals(admitted.claims, CollaborationProcedureWork.plan(restored, listOf(work), { reopened }, f.access()).claims)
            assertTrue(runCatching { CollaborationProcedureWork.plan(record, listOf(f.work(first, initial, "new")), { reopened }, f.access()) }.isFailure)
            val next = CollaborationProcedureWork.plan(record, listOf(f.work(first, rolled, "new")), { reopened }, f.access())
            assertEquals(rolled.getString("sha256"), JSONObject(CollaborationProcedureWork.context(next.work.single()).getValue(CollaborationProcedureWork.TASK))
                .getJSONObject(CollaborationCapabilityChannel.FIELD).getString("sha256"))
        } finally { database.clear(); groups.remove(group) }
    }
}
