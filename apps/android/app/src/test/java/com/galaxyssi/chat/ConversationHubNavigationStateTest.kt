package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ConversationHubNavigationStateTest {
    @Test fun anchorFollowsConversationAfterNewRowsArrive() {
        val anchor = ConversationHubScrollAnchor("agent:b", 37, 1)
        assertEquals(3, anchor.restoredPosition(listOf("new", "contact", "agent:a", "agent:b")))
        assertEquals(37, anchor.topOffset)
    }
    @Test fun missingAnchorFallsBackToNearestPosition() {
        val anchor = ConversationHubScrollAnchor("deleted", 0, 8)
        assertEquals(2, anchor.restoredPosition(listOf("a", "b", "c")))
    }
    @Test fun emptyListDoesNotProduceNegativePosition() {
        assertEquals(0, ConversationHubScrollAnchor("deleted", 0, 8).restoredPosition(emptyList()))
    }
    @Test fun exactAnchorWinsOverOldPosition() {
        assertEquals(0, ConversationHubScrollAnchor("a", 12, 20).restoredPosition(listOf("a", "b")))
    }
    @Test fun contactAndAgentAnchorsRemainDistinct() {
        assertEquals(1, ConversationHubScrollAnchor("conversation:AGENT:x", 0)
            .restoredPosition(listOf("conversation:CONTACT:x", "conversation:AGENT:x")))
    }
    @Test fun navigationSnapshotDoesNotContainMessageOrViewFields() {
        val allowed = setOf(Boolean::class.javaPrimitiveType, Int::class.javaPrimitiveType,
            ConversationHubTab::class.java, ConversationHubItemKind::class.java, ConversationHubScrollAnchor::class.java)
        assertTrue(ConversationHubNavigationState::class.java.declaredFields
            .filterNot { java.lang.reflect.Modifier.isStatic(it.modifiers) }.all { it.type in allowed })
    }
}
