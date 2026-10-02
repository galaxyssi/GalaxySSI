package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Isolated fixture group; no real provider calls or existing user tasks. */
@RunWith(AndroidJUnit4::class)
class CollaborationResearchWorkspaceDeviceTest {
    @Test fun processCheckpointPhase() {
        val arguments = InstrumentationRegistry.getArguments()
        val phase = arguments.getString("workspacePhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val token = arguments.getString("workspaceToken").orEmpty()
        require(token.matches(Regex("[a-z0-9-]{1,80}")))
        val context = ApplicationProvider.getApplicationContext<Context>()
        val group = "workspace-process-fixture-$token"
        val groups = CollaborationGroupStore(context)
        val access = CollaborationWorkspaceAccess(group, "fixture-run", "fixture-turn", 1, "fixture-node", "author")
        val workspace = CollaborationResearchWorkspace(context)
        if (phase == "seed") {
            require(groups.load(group) == null) { "A fresh process fixture token is required" }
            groups.update(group) { it.copy(members = listOf(CollaborationMember("author", "Turing", "fixture", "Fixture")), coordinatorId = "author") }
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Process checkpoint")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
                .put("workspace", JSONArray().put(JSONObject().put("id", "checkpoint").put("kind", "decision")
                    .put("title", "Preserved rationale").put("body", JSONObject().put("content", "Rejected path and supporting original evidence"))))
            assertEquals("recorded", workspace.publish(access, raw.toString()).getString("status"))
        } else try {
            assertNotNull(groups.load(group))
            val reference = workspace.browse(access).revisions.single()
            val saved = workspace.read(access, reference.getString("object_id"), 1)!!
            assertEquals("Rejected path and supporting original evidence", saved.getJSONObject("body").getString("content"))
            assertEquals("member_reported_not_verified", saved.getString("evidence_state"))
        } finally { groups.remove(group) }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, android.os.Bundle().apply {
            putString("workspace_phase", phase)
            putString("fixture_pid", android.os.Process.myPid().toString())
        })
    }

    @Test fun encryptedVersionsReopenReplayAndDisappearWhenFixtureGroupIsDeleted() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val group = "workspace-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf(CollaborationMember("author", "Turing", "fixture", "Fixture")), coordinatorId = "author") }
        val access = CollaborationWorkspaceAccess(group, "run", "turn", 1, "node", "author")
        val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture design")
            .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
            .put("workspace", JSONArray().put(JSONObject().put("id", "design").put("kind", "proposal")
                .put("title", "Fixture design").put("body", JSONObject().put("content", "Uncompressed evidence ".repeat(2000)))))
        try {
            val first = CollaborationResearchWorkspace(context).publish(access, raw.toString())
            val reference = first.getJSONArray("revisions").getJSONObject(0)
            val id = reference.getString("object_id")
            val reopened = CollaborationResearchWorkspace(context)
            assertEquals(first.toString(), reopened.publish(access, raw.toString()).toString())
            assertEquals("Uncompressed evidence ".repeat(2000), reopened.read(access, id, 1)!!.getJSONObject("body").getString("content"))
            val changed = JSONObject(raw.toString())
            changed.getJSONArray("workspace").getJSONObject(0).put("object_id", id).put("base_revision", 1)
                .put("body", JSONObject().put("content", "Revision after independent challenge"))
            val reviewer = access.copy(round = 2, nodeId = "reviewer", personId = "reviewer")
            assertEquals("recorded", reopened.publish(reviewer, changed.toString()).getString("status"))
            assertEquals(reference.getString("sha256"), reopened.read(reviewer, id, 2)!!.getString("previous_sha256"))
            assertNotNull(reopened.read(reviewer, id, 1))
            assertNull(reopened.read(access.copy(nodeId = "independent", personId = "independent"), id, 1))
            groups.remove(group)
            assertNull(reopened.read(reviewer, id, 2))
            assertEquals("rejected", reopened.publish(reviewer.copy(nodeId = "late"), changed.toString()).getString("status"))
        } finally { groups.remove(group) }
    }
}
