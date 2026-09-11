package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentWorkspaceCommitDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun failedIndexWriteRollsBackRecordAndDoesNotPublishStaleMemory() {
        assertEquals("SM-S9480", Build.MODEL)
        val name = "workspace-atomic-fixture-${UUID.randomUUID()}"
        val store = EncryptedAgentWorkspaceStore(context, name)
        val raw = AgentEncryptedDatabase(context, name)
        try {
            assertTrue(store.list().isEmpty())
            raw.indexedTransaction { database -> database.execSQL(
                "CREATE TRIGGER reject_fixture_index BEFORE INSERT ON encrypted_values " +
                    "WHEN NEW.storage_key = 'recoverable_workspace_ids_v2' " +
                    "BEGIN SELECT RAISE(ABORT, 'fixture failure'); END") }
            assertThrows(Exception::class.java) { store.upsert(workspace("a")) }
            assertNull(store.find("a"))
            assertEquals("", raw.readString("workspace_v2:a", ""))
            assertEquals(0, JSONArray(raw.readString("workspace_ids_v2", "[]")).length())
            raw.indexedTransaction { it.execSQL("DROP TRIGGER reject_fixture_index") }
            val created = store.upsert(workspace("a"))
            assertEquals(1L, created.revision)
            assertEquals(listOf("a"), store.recoverable().map { it.workspaceId })
            assertEquals(created, AgentWorkspaceJsonCodec.decode(raw.readString("workspace_v2:a", "")))
        } finally {
            raw.indexedTransaction { it.execSQL("DROP TRIGGER IF EXISTS reject_fixture_index") }
            store.clear()
        }
    }

    @Test fun completedTaskAndRecoveryIndexAreUpdatedTogether() {
        assertEquals("SM-S9480", Build.MODEL)
        val name = "workspace-index-fixture-${UUID.randomUUID()}"
        val store = EncryptedAgentWorkspaceStore(context, name)
        val raw = AgentEncryptedDatabase(context, name)
        try {
            val a = store.upsert(workspace("a"))
            store.upsert(workspace("b"))
            val completed = store.upsert(a.copy(status = AgentWorkspaceStatus.COMPLETED), a.revision)
            assertEquals(listOf("b"), store.recoverable().map { it.workspaceId })
            val durableIds = JSONArray(raw.readString("recoverable_workspace_ids_v2", "[]"))
            assertEquals(listOf("b"), (0 until durableIds.length()).map(durableIds::getString))
            assertEquals(completed, AgentWorkspaceJsonCodec.decode(raw.readString("workspace_v2:a", "")))
            assertEquals(2, store.list().size)
        } finally { store.clear() }
    }

    private fun workspace(id: String) = AgentWorkspace(id, "session-$id", "conversation-$id", "task-$id",
        status = AgentWorkspaceStatus.RUNNING)
}
