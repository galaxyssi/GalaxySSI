package com.galaxyssi.chat

import android.os.SystemClock
import androidx.documentfile.provider.DocumentFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ObsidianKnowledgeProjectionDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun item(id: Int, source: String = "https://example.test/notes/$id") = AgentKnowledgeItem(
        "projection-item-$id", AgentKnowledgeKind.NOTE, "\u77e5\u8bc6-$id", "\u6295\u5f71\u6b63\u6587-$id",
        source = source, updatedAtMillis = 1234)

    @Test fun writesAll1201SourcesAcrossBoundedBatchesAndReopenWithoutEagerBodies() = isolated { f ->
        repeat(1201) { f.store.upsert(item(it)) }
        val initialReads = f.db.decryptedItemReads
        val initialSummaries = f.summaryReads()
        val started = SystemClock.elapsedRealtime()
        var result = f.run(12)
        assertEquals(ObsidianProjectionBatchResult(12, 0, 1189), result)
        assertEquals(12L, f.db.decryptedItemReads - initialReads)
        assertEquals(12, f.files().size)
        f.reopen()
        assertEquals(12, f.state.index().size)
        var written = 12
        var rounds = 1
        while (result.remaining > 0) {
            result = f.run(32)
            written += result.written
            assertTrue(++rounds <= 39)
        }
        assertEquals(1201, written)
        assertTrue(f.summaryReads() - initialSummaries <= 1950)
        assertEquals(1201, f.files().size)
        assertEquals(1201, f.state.index().map { it.sourceKey }.toSet().size)
        assertEquals((0..1200).map { "\u6295\u5f71\u6b63\u6587-$it" }.toSet(),
            f.files().map { it.readText().trim().substringAfterLast("\n") }.toSet())
        val before = f.db.decryptedItemReads
        var unchanged = 0
        var unchangedRounds = 0
        do {
            result = f.run(12)
            unchanged += result.unchanged
            assertEquals(0, result.written)
            assertTrue(++unchangedRounds <= 25)
        } while (result.remaining > 0)
        assertEquals(1201, unchanged)
        assertEquals(before, f.db.decryptedItemReads)
        println("OBSIDIAN_PROJECTION sources=1201 batches=$rounds first_body_reads=12 unchanged_body_reads=0 summary_reads=${f.summaryReads() - initialSummaries} elapsed_ms=${SystemClock.elapsedRealtime() - started}")
    }

    @Test fun sourceWith601ChunksIsCompleteAndOrdered() = isolated { f ->
        f.store.replaceSource("long-source", (600 downTo 0).map { id -> item(id, "long-source")
            .copy(title = "\u957f\u6587\u6863 [${id + 1}/601]", chunkIndex = id, chunkCount = 601) })
        val before = f.db.decryptedItemReads
        val spec = ObsidianKnowledgeProjection.specs(f.store).single()
        assertEquals(before, f.db.decryptedItemReads)
        val text = spec.content()
        val bodies = text.lines().filter { it.startsWith("\u6295\u5f71\u6b63\u6587-") }
        assertEquals((0..600).map { "\u6295\u5f71\u6b63\u6587-$it" }, bodies)
        assertEquals(601L, f.db.decryptedItemReads - before)
    }

    @Test fun completeCipherRevisionDetectsContentChangesWithSameTimestampAndCount() = isolated { f ->
        val original = item(1)
        f.store.upsert(original)
        val first = ObsidianKnowledgeProjection.specs(f.store).single()
        f.store.upsert(original)
        assertEquals(first.sourceRevision, ObsidianKnowledgeProjection.specs(f.store).single().sourceRevision)
        assertEquals(1, f.run(12).written)
        f.store.upsert(item(2))
        assertTrue(first.content().contains(original.content))
        f.store.upsert(original.copy(content = "\u66f4\u65b0\u7684\u6b63\u6587"))
        assertThrows(IllegalStateException::class.java) { first.content() }
        val changed = ObsidianKnowledgeProjection.specs(f.store).first { it.sourceKey == first.sourceKey }
        assertNotEquals(first.sourceRevision, changed.sourceRevision)
        assertEquals(2, f.run(12).written)
        assertTrue(f.files().any { it.readText().contains("\u66f4\u65b0\u7684\u6b63\u6587") })
        assertFalse(f.files().any { it.readText().contains(original.content) })
    }

    @Test fun privateChunksAndMetadataStayOutAndDeniedOnlySourceTerminates() = isolated { f ->
        val source = "https://example.test/article?access_token=fixture-secret"
        f.store.replaceSource(source, listOf(item(1, source).copy(title = "api_key=fixture-secret", chunkIndex = 0),
            item(2, source).copy(content = "private key is fixture-secret", chunkIndex = 1)))
        f.store.upsert(item(3).copy(content = "mqtt password is fixture-secret"))
        val result = f.run(12)
        assertEquals(ObsidianProjectionBatchResult(1, 1, 0), result)
        val file = f.files().single()
        assertFalse(file.name.contains("fixture-secret"))
        val text = file.readText()
        assertTrue(text.contains(item(1).content))
        assertFalse(text.contains("fixture-secret"))
        assertFalse(text.contains("access_token"))
        assertEquals(ObsidianProjectionBatchResult(0, 2, 0), f.run(12))
    }

    @Test fun sameNamedLocalNotesRemainDistinctAndUserEditsArePreserved() = isolated { f ->
        f.store.upsert(item(1, "").copy(title = "Same"))
        f.store.upsert(item(2, "").copy(title = "Same"))
        assertEquals(2, f.run(12).written)
        assertEquals(2, f.files().size)
        val entry = f.state.index().first()
        val file = File(f.root, entry.relativePath)
        file.writeText("user-owned edit")
        f.state.saveIndex(entry.copy(userModified = true))
        f.store.upsert(item(1, "").copy(title = "Same", content = "updated one"))
        f.store.upsert(item(2, "").copy(title = "Same", content = "updated two"))
        assertEquals(1, f.run(12).written)
        assertEquals("user-owned edit", file.readText())
    }

    @Test fun corruptedSourceDoesNotReplaceAnAlreadyProjectedFileOrAdvanceIndex() = isolated { f ->
        f.store.upsert(item(1))
        assertEquals(1, f.run(12).written)
        val old = f.state.index().single()
        val bytes = f.files().single().readBytes()
        f.db.access { it.execSQL("UPDATE knowledge_items SET header='corrupt'") }
        assertThrows(Exception::class.java) { f.run(12) }
        assertEquals(old, f.state.index().single())
        assertArrayEquals(bytes, f.files().single().readBytes())
    }

    @Test fun collidingLegacyUrlIndexIsAdoptedOnlyByItsExactOwner() = isolated { f ->
        val first = item(1)
        val second = item(2)
        f.store.upsert(first)
        f.store.upsert(second)
        val old = f.seedLegacy(second)
        assertEquals(2, f.run(12).written)
        assertEquals(2, f.files().size)
        assertNull(f.state.index(old.sourceKey))
        val secondKey = ObsidianKnowledgeIdentity.sourceKey(AgentKnowledgeSourceReference(second.source))
        assertEquals(old.relativePath, requireNotNull(f.state.index(secondKey)).relativePath)
        assertTrue(File(f.root, old.relativePath).readText().contains(second.content))
        assertFalse(File(f.root, old.relativePath).readText().contains(first.content))
    }

    @Test fun unscannedLegacyUserEditIsNotOverwrittenDuringIdentityUpgrade() = isolated { f ->
        val note = item(1)
        f.store.upsert(note)
        val old = f.seedLegacy(note)
        val file = File(f.root, old.relativePath)
        file.appendText("\nuser-owned update\n")
        assertFalse(requireNotNull(f.state.index(old.sourceKey)).userModified)
        assertEquals(ObsidianProjectionBatchResult(0, 1, 0), f.run(12))
        assertTrue(file.readText().endsWith("user-owned update\n"))
        assertEquals(1, f.files().size)
    }

    @Test fun committedFileBeforeCheckpointFailureReplaysWithoutASecondWrite() = isolated { f ->
        repeat(3) { f.store.upsert(item(it)) }
        assertThrows(IllegalStateException::class.java) { f.run(1) { error("interrupted after index commit") } }
        assertNull(f.state.projectionCheckpoint())
        f.reopen()
        assertEquals(ObsidianProjectionBatchResult(2, 1, 0), f.run(2))
        assertEquals(3, f.files().size)
    }

    @Test fun changedSourceBehindCursorIsRevisitedAfterStoreReopen() = isolated { f ->
        repeat(3) { f.store.upsert(item(it)) }
        f.run(1)
        val exported = f.state.index().single()
        val id = (0..2).first { ObsidianKnowledgeIdentity.sourceKey(AgentKnowledgeSourceReference(item(it).source)) == exported.sourceKey }
        f.store.upsert(item(id).copy(content = "\u4fee\u6539\u540e\u7684\u6b63\u6587"))
        f.reopen()
        assertEquals(0, f.run(3).remaining)
        assertTrue(File(f.root, exported.relativePath).readText().contains("\u4fee\u6539\u540e\u7684\u6b63\u6587"))
        assertEquals(3, f.files().size)
    }

    @Test fun editScanPagesReachUserChangesBeyondTheFirstEightIndexes() = isolated { f ->
        repeat(41) { f.store.upsert(item(it)) }
        f.run(32)
        f.run(32)
        val first = f.state.editScanPage(8).first.map { it.sourceKey }.toSet()
        val target = f.state.index().first { it.sourceKey !in first }
        val file = File(f.root, target.relativePath)
        file.appendText("\n\u7528\u6237\u624b\u52a8\u4fee\u6539\n")
        assertTrue(file.setLastModified(target.lastModifiedMillis + 2000))
        repeat(6) { ObsidianAndroidBridge.scanUserEdits(context, DocumentFile.fromFile(f.root), f.state) }
        assertTrue(requireNotNull(f.state.index(target.sourceKey)).userModified)
        assertTrue(f.state.candidates().any { it.sourceKey == target.sourceKey })
    }

    private inner class Fixture {
        val name = "test-obsidian-${UUID.randomUUID()}"
        val root = File(context.cacheDir, name).apply { check(mkdirs()) }
        val dbName = "$name-knowledge.db"
        var store = SQLiteAgentKnowledgeStore(context, dbName, "$name-legacy") { _, _ -> }
        val db get() = AgentKnowledgeDatabase.shared(context, dbName, "$name-legacy")
        var state = ObsidianAndroidStateStore(context, "$name-state", "$name-settings")
        var previousSummaryReads = 0L
        fun summaryReads() = previousSummaryReads + db.decryptedSourceSummaryReads
        fun files() = root.walkTopDown().filter { it.isFile && it.extension == "md" }.toList()
        fun run(budget: Int, afterWrite: () -> Unit = {}) = ObsidianKnowledgeProjection.run(store, state, root.toURI().toString(), budget,
            { spec -> ObsidianLegacyProjection.findIndex(context, DocumentFile.fromFile(root), state, spec) }) { spec, content ->
            state.saveIndex(ObsidianAndroidBridge.writeProjection(context, DocumentFile.fromFile(root), spec, content), spec.retiredSourceKey)
            afterWrite()
        }
        fun reopen() {
            previousSummaryReads += db.decryptedSourceSummaryReads
            AgentKnowledgeDatabase.release(context, dbName)
            store = SQLiteAgentKnowledgeStore(context, dbName, "$name-legacy") { _, _ -> }
            state = ObsidianAndroidStateStore(context, "$name-state", "$name-settings")
        }
        fun seedLegacy(item: AgentKnowledgeItem): ObsidianProjectionIndexEntry {
            val key = ObsidianKnowledgeIdentity.legacyKey(AgentKnowledgeSourceReference(item.source))
            val spec = ObsidianProjectionSpec(key, "60 Reading/Legacy.md", "legacy") { "" }
            val content = ObsidianAndroidBridge.note(key, "reading", item.title, item.source, item.updatedAtMillis,
                emptyList(), item.content)
            return ObsidianAndroidBridge.writeProjection(context, DocumentFile.fromFile(root), spec, content).also { state.saveIndex(it) }
        }
        fun clean() {
            AgentKnowledgeDatabase.release(context, dbName)
            context.deleteDatabase(dbName)
            AgentEncryptedPreferences(context, "$name-legacy").clear()
            AgentEncryptedPreferences(context, "$name-settings").clear()
            AgentEncryptedDatabase(context, "$name-state").clear()
            check(root.canonicalFile.parentFile == context.cacheDir.canonicalFile && root.name == name)
            check(root.deleteRecursively())
        }
    }
    private fun isolated(block: (Fixture) -> Unit) {
        val fixture = Fixture()
        try { block(fixture) } finally { fixture.clean() }
    }
}
