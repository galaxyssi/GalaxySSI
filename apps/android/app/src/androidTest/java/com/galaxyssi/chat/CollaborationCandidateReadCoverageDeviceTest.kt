package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real encrypted production stores; no provider calls or user conversation access. */
@RunWith(AndroidJUnit4::class)
class CollaborationCandidateReadCoverageDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun incompleteOriginalIsRejectedThenReopenedDraftRecoversWithoutRepeatingWork() = verify(false)

    @Test fun remotePreparedPagesRequireConfirmedDeliveryBeforeReviewCanBePublished() = verify(true)

    private fun verify(remoteConfirmation: Boolean) {
        val group = "candidate-read-${UUID.randomUUID()}"
        val previous = AgentTranscriptStore(context).activeConversation().id
        val author = CollaborationWorkspaceAccess(group, "run", "turn", 0, "author", "author")
        val reviewer = author.copy(round = 1, nodeId = "review", personId = "reviewer")
        val inspector = reviewer.copy(round = 2, nodeId = "inspect")
        try {
            CollaborationGroupStore(context).update(group) { it.copy(members = listOf(
                CollaborationMember("author", "Fixture author", "fixture", "Fixture"),
                CollaborationMember("reviewer", "Fixture reviewer", "fixture", "Fixture")), coordinatorId = "author") }
            val ledger = CollaborationEvidenceLedger(context)
            val workspace = CollaborationResearchWorkspace(context)
            val source = ledger.record(author, "original", "original_check", "{}",
                JSONObject().put("text", "fixture source ".repeat(2000)).toString(), 1, 2)
            val proposal = JSONObject().put("id", "candidate").put("kind", "candidate").put("title", "Fixture candidate")
                .put("body", JSONObject().put("content", "Original proposal").put("candidate", JSONObject()
                    .put("operation", "propose").put("rationale", "Validate source coverage")
                    .put("criteria", JSONArray().put("Accuracy"))))
            val target = workspace.publish(author, raw(proposal)).getJSONArray("revisions").getJSONObject(0)
            val task = JSONObject().put("operation", "review").put("target", target).put("member", reviewer.personId)
                .put("group_id", group).put("run_id", "run").put("turn_id", "turn")
                .put("criterion", JSONObject().put("id", "accuracy").put("requirement", "Accuracy").put("verification", "documentary")
                    .put("required_observations", JSONArray().put(JSONObject().put("origin", "android_cloud_tool").put("tool", "original_check"))))
            val review = JSONObject().put("id", "review").put("kind", "candidate_event").put("title", "Fixture review")
                .put("observations", JSONArray().put(source)).put("body", JSONObject().put("candidate_event", JSONObject()
                    .put("operation", "review").put("targets", JSONArray().put(target)).put("criterion", "Accuracy")
                    .put("check", "Read the exact original").put("rationale", "Local fixture only")
                    .put("outcome", "supported").put("unresolved", JSONArray())))
            val response = raw(review)
            workspace.enrollPublication(reviewer, CollaborationResearchStage.VERIFY, task)
            val first = ledger.readPage(reviewer, source.getString("evidence_id"), source.getString("sha256"),
                recordCoverage = !remoteConfirmation)!!
            assertNotNull(first.next)
            assertFalse(CollaborationPublicationRecovery(workspace, reviewer).accept(response))
            assertTrue(workspace.publicationRevisions(inspector, reviewer.nodeId).isEmpty())

            val reopenedLedger = CollaborationEvidenceLedger(context)
            var offset: Int? = 0
            var pages = 0
            while (offset != null) {
                val page = reopenedLedger.readPage(reviewer, source.getString("evidence_id"), source.getString("sha256"),
                    offset, recordCoverage = !remoteConfirmation)!!
                if (remoteConfirmation) {
                    assertFalse(CollaborationPublicationRecovery(CollaborationResearchWorkspace(context), reviewer).accept(response))
                    reopenedLedger.confirmPage(reviewer, source.getString("evidence_id"), source.getString("sha256"), offset,
                        MqttImmutableContent.sha256(page.content))
                }
                pages++
                offset = page.next
            }
            assertTrue(pages > 1)
            val reopened = CollaborationResearchWorkspace(context)
            assertTrue(CollaborationPublicationRecovery(reopened, reviewer).accept(response))
            val saved = reopened.publicationRevisions(inspector, reviewer.nodeId).single()
            val frozen = saved.getJSONArray("host_observations").getJSONObject(0).getJSONObject(CollaborationEvidenceReadCoverage.FIELD)
            assertTrue(frozen.getBoolean("complete"))
            assertEquals(frozen.getInt("total_characters"), frozen.getInt("covered_characters"))
            assertEquals("scoped_pages", frozen.getString("mode"))
            assertNotNull(reopened.replayCandidateTask(reviewer, task))
            assertEquals(1, reopened.publicationRevisions(inspector, reviewer.nodeId).size)
            assertTrue(reopened.candidateReviewApplies(inspector, CollaborationResearchCandidates.reference(saved)))
            assertEquals(previous, AgentTranscriptStore(context).activeConversation().id)
        } finally {
            CollaborationGroupStore(context).remove(group)
            CollaborationEvidenceLedger.remove(context, group)
        }
    }

    private fun raw(item: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Dedicated local fixture").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("workspace", JSONArray().put(item)).toString()
}
