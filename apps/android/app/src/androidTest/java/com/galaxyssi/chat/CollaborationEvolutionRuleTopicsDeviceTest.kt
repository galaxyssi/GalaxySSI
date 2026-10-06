package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local schema reads only; no model requests or external task effects. */
@RunWith(AndroidJUnit4::class)
class CollaborationEvolutionRuleTopicsDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun cloudAndNativeReadEveryTopicCompletelyThroughScopedPagination() = fixture { group, access ->
        val source = AgentTeamDispatchIds.sourceMessageId("rule-topics:$group")
        CollaborationEvidenceLedger(context).bind(source, access)
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
            .subset { it.id == CollaborationRecallNativeTool.ID }
        val invocation = AgentNativeToolInvocationContext(conversationId = group, turnId = "turn", collaborationSourceMessageId = source)
        CollaborationEvolutionProtocol.topicIds().forEach { topic ->
            val cloud = StringBuilder(); val native = StringBuilder()
            var offset: Int? = 0
            while (offset != null) {
                val input = JSONObject().put("mode", "evolution_rules").put("topic", topic).put("offset", offset)
                val page = JSONObject(CollaborationCloudRecall.execute(context, access, input))
                assertEquals(page.toString(), "returned", page.getString("status"))
                val result = registry.invoke(CollaborationRecallNativeTool.ID,
                    mapOf("mode" to "evolution_rules", "topic" to topic, "offset" to offset), invocation)
                assertTrue(result.toJson(), result.isSuccess)
                assertEquals(topic, result.output["topic"])
                assertEquals("host_schema_not_execution_authority", result.output["trust"])
                assertEquals(page.getString("content"), result.output["content"])
                cloud.append(page.getString("content")); native.append(result.output["content"])
                offset = if (page.isNull("next_offset")) null else page.getInt("next_offset")
                assertEquals(offset, (result.output["next_offset"] as? Number)?.toInt())
            }
            assertEquals(CollaborationEvolutionProtocol.rules(topic).toString(), cloud.toString())
            assertEquals(cloud.toString(), native.toString())
        }
    }

    @Test fun invalidSelectorsAndRevokedMembersCannotReadRules() = fixture { group, access ->
        val valid = JSONObject().put("mode", "evolution_rules").put("topic", "catalog")
        val unknown = JSONObject(CollaborationCloudRecall.execute(context, access, JSONObject(valid.toString()).put("topic", "unknown")))
        assertEquals("failed", unknown.getString("status"))
        assertTrue(unknown.getJSONObject("error").getString("message").contains("topic=catalog"))
        listOf(JSONObject(valid.toString()).put("topic", 1), JSONObject(valid.toString()).put("offset", -1),
            JSONObject(valid.toString()).put("cursor", ""), JSONObject(valid.toString()).put("mode", "workspace")).forEach {
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, access, it)).getString("status"))
        }
        CollaborationGroupStore(context).update(group) { it.copy(members = emptyList()) }
        assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, access, valid)).getString("status"))
        assertFalse(CollaborationScopedRecall.read(context, mapOf("mode" to "evolution_rules", "topic" to "catalog"), access).isSuccess)
    }

    private fun fixture(block: (String, CollaborationWorkspaceAccess) -> Unit) {
        val group = "rule-topics-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf(CollaborationMember("reader", "Reader", "fixture", "Fixture")), coordinatorId = "reader") }
        try { block(group, CollaborationWorkspaceAccess(group, "run", "turn", 1, "reader", "reader")) }
        finally { groups.remove(group) }
    }
}
