package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.metrics.*
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgeSourceTimingDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val points = mutableListOf<AgentTimingPoint>()
    private fun timing() = KnowledgeSourceWriteTiming(AgentRuntimeTiming({ trace, stage, operation, outcome, at ->
        points += AgentTimingPoint(trace, "a".repeat(32), stage, at, 0, operation, outcome = outcome)
    }))
    private fun item(id: String = "one", source: String = "private source") =
        AgentKnowledgeItem(id = id, kind = AgentKnowledgeKind.NOTE, title = "private title", content = "private body", source = source)
    private fun metric(phase: String) = AgentLatencyContract.summarize(points)
        .getValue("phone_runtime_knowledge_source_${phase}_ms")
    private fun fixture(publish: (KnowledgeSourceMutation) -> Unit = {}, block: (SQLiteAgentKnowledgeStore) -> Unit) {
        val name = "test-knowledge-timing-${UUID.randomUUID()}.db"
        val store = SQLiteAgentKnowledgeStore(context, name, "legacy-$name", publishSource = publish) { _, _ -> }
        try { block(store) } finally { store.close() }
    }

    @Test fun productionReplacementReportsAllSevenStagesAndPersistsTheBody() = fixture { store ->
        store.replaceSource("private source", sequenceOf(item()), timing())
        for (phase in listOf("total", "stage", "prepare", "commit", "ownership", "apply", "observe")) {
            assertEquals(phase, 1, metric(phase).count)
            assertEquals(phase, 0, metric(phase).unsuccessful)
        }
        assertEquals("private body", store.findByIds(setOf("one")).single().content)
        assertEquals(1, points.map { it.traceId }.distinct().size)
        assertFalse(points.toString().contains("private"))
        assertTrue(metric("commit").p95Ms!! >= metric("ownership").p95Ms!! + metric("apply").p95Ms!!)
    }

    @Test fun stageFailureDoesNotPrepareOrPublishAndPreservesItsException() = fixture { store ->
        val error = IllegalStateException("private input failed")
        val incoming = sequence { yield(item()); throw error }
        try { store.replaceSource("private source", incoming, timing()); fail("Expected input failure") }
        catch (actual: Exception) { assertSame(error, actual) }
        assertEquals(1, metric("stage").unsuccessful); assertEquals(1, metric("total").unsuccessful)
        assertEquals(0, metric("prepare").count); assertEquals(0L, store.stats().itemCount)
    }

    @Test fun ownershipFailureNeverAppearsAsSuccessfulApply() = fixture { store ->
        store.upsert(item(source = "other source"))
        try { store.replaceSource("private source", sequenceOf(item()), timing()); fail("Expected ownership failure") }
        catch (_: IllegalArgumentException) { }
        assertEquals(1, metric("ownership").unsuccessful); assertEquals(1, metric("commit").unsuccessful)
        assertEquals(0, metric("apply").count); assertEquals(0, metric("observe").count)
        assertEquals("other source", store.findByIds(setOf("one")).single().source)
    }

    @Test fun observationFailureIsDistinctFromTheAlreadyCommittedWrite() {
        val error = IllegalStateException("private observer failed")
        fixture(publish = { throw error }) { store ->
            try { store.replaceSource("private source", sequenceOf(item()), timing()); fail("Expected observation failure") }
            catch (actual: Exception) { assertSame(error, actual) }
            assertEquals(1, metric("commit").count); assertEquals(1, metric("observe").unsuccessful)
            assertEquals(1, metric("total").unsuccessful)
            assertEquals(1, store.findByIds(setOf("one")).size)
        }
    }

    @Test fun emptyInputHasNoCommitAndBrokenSinkDoesNotLoseTheWrite() = fixture { store ->
        store.replaceSource("private source", emptySequence(), timing())
        assertEquals(1, metric("stage").count); assertEquals(0, metric("commit").count)
        val broken = KnowledgeSourceWriteTiming(AgentRuntimeTiming({ _, _, _, _, _ -> error("sink") }))
        store.replaceSource("private source", sequenceOf(item()), broken)
        assertEquals(1, store.findByIds(setOf("one")).size)
    }
}
