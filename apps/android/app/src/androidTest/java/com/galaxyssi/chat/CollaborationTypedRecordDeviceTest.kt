package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local durable publication only; no model, network, tool execution or personal data. */
@RunWith(AndroidJUnit4::class)
class CollaborationTypedRecordDeviceTest {
    @Test fun typedSourceWithoutProseSurvivesReopenAndInvalidContentIsNotSilentlyDropped() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "typed-record-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf(CollaborationMember("author", "Author", "fixture", "Fixture")),
            coordinatorId = "author") }
        val access = CollaborationWorkspaceAccess(group, "$group-run", "turn", 1, "publish", "author")
        val kind = CollaborationExecutableTool.TOOL
        val source = "def run(parameters):\n    return parameters['value']\n"
        val spec = JSONObject().put("name", "Identity fixture").put("purpose", "Preserve synthetic input")
            .put("language", "python").put("source", source).put("environment", "python-standard-library")
            .put("dependencies", "Python standard library").put("applies_when", "Synthetic integer input")
            .put("avoid_when", "Other values").put("side_effects", "None")
            .put("input_schema", JSONObject().put("type", "object")
                .put("properties", JSONObject().put("value", JSONObject().put("type", "integer")))
                .put("required", JSONArray().put("value")).put("additional_properties", false))
        fun publication(id: String, body: JSONObject) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", "Device persistence fixture").put("workspace", JSONArray().put(JSONObject()
                .put("id", id).put("kind", kind).put("title", id).put("body", body))).toString()
        try {
            val body = JSONObject().put(kind, spec)
            val raw = publication("source", body)
            val first = CollaborationResearchWorkspace(context).publish(access, raw)
            assertEquals(first.toString(), "recorded", first.getString("status"))
            val ref = first.getJSONArray("revisions").getJSONObject(0)
            val reopened = CollaborationResearchWorkspace(context)
            val saved = reopened.read(access.copy(round = 2), ref.getString("object_id"), ref.getInt("revision"))!!
            assertEquals(body.toString(), saved.getJSONObject("body").toString())
            assertEquals(source, saved.getJSONObject("body").getJSONObject(kind).getString("source"))
            assertFalse(saved.getJSONObject("body").has("content"))
            val replay = reopened.publish(access, raw).getJSONArray("revisions").getJSONObject(0)
            assertEquals(ref.getString("sha256"), replay.getString("sha256"))
            val invalid = reopened.publish(access.copy(nodeId = "invalid"),
                publication("invalid", JSONObject().put(kind, spec).put("content", 42)))
            assertEquals("rejected", invalid.getString("status"))
            assertEquals("/body/content", invalid.getJSONObject(CollaborationRecordValidation.DETAIL).getString("path"))
        } finally {
            CollaborationResearchWorkspace.remove(context, group)
            groups.remove(group)
        }
    }
}
