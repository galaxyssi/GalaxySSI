package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/** Fixture groups and an in-process assessment tool only; no network, model, contact or device actions. */
@RunWith(AndroidJUnit4::class)
class CollaborationEvidenceLedgerDeviceTest {
    @Test fun processCheckpointPhase() {
        val arguments = InstrumentationRegistry.getArguments()
        val phase = arguments.getString("evidencePhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val token = arguments.getString("evidenceToken").orEmpty()
        require(token.matches(Regex("[a-z0-9-]{1,80}")))
        val context = ApplicationProvider.getApplicationContext<Context>()
        val group = "evidence-process-fixture-$token"
        val groups = CollaborationGroupStore(context)
        val access = CollaborationWorkspaceAccess(group, "root", "turn", 1, "member-node", "author")
        val ledger = CollaborationEvidenceLedger(context)
        if (phase == "seed") {
            require(groups.load(group) == null)
            groups.update(group) { it.copy(members = listOf(CollaborationMember("author", "Turing", "fixture", "Fixture")), coordinatorId = "author") }
            ledger.bind(789, access)
            val session = CloudImageAnnotationSession(context, emptyList(), "fixture-session", CollaborationCloudEvidence(ledger, access))
            val output = JSONObject(session.execute(ResearchEvidenceAudit.TOOL, JSONObject().put("scope", "Persistent fixture")
                .put("entities", JSONArray()).put("claims", JSONArray()).put("coverage", JSONArray())))
            assertTrue(output.has("galaxyssi_evidence_receipt"))
        } else try {
            assertEquals(access, ledger.binding(789, group, "turn"))
            val ref = ledger.browse(access).first.single()
            val saved = ledger.read(access, ref.getString("evidence_id"), ref.getString("sha256"))!!
            assertEquals("Persistent fixture", JSONObject(saved.getString("input_json")).getString("scope"))
            assertEquals("not_independently_verified", JSONObject(saved.getString("output_json")).getString("semantic_verification"))
            assertEquals("member_assessment_recorded", saved.getString("observation_kind"))
        } finally { groups.remove(group) }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, android.os.Bundle().apply {
            putString("evidence_phase", phase)
            putString("fixture_pid", android.os.Process.myPid().toString())
        })
    }

    @Test fun cloudToolReceiptBindsToRealDispatchAndSurvivesEncryptedReopen() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val group = "evidence-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf(CollaborationMember("author", "Turing", "fixture", "Fixture")), coordinatorId = "author") }
        val access = CollaborationWorkspaceAccess(group, "root", "turn", 1, "member-node", "author")
        try {
            val ledger = CollaborationEvidenceLedger(context)
            ledger.bind(456, access)
            assertEquals(access, CollaborationEvidenceLedger(context).binding(456, group, "turn"))
            val session = CloudImageAnnotationSession(context, emptyList(), "fixture-session", CollaborationCloudEvidence(ledger, access))
            val output = JSONObject(session.execute(ResearchEvidenceAudit.TOOL, JSONObject().put("scope", "Fixture scope")
                .put("entities", JSONArray()).put("claims", JSONArray()).put("coverage", JSONArray())))
            assertEquals("recorded", output.getString("status"))
            val reference = output.getJSONObject("galaxyssi_evidence_receipt")
            val saved = CollaborationEvidenceLedger(context).read(access, reference.getString("evidence_id"), reference.getString("sha256"))!!
            assertEquals("author", saved.getString("person_id"))
            assertEquals("member_assessment_recorded", saved.getString("observation_kind"))
            assertEquals("not_independently_verified", JSONObject(saved.getString("output_json")).getString("semantic_verification"))
            val workspace = CollaborationResearchWorkspace(context)
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture observation")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
                .put("workspace", JSONArray().put(JSONObject().put("id", "assessment").put("kind", "evidence")
                    .put("title", "Fixture report").put("body", JSONObject().put("content", "Reported assessment only"))
                    .put("observations", JSONArray().put(reference)))).toString()
            val publication = workspace.publish(access, raw)
            assertEquals("recorded", publication.getString("status"))
            val objectId = publication.getJSONArray("revisions").getJSONObject(0).getString("object_id")
            assertEquals(reference.getString("sha256"), workspace.read(access, objectId, 1)!!.getJSONArray("host_observations")
                .getJSONObject(0).getString("sha256"))
            groups.remove(group)
            assertNull(ledger.binding(456, group, "turn"))
            assertNull(ledger.read(access, reference.getString("evidence_id")))
        } finally { groups.remove(group) }
    }
}
