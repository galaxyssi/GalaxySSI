package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CloudResearchCheckpointTest {
    private val scope = AgentModelLoopScope("provider", "conversation", "turn", "task", "workspace", "research", "action")

    @Test fun partialBatchSurvivesRestartAndCanFinishWithoutRepeatingSearch() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        val args = JSONObject().put("query", "chip benchmarks")
        journal.withLease(scope) { records ->
            CloudResearchCheckpoint(records, "binding").record("web_search", args, "completed-source")
        }
        journal.withLease(scope) { records ->
            val checkpoint = CloudResearchCheckpoint(records, "binding")
            val saved = checkpoint.restore().single()
            val progress = CloudWebToolLoopProgress()
            progress.record(saved.tool, saved.arguments, saved.output)
            assertEquals("completed-source", progress.cached("web_search", args))
            checkpoint.record("web_fetch", JSONObject().put("url", "https://example.com"), "page")
            checkpoint.complete("Grounded answer")
        }
        journal.withLease(scope) { records ->
            val checkpoint = CloudResearchCheckpoint(records, "binding")
            assertEquals(2, checkpoint.restore().size)
            assertEquals("Grounded answer", checkpoint.finalAnswer())
        }
    }

    @Test fun sideEffectsAreNeverStoredAsReplayableObservations() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        journal.withLease(scope) { records ->
            val checkpoint = CloudResearchCheckpoint(records, "binding")
            for (tool in listOf("web_watch", "write_file", "annotate_image")) checkpoint.record(tool, JSONObject(), "done")
            checkpoint.record("web_cache", JSONObject().put("action", "clear"), "done")
        }
        assertFalse(journal.hasRecords(scope))
    }

    @Test fun qualityUpgradeReusesEvidenceButNotThePreviouslyUncheckedAnswer() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        journal.withLease(scope) { records ->
            val checkpoint = CloudResearchCheckpoint(records, "binding")
            checkpoint.record("web_search", JSONObject(), "source")
            checkpoint.complete("Old unreviewed answer")
        }
        journal.withLease(scope) { records ->
            val checkpoint = CloudResearchCheckpoint(records, "binding")
            assertEquals(1, checkpoint.restore().size)
            assertNull(checkpoint.finalAnswer("galaxyssi.research-quality/1.0"))
            checkpoint.complete("Reviewed answer", JSONObject().put("contract", "galaxyssi.research-quality/1.0"))
        }
        journal.withLease(scope) { records ->
            val checkpoint = CloudResearchCheckpoint(records, "binding")
            checkpoint.restore()
            assertEquals("Reviewed answer", checkpoint.finalAnswer("galaxyssi.research-quality/1.0"))
            assertNull(checkpoint.finalAnswer("galaxyssi.research-quality/2.0"))
            val result = JSONObject(records.read("final:galaxyssi.research-quality/1.0")!!)
            assertEquals("not_confirmed", result.getString("delivery"))
        }
    }

    @Test fun changedInputFailsClosedAndOtherConversationCannotReadResults() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        journal.withLease(scope) { CloudResearchCheckpoint(it, "first").record("web_search", JSONObject(), "source") }
        journal.withLease(scope) { records ->
            assertThrows(IllegalStateException::class.java) { CloudResearchCheckpoint(records, "different").restore() }
        }
        journal.withLease(scope.copy(conversation = "other")) {
            assertTrue(CloudResearchCheckpoint(it, "first").restore().isEmpty())
        }
    }

    @Test fun corruptObservationCannotBeRestoredAsExecutableMutation() = runBlocking {
        val journal = InMemoryAgentModelLoopJournal()
        journal.withLease(scope) { records ->
            records.write("initial", """{"binding":"first"}""")
            records.write("observation:0", """{"tool":"web_watch","arguments":{},"output":"done"}""")
            assertThrows(IllegalStateException::class.java) { CloudResearchCheckpoint(records, "first").restore() }
            Unit
        }
    }
}
