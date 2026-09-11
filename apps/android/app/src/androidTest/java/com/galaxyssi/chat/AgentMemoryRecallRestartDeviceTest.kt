package com.galaxyssi.chat

import android.os.Process
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Run the two methods separately, with host-observed process termination between them. */
@RunWith(AndroidJUnit4::class)
class AgentMemoryRecallRestartDeviceTest {
    private fun fixture() = MemoryDeletionDeviceFixture(InstrumentationRegistry.getArguments()
        .getString("memory_recall_fixture") ?: "20260911-indexed-recall-v1167")

    @Test fun prepareInterruptedIndex() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("memory_recall_restart") == "prepare")
        val f = fixture()
        check(f.store.count() == 0) { "Retained restart fixture already exists; do not overwrite evidence" }
        f.store.saveItems((0 until 129).map { deletionMemory(it, if (it == 128) "nebularouting" else "stored fact $it") })
        f.store.database.remove(AgentMemoryRecallIndex.MARKER)
        val index = AgentMemoryRecallIndex(f.store.database)
        val state = f.store.database.indexedTransaction(index::state)
        assertFalse(index.backfillPage(state.generation, 16))
        val checkpoint = f.store.database.indexedTransaction(index::state)
        assertTrue(checkpoint.cursor.isNotEmpty()); assertFalse(checkpoint.ready)
        f.context.getSharedPreferences("restart-proof", 0).edit().putInt("pid", Process.myPid())
            .putString("generation", checkpoint.generation).putString("cursor", checkpoint.cursor).commit().also { assertTrue(it) }
        Log.i("GalaxySSIRecallRestart", "prepared rows=129 indexed=16 pid=${Process.myPid()}")
    }

    @Test fun resumeAfterProcessRestart() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("memory_recall_restart") == "resume")
        val f = fixture()
        val saved = f.context.getSharedPreferences("restart-proof", 0)
        val originalPid = saved.getInt("pid", -1)
        assertTrue(originalPid > 0); assertNotEquals(originalPid, Process.myPid())
        val index = AgentMemoryRecallIndex(f.store.database)
        val checkpoint = f.store.database.indexedTransaction(index::state)
        assertEquals(saved.getString("generation", ""), checkpoint.generation)
        assertEquals(saved.getString("cursor", ""), checkpoint.cursor)
        assertFalse(checkpoint.ready); assertEquals(129, f.store.count())
        while (!index.backfillPage(checkpoint.generation, 16)) { }
        val query = AgentMemoryRecallQuery(f.store.database)
        assertEquals(listOf("memory-128"), query.search("nebularouting", System.currentTimeMillis(), 8).map { it.id })
        assertTrue(query.usedIndex); assertEquals(1L, query.decryptedRows)
        assertEquals(129, f.reopen().count())
        Log.i("GalaxySSIRecallRestart", "resumed rows=129 decrypted=1 priorPid=$originalPid pid=${Process.myPid()}")
    }
}
