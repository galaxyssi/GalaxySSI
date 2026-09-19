package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ResearchCorpusDeviceTest {
    @Test fun tenThousandSourceReceiptsArePagedDeduplicatedAndDeleted() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val conversation = "research-corpus-fixture-${UUID.randomUUID()}"
        val turn = "fixture-turn"
        try {
            repeat(100) { batch ->
                val delta = AgentResearchTrace(listOf("query $batch"), (0 until 100).map { index ->
                    AgentResearchTrace.Source("https://example.org/source/${batch * 100 + index}", "Source ${batch * 100 + index}")
                })
                AgentResearchTraceStore.merge(context, conversation, turn, delta)
                AgentResearchTraceStore.merge(context, conversation, turn, delta)
            }
            val first = AgentResearchTraceStore.read(context, conversation, turn)
            assertEquals(10_000, first.displayedSourceCount)
            assertEquals(50, first.sources.size)
            assertEquals(100, first.queries.size)
            assertFalse(first.truncated)
            val next = AgentResearchTraceStore.read(context, conversation, turn, 100)
            assertEquals(first.sources, next.sources.take(50))
            assertEquals(100, next.sources.map { it.url }.toSet().size)
            val source = first.sources.first().copy(status = "body_retrieved")
            AgentResearchTraceStore.merge(context, conversation, turn, AgentResearchTrace(sources = listOf(source)))
            val updated = AgentResearchTraceStore.read(context, conversation, turn)
            assertEquals(10_000, updated.displayedSourceCount)
            assertEquals("body_retrieved", updated.sources.first().status)
            assertFalse(AgentResearchTraceStore.read(context, conversation, "other-turn").visible)
        } finally {
            AgentResearchTraceStore.delete(context, conversation)
        }
        assertFalse(AgentResearchTraceStore.read(context, conversation, turn).visible)
    }
}
