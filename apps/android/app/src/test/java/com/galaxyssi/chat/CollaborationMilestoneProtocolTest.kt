package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationMilestoneProtocolTest {
    @Test fun publicationRetryAndListCanRefreshWithoutInvalidatingSearchCache() {
        val progress = CloudWebToolLoopProgress()
        val input = JSONObject().put("mode", "list")
        val query = JSONObject().put("query", "fixture")
        progress.record("web_search", query, "saved search")
        progress.record(CollaborationMilestoneTool.NAME, input, "old list or uncertain failure")
        progress.invalidate(CollaborationMilestoneTool.NAME, input)
        assertNull(progress.cached(CollaborationMilestoneTool.NAME, input))
        assertEquals("saved search", progress.cached("web_search", query))
        assertTrue(progress.record(CollaborationMilestoneTool.NAME, input, "fresh receipt"))
        assertEquals("fresh receipt", progress.cached(CollaborationMilestoneTool.NAME, input))
        assertFalse(CloudResearchCheckpoint.isReadOnly(CollaborationMilestoneTool.NAME, input))
    }

    private fun request() = JSONObject().apply {
        AgentResultRecoveryClient.FIELDS.forEach { put(it, if (it == "agent_id") "codex" else it) }
        put("execution_generation", 1).put("expires_at", 30000L).put("request_id", "nonce")
        put("type", AndroidCollaborationRemoteMilestone.REQUEST).put("contract", AndroidCollaborationRemoteMilestone.CONTRACT)
        put("phase", "publish").put("arguments", JSONObject().put("mode", "publish")
            .put("milestone_id", "candidate-v1").put("artifact", "{\"format\":\"galaxyssi.research-artifact.v1\"}"))
    }

    @Test fun publicationCannotUseReadOnlyRpcOrUnboundExpiredEnvelope() {
        assertTrue(AndroidCollaborationRemoteMilestone.valid(request(), 10000))
        assertFalse(CollaborationRemoteRecallProtocol.valid(request(), 10000))
        for (field in AgentResultRecoveryClient.FIELDS + listOf("execution_generation", "request_id", "contract", "phase", "arguments"))
            assertFalse(field, AndroidCollaborationRemoteMilestone.valid(request().apply { remove(field) }, 10000))
        for ((field, value) in listOf("phase" to "read", "agent_id" to "other", "contract" to CollaborationRemoteRecallProtocol.CONTRACT,
            "expires_at" to 10000L, "expires_at" to 71000L, "execution_generation" to 1.5))
            assertFalse(field, AndroidCollaborationRemoteMilestone.valid(request().put(field, value), 10000))
        assertFalse(AndroidCollaborationRemoteMilestone.valid(request().put("delivery", JSONObject()), 10000))
        assertTrue(MqttQueryDeliveryPolicy.isTransient(AndroidCollaborationRemoteMilestone.RESPONSE))
    }

    @Test fun allCloudProvidersAdvertiseSameExplicitCapabilityAndRepairRemainsReadOnly() {
        for (provider in ModelStreamProvider.entries) {
            val prepared = PreparedCloudConversationStream("id", provider, "https://test.invalid", emptyMap(), JSONObject(), JSONArray(), "messages")
            CollaborationMilestoneTool.install(prepared)
            val encoded = prepared.body.toString()
            assertTrue(provider.name, encoded.contains(CollaborationMilestoneTool.NAME))
            assertTrue(encoded.contains("milestone_id")); assertTrue(encoded.contains("artifact"))
            CloudConversationStreamEngine.restrictPublicationRepairTools(prepared)
            assertFalse(prepared.body.toString().contains(CollaborationMilestoneTool.NAME))
            assertTrue(prepared.body.toString().contains(CollaborationCloudRecall.NAME))
        }
    }

    @Test fun malformedFinalMilestoneReferencesAreDiagnosedAsFieldsNotInventedObjects() {
        val original = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "result")
            .put("candidates", JSONArray()).put("findings", JSONArray())
        for (value in listOf<Any>("bad", JSONObject(), JSONArray(listOf(1)), JSONArray(listOf("same", "same")))) {
            assertNull(CollaborationResearchArtifact.decode(JSONObject(original.toString()).put("milestones", value).toString()))
            assertTrue(CollaborationResearchArtifact.validationError(JSONObject(original.toString()).put("milestones", value).toString()).isNotBlank())
        }
    }
}
