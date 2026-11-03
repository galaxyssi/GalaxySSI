package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local production-handler checks; no models, network or device-control actions. */
@RunWith(AndroidJUnit4::class)
class CollaborationAssessmentPreflightDeviceTest {
    @Test fun rejectedDraftCanBeRepairedWithoutPublicationAndPauseStillApplies() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "assessment-preflight-${UUID.randomUUID()}"
        val run = "$group-run"
        val groups = CollaborationGroupStore(context)
        val control = AgentTeamDurableControl(context)
        groups.update(group) { it.copy(members = listOf(CollaborationMember("planner", "Planner", "fixture", "Fixture")),
            coordinatorId = "planner") }
        val access = CollaborationWorkspaceAccess(group, run, "turn", 1, "planning", "planner")
        fun check(raw: String) = JSONObject(CollaborationMilestoneTool.execute(context, access,
            JSONObject().put("mode", CollaborationAssessmentPreflight.MODE).put("artifact", raw)))
        try {
            val draft = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Synthetic draft")
                .put("decision", "continue").put("work", JSONArray()).put("blockers", JSONArray())
            val rejected = check(draft.toString())
            assertTrue(rejected.getBoolean("success"))
            assertFalse(rejected.getBoolean("schema_valid"))
            assertEquals("$.criteria", rejected.getJSONObject("failure").getString("path"))
            draft.put("criteria", JSONArray().put(JSONObject().put("id", "fixture")
                .put("requirement", "Synthetic fixture only").put("status", "open").put("evidence", JSONArray())))
            val repaired = check(draft.toString())
            assertTrue(repaired.toString(), repaired.getBoolean("schema_valid"))
            assertFalse(repaired.getBoolean("committed"))
            assertFalse(repaired.getBoolean("goal_accepted"))
            assertFalse(repaired.getBoolean("assignment_completed"))
            assertEquals(repaired.toString(), check(draft.toString()).toString())
            val reopened = CollaborationResearchWorkspace(context)
            assertNull(reopened.publicationCheckpoint(access))
            assertFalse(reopened.publicationCapability(access).getBoolean("publish_allowed"))
            assertEquals(0, reopened.milestones(access).getJSONArray("milestones").length())
            control.set(run, AgentTeamUserControl.PAUSE)
            assertEquals("rejected", check(draft.toString()).getString("status"))
            control.set(run, AgentTeamUserControl.RUN)
            assertTrue(check(draft.toString()).getBoolean("schema_valid"))
            groups.update(group) { it.copy(members = emptyList()) }
            assertEquals("rejected", check(draft.toString()).getString("status"))
        } finally {
            control.remove(run)
            CollaborationResearchWorkspace.remove(context, group)
            groups.remove(group)
        }
    }
}
