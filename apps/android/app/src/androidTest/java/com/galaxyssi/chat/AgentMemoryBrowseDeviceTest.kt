package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentMemoryBrowseDeviceTest {
    private fun fixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val fixture = MemoryDeletionDeviceFixture()
        try { block(fixture) } finally { fixture.clear() }
    }
    private fun rows(size: Int) = (0 until size).map { deletionMemory(it).copy(timestampMillis = (it / 3).toLong(), important = it % 7 == 0) }
    private fun all(f: MemoryDeletionDeviceFixture, request: AgentMemoryBrowseRequest): List<AgentMemoryBrowseEntry> {
        val result = mutableListOf<AgentMemoryBrowseEntry>()
        var cursor: AgentMemoryBrowseCursor? = null
        do {
            val page = f.reopen().browse(request.copy(cursor = cursor))
            assertTrue(page.entries.size <= request.limit)
            result += page.entries
            cursor = page.next
        } while (cursor != null)
        return result
    }

    @Test fun forwardAndBackwardPagesKeepStableOrderingWithoutLossOrDuplication() = fixture { f ->
        f.store.saveItems(rows(257))
        val expected = f.store.snapshot().activeItems
        val actual = all(f, AgentMemoryBrowseRequest())
        assertEquals(expected, actual.map { it.item })
        assertEquals(257, actual.map { it.item.id }.toSet().size)
        val first = f.store.browse(AgentMemoryBrowseRequest())
        val second = f.store.browse(AgentMemoryBrowseRequest(cursor = first.next))
        val back = f.store.browse(AgentMemoryBrowseRequest(cursor = second.previous, backwards = true))
        assertEquals(first.entries, back.entries)
        assertNull(back.previous)
        assertEquals(second.entries, f.store.browse(AgentMemoryBrowseRequest(cursor = back.next)).entries)
    }

    @Test fun timeExtremesAndIdenticalTimestampsRemainPageable() = fixture { f ->
        val times = listOf(Long.MIN_VALUE, -1L, 0L, Long.MAX_VALUE)
        f.store.saveItems((0 until 41).map { deletionMemory(it).copy(timestampMillis = times[it % times.size]) })
        assertEquals(f.store.snapshot().activeItems, all(f, AgentMemoryBrowseRequest(limit = 3)).map { it.item })
    }

    @Test fun kindStreamsMergeInGlobalOrderAndCountsMatchFilteredData() = fixture { f ->
        val items = rows(67).mapIndexed { i, item -> item.copy(kind = AgentMemoryKind.entries[i % AgentMemoryKind.entries.size]) }
        f.store.saveItems(items)
        val kinds = AgentMemoryKind.entries.take(2).toSet()
        val actual = all(f, AgentMemoryBrowseRequest(kinds = kinds, limit = 4))
        assertEquals(f.store.snapshot().activeItems.filter { it.kind in kinds }, actual.map { it.item })
        assertEquals(actual.size.toLong(), f.store.browseCounts(kinds).active)
        assertEquals(items.groupingBy { it.kind }.eachCount().mapValues { it.value.toLong() }, f.store.browseKindCounts())
    }

    @Test fun cursorsAreBoundToRevisionFiltersAndDatabase() = fixture { f ->
        f.store.saveItems(rows(7))
        val first = f.store.browse(AgentMemoryBrowseRequest(limit = 2))
        assertNotNull(runCatching { f.store.browse(AgentMemoryBrowseRequest(section = AgentMemorySection.HISTORY, cursor = first.next)) }.exceptionOrNull())
        fixture { other ->
            other.store.saveItems(rows(7))
            assertNotNull(runCatching { other.store.browse(AgentMemoryBrowseRequest(cursor = first.next)) }.exceptionOrNull())
        }
        f.store.setImportant("memory-1", true)
        assertTrue(runCatching { f.store.browse(AgentMemoryBrowseRequest(cursor = first.next)) }.exceptionOrNull() is AgentMemoryPageChanged)
    }

    @Test fun activeHistoryAndConflictGroupsHaveIndependentPagesAndCounts() = fixture { f ->
        f.store.saveItems(rows(11) + rows(23).map { it.copy(id = "history-${it.id}", status = AgentMemoryStatus.SUPERSEDED) })
        repeat(9) { group -> repeat(3) { member ->
            f.store.remember(deletionMemory(100 + group * 3 + member).copy(key = "conflict-$group", timestampMillis = (member % 2).toLong()))
        } }
        val snapshot = f.store.snapshot()
        val groups = all(f, AgentMemoryBrowseRequest(section = AgentMemorySection.CONFLICTS, limit = 2))
        assertEquals(snapshot.conflicts.map { it.groupId }, groups.map { it.item.conflictGroupId })
        groups.forEach { entry ->
            assertEquals(3L, entry.conflictSize)
            assertEquals(3, f.store.browseConflict(entry.item)!!.candidates.size)
        }
        assertEquals(snapshot.historyItems, all(f, AgentMemoryBrowseRequest(section = AgentMemorySection.HISTORY, limit = 4)).map { it.item })
        assertEquals(AgentMemoryBrowseCounts(11, 9, 23), f.reopen().browseCounts())
        val selected = groups.first().item
        assertNotNull(f.store.resolveConflict(selected.conflictGroupId, selected.id))
        assertEquals(AgentMemoryBrowseCounts(12, 8, 26), f.reopen().browseCounts())
    }

    @Test fun recentUsesIndexedPagingAndNeverReturnsPrivateOrExpiredRows() = fixture { f ->
        val items = rows(137).mapIndexed { i, item -> item.copy(privateMemory = i % 5 == 0, expiresAtMillis = if (i % 3 == 0) 1 else 0) }
        f.store.saveItems(items)
        val expected = f.store.snapshot().activeItems.filter { !it.privateMemory && !it.isExpired(System.currentTimeMillis()) }
        assertEquals(expected.take(8), f.store.recent(8))
        assertEquals(expected, f.store.recent(500))
        assertTrue(f.store.recent(0).isEmpty())
        f.store.setPrivate(expected.first().id, true)
        assertEquals(expected.drop(1).take(8), f.reopen().recent(8))
    }

    @Test fun legacyUnkeyedConflictsRemainOneGroupWithAllCandidates() = fixture { f ->
        f.store.saveItems((0 until 3).map { deletionMemory(it).copy(key = "", status = AgentMemoryStatus.CONFLICTED, conflictGroupId = "legacy-group") })
        val snapshot = f.store.snapshot()
        assertEquals(1, snapshot.conflicts.size)
        val page = f.store.browse(AgentMemoryBrowseRequest(section = AgentMemorySection.CONFLICTS))
        assertEquals(1L, page.counts.conflicts)
        assertEquals(3L, page.entries.single().conflictSize)
        assertEquals(snapshot.conflicts.single().candidates.toSet(), f.store.browseConflict(page.entries.single().item)!!.candidates.toSet())
    }

    @Test fun selectedRowsAreValidatedButUnrelatedBodiesAreNotDecrypted() = fixture { f ->
        f.store.saveItems(rows(51))
        val first = f.store.browse(AgentMemoryBrowseRequest(limit = 3))
        val unrelated = f.store.snapshot().activeItems.last()
        f.store.database.writeString(AgentPersonalMemoryRows.key(unrelated.id), "unreadable unrelated body")
        val query = AgentMemoryBrowseQuery(f.store.database)
        assertEquals(first.entries, query.page(AgentMemoryBrowseRequest(limit = 3)).entries)
        assertEquals(3, query.decryptedRows)
        f.store.database.writeString(AgentPersonalMemoryRows.key(first.entries.first().item.id), "unreadable selected body")
        assertNotNull(runCatching { query.page(AgentMemoryBrowseRequest(limit = 3)) }.exceptionOrNull())
    }

    @Test fun indexTamperingCannotExposeAPrivateBodyAsPublic() = fixture { f ->
        f.store.remember(deletionMemory(1).copy(privateMemory = true))
        f.store.browseCounts()
        f.sql().use { it.execSQL("UPDATE personal_memory_browse SET private=0") }
        assertNotNull(runCatching { f.store.recent(8) }.exceptionOrNull())
    }

    @Test fun failedIndexUpdateRollsBackBodyCountsAndRevision() = fixture { f ->
        f.store.saveItems(rows(4))
        val before = f.store.browse(AgentMemoryBrowseRequest())
        val revision = f.store.database.readString(AgentPersonalMemoryRows.META, "")
        f.sql().use { sql ->
            sql.execSQL("CREATE TRIGGER test_browse_abort BEFORE INSERT ON personal_memory_browse BEGIN SELECT RAISE(ABORT,'browse failure'); END")
            try {
                assertNotNull(runCatching { f.store.setPrivate("memory-1", true) }.exceptionOrNull())
                assertNotNull(runCatching { f.store.remember(deletionMemory(500)) }.exceptionOrNull())
                assertEquals(revision, f.store.database.readString(AgentPersonalMemoryRows.META, ""))
                assertEquals(before, f.reopen().browse(AgentMemoryBrowseRequest()))
            } finally { sql.execSQL("DROP TRIGGER test_browse_abort") }
        }
    }

    @Test fun failedBackfillLeavesNoReadyMarkerOrPartialRowsAndCanRetry() = fixture { f ->
        f.store.saveItems(rows(5))
        val key = AgentPersonalMemoryRows.key("memory-2")
        val original = f.store.database.readString(key, "")
        f.store.database.writeString(key, "invalid")
        assertNotNull(runCatching { f.store.browseCounts() }.exceptionOrNull())
        assertFalse(f.store.database.contains(AgentMemoryBrowseIndex.MARKER))
        f.store.database.writeString(key, original)
        assertEquals(5L, f.reopen().browseCounts().active)
    }

    @Test fun editsDeletionAndScopeRebindKeepIndexesConsistent() = fixture { f ->
        f.store.remember(deletionMemory(1).copy(scope = AgentMemoryScope.CONVERSATION, scopeId = "old"))
        f.store.browseCounts()
        f.store.rebindConversationScope("old", "new")
        val edited = f.store.update("memory-1", "changed")!!.item!!
        assertEquals(AgentMemoryBrowseCounts(1, 0, 1), f.reopen().browseCounts())
        assertTrue(f.store.deleteById(edited.id))
        assertEquals(AgentMemoryBrowseCounts(0, 0, 0), f.reopen().browseCounts())
    }

    @Test fun clearRemovesDerivedMetadataAndAllowsFreshMigration() = fixture { f ->
        f.store.saveItems(rows(8))
        f.store.browseCounts()
        f.store.database.clear()
        f.sql().use { sql -> for (table in listOf(AgentMemoryBrowseIndex.ROWS, AgentMemoryBrowseIndex.GROUPS, AgentMemoryBrowseIndex.COUNTS)) {
            sql.rawQuery("SELECT count(*) FROM $table", null).use { assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0)) }
        } }
        f.reopen().remember(deletionMemory(99))
        assertEquals(1L, f.reopen().browseCounts().active)
    }

    @Test fun sqlUsesACompositeSeekInsteadOfOffsetOrTemporarySorting() = fixture { f ->
        f.store.saveItems(rows(51))
        f.store.browseCounts()
        f.sql().use { sql ->
            val plan = sql.rawQuery("EXPLAIN QUERY PLAN SELECT row_key FROM personal_memory_browse " +
                "WHERE state='ACTIVE' AND (priority,sort_time,position,row_key)>(1,0,0,'') " +
                "ORDER BY priority,sort_time,position,row_key LIMIT 8", null).use { c ->
                buildList { while (c.moveToNext()) add(c.getString(3)) }.joinToString("\n")
            }
            assertTrue(plan, plan.contains("memory_browse_order"))
            assertFalse(plan, plan.contains("TEMP B-TREE"))
        }
    }

    @Test fun warmPagesAndRecentLatencyAtTwoRealCardinalities() {
        for (size in listOf(1_201, 10_001)) fixture { f ->
            f.store.saveItems(rows(size))
            val migration = SystemClock.elapsedRealtimeNanos()
            assertEquals(size.toLong(), f.store.browseCounts().active)
            val migrationMs = (SystemClock.elapsedRealtimeNanos() - migration) / 1_000_000.0
            val pages = mutableListOf<Double>(); val recent = mutableListOf<Double>(); val writes = mutableListOf<Double>()
            val uiPages = mutableListOf<Double>()
            var cursor: AgentMemoryBrowseCursor? = null
            repeat(100) {
                val begin = SystemClock.elapsedRealtimeNanos()
                val page = f.store.browse(AgentMemoryBrowseRequest(cursor = cursor, limit = 8))
                val middle = SystemClock.elapsedRealtimeNanos()
                assertEquals(8, f.store.recent(8).size)
                val end = SystemClock.elapsedRealtimeNanos()
                pages += (middle - begin) / 1_000_000.0; recent += (end - middle) / 1_000_000.0
                cursor = page.next
            }
            repeat(100) {
                val begin = SystemClock.elapsedRealtimeNanos()
                assertEquals(25, f.store.browse(AgentMemoryBrowseRequest()).entries.size)
                uiPages += (SystemClock.elapsedRealtimeNanos() - begin) / 1_000_000.0
            }
            repeat(100) { sample ->
                val begin = SystemClock.elapsedRealtimeNanos()
                f.store.remember(deletionMemory(size + sample))
                writes += (SystemClock.elapsedRealtimeNanos() - begin) / 1_000_000.0
            }
            assertEquals((size + 100).toLong(), f.reopen().browseCounts().active)
            f.sql().use { sql ->
                sql.rawQuery("SELECT count(*) FROM personal_memory_browse", null).use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals((size + 100).toLong(), c.getLong(0))
                }
                sql.rawQuery("SELECT count(*) FROM encrypted_values WHERE storage_key LIKE 'personal-memory:v3:row:%'", null).use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals((size + 100).toLong(), c.getLong(0))
                }
            }
            fun report(values: List<Double>): String {
                val sorted = values.sorted()
                return "p50=${sorted[49]} p95=${sorted[94]} p99=${sorted[98]} max=${sorted.last()} misses100=${values.count { it >= 100 }}"
            }
            Log.i("GalaxySSIMemoryBrowse", "rows=$size samples=100 migrationMs=$migrationMs page8=${report(pages)} recent8=${report(recent)} page25=${report(uiPages)} new=${report(writes)}")
        }
    }
}
