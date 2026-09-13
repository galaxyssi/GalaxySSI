package com.galaxyssi.chat

import android.system.Os
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KnowledgePrimaryReadConnectionsDeviceTest {
    @Test fun repeatedReadsReuseOneConnectionWithoutRetainingBindings() = KnowledgePrimaryCompactionFixture(records = 1024).use { f ->
        f.transaction { repeat(128) { f.put(it, "\u5bc6\u6587\u8bb0\u5fc6-$it") } }
        val before = KnowledgePrimaryReadConnections.stats()
        repeat(2) { for (i in 0..127) assertEquals("\u5bc6\u6587\u8bb0\u5fc6-$i", f.parts.read(f.db, f.key(i))) }
        val after = KnowledgePrimaryReadConnections.stats()
        assertEquals(1L, after.opened - before.opened); assertEquals(255L, after.reused - before.reused)
        assertTrue(after.peak <= 8); assertEquals(0, after.active)
    }

    @Test fun manyPartitionsKeepFixedCapacityAndEvictedFilesRemainReadable() = KnowledgePrimaryCompactionFixture(records = 1).use { f ->
        f.transaction { repeat(24) { f.put(it) } }
        val before = KnowledgePrimaryReadConnections.stats()
        repeat(2) { for (i in 0..23) assertEquals("\u8bb0\u5fc6-$i", f.parts.read(f.db, f.key(i))) }
        val after = KnowledgePrimaryReadConnections.stats()
        assertTrue(after.evicted > before.evicted); assertTrue(after.peak <= 8)
        assertTrue(after.idle <= 8); assertEquals(0, after.active)
    }

    @Test fun activeWriterReadDoesNotBorrowACommittedReader() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1, "\u65e7\u5185\u5bb9") }
        assertEquals("\u65e7\u5185\u5bb9", f.parts.read(f.db, f.key(1)))
        val before = KnowledgePrimaryReadConnections.stats()
        f.transaction(commit = false) { f.put(1, "\u672a\u63d0\u4ea4"); assertEquals("\u672a\u63d0\u4ea4", f.parts.read(f.db, f.key(1))) }
        assertEquals(before, KnowledgePrimaryReadConnections.stats())
        assertEquals("\u65e7\u5185\u5bb9", f.parts.read(f.db, f.key(1)))
        f.transaction { f.put(1, "\u65b0\u5185\u5bb9") }
        assertEquals("\u65b0\u5185\u5bb9", f.parts.read(f.db, f.key(1)))
    }

    @Test fun missingFileCannotReadAnUnlinkedCachedHandle() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
        val file = File(f.root, "${f.source(1)}.sqlite"); val held = File(f.root, "${file.name}.held")
        assertTrue(file.renameTo(held))
        try { assertThrows(Exception::class.java) { f.parts.read(f.db, f.key(1)) } }
        finally { assertTrue(held.renameTo(file)) }
        assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
    }

    @Test fun replacementInodeIsReopenedAndAuthenticated() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; f.parts.read(f.db, f.key(1))
        val file = File(f.root, "${f.source(1)}.sqlite")
        val replacement = File(f.root, "${file.name}.replacement"); val held = File(f.root, "${file.name}.held")
        file.copyTo(replacement)
        KnowledgeSqlite(replacement.absolutePath).use { it.execSQL("UPDATE frames SET ciphertext='corrupted'") }
        assertTrue(file.renameTo(held)); assertTrue(replacement.renameTo(file))
        try { assertThrows(Exception::class.java) { f.parts.read(f.db, f.key(1)) } }
        finally { assertTrue(file.renameTo(replacement)); assertTrue(held.renameTo(file)) }
        assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
    }

    @Test fun externalCorruptionIsNotHiddenByAnIdleReadTransaction() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; f.parts.read(f.db, f.key(1))
        KnowledgeSqlite(File(f.root, "${f.source(1)}.sqlite").absolutePath).use { it.execSQL("UPDATE frames SET ciphertext='corrupted'") }
        assertThrows(Exception::class.java) { f.parts.read(f.db, f.key(1)) }
        assertEquals(0, KnowledgePrimaryReadConnections.stats().active)
    }

    @Test fun retirementClosesCachedConnectionsBeforeUnlink() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; f.parts.read(f.db, f.key(1))
        val file = File(f.root, "${f.source(1)}.sqlite")
        f.transaction { f.db.delete("knowledge_items", null, null) }
        f.drain(); assertFalse(file.exists())
        assertEquals(0, KnowledgePrimaryReadConnections.stats().active)
    }

    @Test fun symlinkCannotReuseThePreviouslyCachedFile() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; f.parts.read(f.db, f.key(1))
        val file = File(f.root, "${f.source(1)}.sqlite"); val held = File(f.root, "${file.name}.held")
        assertTrue(file.renameTo(held)); Os.symlink(held.absolutePath, file.absolutePath)
        try { assertThrows(Exception::class.java) { f.parts.read(f.db, f.key(1)) } }
        finally { assertTrue(file.delete()); assertTrue(held.renameTo(file)) }
        assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
    }

    @Test fun runtimeTrimClosesIdleCacheWithoutLosingStoredRecords() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; f.parts.read(f.db, f.key(1))
        val before = KnowledgePrimaryReadConnections.stats()
        assertTrue(before.idle > 0)
        KnowledgeSemanticSearch.clearRuntime()
        val deadline = android.os.SystemClock.elapsedRealtime() + 5000
        while (KnowledgePrimaryReadConnections.stats().idle > 0 && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(5)
        assertEquals(0, KnowledgePrimaryReadConnections.stats().idle)
        assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
        assertEquals(before.opened + 1, KnowledgePrimaryReadConnections.stats().opened)
    }

    @Test fun equivalentRootPathsShareTheSamePhysicalConnection() = KnowledgePrimaryCompactionFixture().use { f ->
        f.transaction { f.put(1) }; f.parts.read(f.db, f.key(1))
        val before = KnowledgePrimaryReadConnections.stats()
        val alias = File(f.root, "../${f.root.name}")
        KnowledgePrimaryPartitions(f.context, alias, f.name).use { parts ->
            assertEquals("\u8bb0\u5fc6-1", parts.read(f.db, f.key(1)))
            assertEquals(before.opened, KnowledgePrimaryReadConnections.stats().opened)
            assertEquals(before.reused + 1, KnowledgePrimaryReadConnections.stats().reused)
        }
        assertEquals("\u8bb0\u5fc6-1", f.parts.read(f.db, f.key(1)))
    }
}
