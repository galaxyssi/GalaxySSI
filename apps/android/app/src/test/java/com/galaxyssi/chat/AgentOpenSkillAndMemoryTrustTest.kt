package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentOpenSkillAndMemoryTrustTest {
    @Test
    fun skillMarkdownRoundTripPreservesDeclarativeWorkflow() {
        val manifest = AgentSkillManifest(
            id = "daily-research",
            version = "1.2.0",
            title = "Daily research",
            description = "Research one topic with sources",
            instructions = "Search, verify, and summarize the requested topic.",
            nativeTools = setOf(AGENT_ORCHESTRATION_TOOL_ID),
            steps = listOf(AgentSkillStep("research", AGENT_ORCHESTRATION_TOOL_ID)),
            triggerExamples = listOf("Research today's AI news")
        )

        val decoded = AgentSkillMarkdownCodec.decode(AgentSkillMarkdownCodec.encode(manifest))

        assertNotNull(decoded)
        assertEquals(manifest.id, decoded?.id)
        assertEquals(manifest.version, decoded?.version)
        assertEquals(manifest.steps, decoded?.steps)
        assertFalse(decoded?.autoInvoke ?: true)
    }

    @Test
    fun privateAndDeprecatedMemoriesNeverEnterRecall() {
        val store = InMemoryAgentMemoryStore()
        val public = store.remember(AgentMemoryItem(
            id = "public-memory",
            kind = AgentMemoryKind.IDENTITY,
            value = "My name is Alex",
            key = "user.name"
        )).item!!
        val private = store.remember(AgentMemoryItem(
            id = "private-memory",
            kind = AgentMemoryKind.PREFERENCE,
            value = "My private preference is quiet mode",
            key = "user.private.preference",
            privateMemory = true
        )).item!!

        assertEquals(listOf(public.id), store.recall("Alex").map(AgentMemoryItem::id))
        assertTrue(store.recall("quiet mode").isEmpty())
        assertTrue(store.setPrivate(public.id, true))
        assertTrue(store.recall("Alex").isEmpty())
        assertTrue(store.setPrivate(public.id, false))
        assertTrue(store.deprecateById(public.id))
        assertTrue(store.setPrivate(public.id, true))
        assertTrue(store.recall("Alex").isEmpty())
        assertTrue(store.snapshot().historyItems.any { it.id == public.id && it.privateMemory })
        assertTrue(store.snapshot().activeItems.any { it.id == private.id && it.privateMemory })
    }
}
