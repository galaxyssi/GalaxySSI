package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class ObsidianProjectionBatchTest {
    private fun indexed(key: String, revision: String = "r", edited: Boolean = false) =
        ObsidianProjectionIndexEntry(key, "$key.md", revision, "hash", 1, edited)

    @Test fun budgetDoesNotRenderDeferredOrUnchangedContent() {
        var rendered = 0
        var generated = 0
        val written = mutableListOf<String>()
        val specs = (0 until 1201).asSequence().map { id ->
            generated++
            ObsidianProjectionSpec("$id", "$id.md", "r") { rendered++; "text-$id" }
        }
        val result = ObsidianProjectionBatch.run(specs, 12, { key -> if (key.toInt() < 10) indexed(key) else null }) { spec, _ ->
            written += spec.sourceKey
        }
        assertEquals(1201, generated)
        assertEquals(12, rendered)
        assertEquals((10..21).map(Int::toString), written)
        assertEquals(ObsidianProjectionBatchResult(12, 10, 1179), result)
    }

    @Test fun repeatedRunsDrainAllSourcesAndNeverOverwriteUserEdits() {
        val index = mutableMapOf("500" to indexed("500", edited = true))
        var writes = 0
        var rounds = 0
        var result: ObsidianProjectionBatchResult
        do {
            result = ObsidianProjectionBatch.run((0..600).asSequence().map { id ->
                ObsidianProjectionSpec("$id", "$id.md", "r") { "text" }
            }, 32, index::get) { spec, _ -> writes++; index[spec.sourceKey] = indexed(spec.sourceKey) }
            assertTrue(++rounds <= 19)
        } while (result.remaining > 0)
        assertEquals(600, writes)
        assertEquals(601, index.size)
        assertTrue(requireNotNull(index["500"]).userModified)
    }

    @Test fun blankPrivacyFilteredSourcesDoNotLoopAsRemainingWork() {
        val specs = sequenceOf(ObsidianProjectionSpec("blocked", "blocked.md", "r") { "" },
            ObsidianProjectionSpec("safe", "safe.md", "r") { "safe" })
        val writes = mutableListOf<String>()
        val result = ObsidianProjectionBatch.run(specs, 1, { null }) { spec, _ -> writes += spec.sourceKey }
        assertEquals(listOf("safe"), writes)
        assertEquals(ObsidianProjectionBatchResult(1, 1, 0), result)
    }

    @Test fun writeFailureDoesNotClaimCompletionOrConsumeLaterBodies() {
        var rendered = 0
        assertThrows(IllegalStateException::class.java) {
            ObsidianProjectionBatch.run((0..3).asSequence().map { id ->
                ObsidianProjectionSpec("$id", "$id.md", "r") { rendered++; "body" }
            }, 12, { null }) { _, _ -> error("storage unavailable") }
        }
        assertEquals(1, rendered)
    }

    @Test fun changedDisplayTitleUpdatesTheExistingNoteWithoutCreatingADuplicatePath() {
        val original = indexed("source", "old").copy(relativePath = "10 Knowledge/Original.md")
        val renamed = ObsidianProjectionSpec("source", "10 Knowledge/Renamed.md", "new") { "new text" }
        var written: ObsidianProjectionSpec? = null
        ObsidianProjectionBatch.run(sequenceOf(renamed), 12, { original }) { spec, _ -> written = spec }
        assertEquals(original.relativePath, requireNotNull(written).relativePath)
        assertEquals("new", requireNotNull(written).sourceRevision)
    }

    @Test fun exactKnowledgeIdentityDoesNotNormalizeUrlsOrTruncateLongSources() {
        val a = AgentKnowledgeSourceReference("https://example.test/1")
        val b = AgentKnowledgeSourceReference("https://example.test/2")
        assertEquals(ObsidianKnowledgeIdentity.legacyKey(a), ObsidianKnowledgeIdentity.legacyKey(b))
        assertNotEquals(ObsidianKnowledgeIdentity.sourceKey(a), ObsidianKnowledgeIdentity.sourceKey(b))
        val prefix = "https://example.test/" + "a".repeat(2500)
        assertNotEquals(ObsidianKnowledgeIdentity.sourceKey(AgentKnowledgeSourceReference(prefix + "1")),
            ObsidianKnowledgeIdentity.sourceKey(AgentKnowledgeSourceReference(prefix + "2")))
        assertNotEquals(ObsidianKnowledgeIdentity.sourceKey(AgentKnowledgeSourceReference("identifier")),
            ObsidianKnowledgeIdentity.sourceKey(AgentKnowledgeSourceReference("", "identifier")))
        assertNotEquals(ObsidianKnowledgeIdentity.sourceKey(AgentKnowledgeSourceReference("https://example.test/A")),
            ObsidianKnowledgeIdentity.sourceKey(AgentKnowledgeSourceReference("https://example.test/a")))
    }

    @Test fun verifiedLegacyBindingRetiresOnlyTheMatchedIndexAfterWriting() {
        val legacy = indexed("legacy", "old").copy(relativePath = "60 Reading/Legacy.md")
        val next = ObsidianProjectionSpec("exact-source", "60 Reading/New.md", "new") { "body" }
        var written: ObsidianProjectionSpec? = null
        val result = ObsidianProjectionBatch.run(sequenceOf(next), 12, { null }, { legacy }) { spec, _ -> written = spec }
        assertEquals(1, result.written)
        assertEquals(legacy.relativePath, requireNotNull(written).relativePath)
        assertEquals("legacy", requireNotNull(written).retiredSourceKey)
    }
}
