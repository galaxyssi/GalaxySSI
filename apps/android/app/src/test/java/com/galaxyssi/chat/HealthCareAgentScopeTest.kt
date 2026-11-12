package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthCareAgentScopeTest {
    private val concern = "c1a2e064-cb28-4df2-9ae0-e8fc8492a021"
    private val conversation = AgentConversation("793614b6-a121-4971-bc30-66201ac4733b", "Health discussion", 1, 1,
        privateMode = true, trackingPaused = true, globalTopicKey = HealthCareDiscussionPolicy.TOPIC_PREFIX + concern)

    @Test fun scopedPrivateConversationResolvesOnlyItsOwnConcern() {
        assertEquals(concern, HealthCareAgentScope.concernId(conversation))
        assertEquals(concern, HealthCareAgentScope.concernId(conversation.copy(selectedModelOrAgent = "Another provider")))
    }
    @Test fun ordinaryAndCollaborationConversationsNeverResolveAHealthConcern() {
        listOf("", "news", "collaboration:$concern", "prefix-health-care:$concern").forEach {
            assertNull(HealthCareAgentScope.concernId(conversation.copy(globalTopicKey = it)))
        }
    }
    @Test fun malformedScopeCannotExposeTheGlobalLatestConcern() {
        listOf("", "invalid", "$concern:extra", " $concern", "$concern ").forEach {
            assertNull(HealthCareAgentScope.concernId(conversation.copy(globalTopicKey = HealthCareDiscussionPolicy.TOPIC_PREFIX + it)))
        }
    }
    @Test fun archivedOrNoLongerPrivateConversationsDoNotShowHealthContext() {
        assertNull(HealthCareAgentScope.concernId(conversation.copy(status = AgentConversationStatus.ARCHIVED)))
        assertNull(HealthCareAgentScope.concernId(conversation.copy(privateMode = false)))
        assertNull(HealthCareAgentScope.concernId(conversation.copy(trackingPaused = false)))
    }
}
