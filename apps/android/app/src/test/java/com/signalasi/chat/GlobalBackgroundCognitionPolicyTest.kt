package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.json.JSONObject
import org.junit.Test

class GlobalBackgroundCognitionPolicyTest {
    @Test
    fun `paired Agents require explicit background authorization`() {
        val paired = resource(
            location = AgentResourceLocation.TRUSTED_DESKTOP,
            trust = AgentResourceTrust.VERIFIED_PAIRED,
            type = AgentResourceType.REMOTE_AGENT,
            supportsBackground = true
        )

        assertFalse(GlobalBackgroundReasoningResourcePolicy.allowed(paired, false, false, false))
        assertTrue(GlobalBackgroundReasoningResourcePolicy.allowed(paired, true, false, false))
    }

    @Test
    fun `cloud and local resources keep independent privacy gates`() {
        val cloud = resource(
            location = AgentResourceLocation.CLOUD,
            trust = AgentResourceTrust.CLOUD_CONFIGURED,
            type = AgentResourceType.CLOUD_MODEL
        )
        val local = resource(
            location = AgentResourceLocation.PHONE,
            trust = AgentResourceTrust.PHONE_SYSTEM,
            type = AgentResourceType.ON_DEVICE_MODEL
        )

        assertFalse(GlobalBackgroundReasoningResourcePolicy.allowed(cloud, true, false, false))
        assertTrue(GlobalBackgroundReasoningResourcePolicy.allowed(cloud, false, true, false))
        assertFalse(GlobalBackgroundReasoningResourcePolicy.allowed(local, false, false, false))
        assertTrue(GlobalBackgroundReasoningResourcePolicy.allowed(local, false, false, true))
    }

    @Test
    fun `explicit paired authorization only opens global background conversations`() {
        val cognition = JSONObject()
            .put("type", "text")
            .put("conversation_id", "global-cognition:test")
        val evolution = JSONObject()
            .put("type", "text")
            .put("conversation_id", "self-evolution:test")

        assertTrue(SignalASITransportPrivacyPolicy.isLocalOnly(cognition))
        assertFalse(SignalASITransportPrivacyPolicy.isLocalOnly(cognition, true))
        assertTrue(SignalASITransportPrivacyPolicy.isLocalOnly(evolution, true))
    }

    @Test
    fun `fresh durable cognition outranks stale generic retries`() {
        val now = 1_800_000_000_000L
        val generic = cognitionTask(
            status = GlobalCognitionTaskStatus.WAITING_FOR_RESOURCE,
            createdAtMillis = now - 3L * 24L * 60L * 60L * 1_000L,
            attemptCount = 3,
            understanding = understanding("generic")
        )
        val durable = cognitionTask(
            status = GlobalCognitionTaskStatus.QUEUED,
            createdAtMillis = now - 60_000L,
            attemptCount = 0,
            understanding = understanding("durable").copy(
                urgency = 0.8,
                complexity = 0.7,
                durableFollowUpUseful = true,
                externalResearchUseful = true,
                riskCandidates = listOf("The background loop may stop silently")
            )
        )

        assertTrue(
            GlobalCognitionTaskPolicy.selectionScore(durable, now) >
                GlobalCognitionTaskPolicy.selectionScore(generic, now)
        )
    }

    @Test
    fun `fresh proactive research outranks a stale waiting monitor`() {
        val now = 1_800_000_000_000L
        val monitor = researchTask(
            depth = GlobalResearchDepth.CONTINUOUS_MONITOR,
            status = GlobalResearchTaskStatus.WAITING_FOR_RESOURCE,
            createdAtMillis = now - 4L * 24L * 60L * 60L * 1_000L,
            attemptCount = 4
        )
        val proactive = researchTask(
            depth = GlobalResearchDepth.PROACTIVE_INFERENCE,
            status = GlobalResearchTaskStatus.QUEUED,
            createdAtMillis = now - 60_000L,
            attemptCount = 0
        )

        assertTrue(
            GlobalResearchTaskPolicy.selectionScore(proactive, now) >
                GlobalResearchTaskPolicy.selectionScore(monitor, now)
        )
    }

    private fun resource(
        location: AgentResourceLocation,
        trust: AgentResourceTrust,
        type: AgentResourceType,
        supportsBackground: Boolean = false
    ) = AgentResourceDescriptor(
        id = "resource",
        title = "Resource",
        type = type,
        location = location,
        status = AgentConnectorStatus.AVAILABLE,
        capabilities = setOf(AgentCapability.CHAT, AgentCapability.REASONING),
        cost = AgentResourceCost.FREE,
        latency = AgentResourceLatency.FAST,
        quality = AgentResourceQuality.STRONG,
        supportsTools = true,
        targetId = "resource",
        trust = trust,
        supportsBackground = supportsBackground
    )

    private fun cognitionTask(
        status: GlobalCognitionTaskStatus,
        createdAtMillis: Long,
        attemptCount: Int,
        understanding: GlobalUnderstanding
    ) = GlobalCognitionTask(
        sourceEvent = GlobalConversationEvent(
            id = understanding.eventId,
            type = GlobalConversationEventType.MESSAGE_CREATED,
            conversationId = "conversation",
            actor = GlobalConversationActor.USER,
            content = understanding.topic,
            conversationTitle = "主动认知"
        ),
        baselineUnderstanding = understanding,
        status = status,
        attemptCount = attemptCount,
        createdAtMillis = createdAtMillis,
        updatedAtMillis = createdAtMillis
    )

    private fun understanding(id: String) = GlobalUnderstanding(
        eventId = id,
        topic = id,
        intent = "planning"
    )

    private fun researchTask(
        depth: GlobalResearchDepth,
        status: GlobalResearchTaskStatus,
        createdAtMillis: Long,
        attemptCount: Int
    ) = GlobalResearchTask(
        sourceEventId = "event",
        sourceConversationId = "conversation",
        topic = "主动认知",
        question = "主动认知是否正常工作？",
        depth = depth,
        preferredSources = listOf("official"),
        status = status,
        attemptCount = attemptCount,
        createdAtMillis = createdAtMillis,
        updatedAtMillis = createdAtMillis
    )
}
