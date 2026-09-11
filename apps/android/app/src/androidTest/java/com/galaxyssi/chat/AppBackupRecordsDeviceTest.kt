package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AppBackupRecordsDeviceTest {
    private val password = "fixture-only-passphrase".toCharArray()
    private fun fixture(block: (MemoryDeletionDeviceFixture) -> Unit) {
        val f = MemoryDeletionDeviceFixture()
        try { block(f) } finally { f.clear() }
    }
    private fun file(f: MemoryDeletionDeviceFixture) = File(f.context.cacheDir, "${UUID.randomUUID()}.hcbak")
    private val arrays = setOf("knowledge", "tasks", "transcript", "agent_conversations", "workflows", "workflow_schedules",
        "workflow_triggers", "workflow_execution_history", "custom_device_connectors")
    private fun value(section: String, key: String): Any = when {
        section == "agent-field" && key == "version" -> 33
        section == "agent-field" && key in setOf("interface_language", "agent_preference_mode", "active_agent_conversation") -> "fixture-$key"
        section == "agent-field" && key in arrays || section == "app-field" && key in setOf("contacts", "friend_requests") ->
            JSONArray().put(JSONObject().put("fixture", key))
        else -> JSONObject().put("fixture", key)
    }
    private fun export(f: MemoryDeletionDeviceFixture, file: File, contacts: Boolean = true, messages: Boolean = true) {
        val expected = AppBackupFields.expected(contacts, messages)
        AppBackupRecords(f.context).export(file, password, contacts, messages,
            appFields = { emit -> expected.filter { it.first == "app-field" }.forEach { emit(it.second, value(it.first, it.second)) } },
            agentFields = { emit -> expected.filter { it.first == "agent-field" }.forEach { emit(it.second, value(it.first, it.second)) } })
    }

    @Test fun appArchiveRoundTripsPersonalMemoryAndDispatchesAllOtherFields() = fixture { f ->
        val input = (0 until 137).map { deletionMemory(it) }
        f.store.saveItems(input)
        val file = file(f)
        try {
            export(f, file)
            f.store.saveItems(listOf(deletionMemory(999)))
            val received = mutableSetOf<Pair<String, String>>()
            var completed = false
            fun accept(section: String, key: String, item: Any) {
                assertTrue(received.add(section to key))
                assertEquals(value(section, key).toString(), item.toString())
            }
            AppBackupRecords(f.context).restore(file, password, true,
                { key, item -> accept("app-field", key, item) }, { key, item -> accept("agent-field", key, item) }, { completed = true })
            assertEquals(AppBackupFields.expected(true, true), received)
            assertTrue(completed)
            assertEquals(input, f.reopen().loadItems())
        } finally { file.delete() }
    }

    @Test fun skippedMessageRestoreDoesNotSkipMemoryOrOtherFields() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val file = file(f)
        try {
            export(f, file)
            f.store.saveItems(emptyList())
            val received = mutableSetOf<String>()
            AppBackupRecords(f.context).restore(file, password, false, { key, _ -> received.add(key) }, { _, _ -> }, {})
            assertFalse("messages" in received)
            assertTrue("contacts" in received)
            assertEquals(listOf(deletionMemory(1)), f.reopen().loadItems())
        } finally { file.delete() }
    }

    @Test fun corruptAppArchiveHasNoLiveRestoreCallbacksAndDoesNotChangeMemory() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val file = file(f)
        try {
            export(f, file)
            val original = file.readBytes()
            f.store.saveItems(listOf(deletionMemory(2)))
            for (broken in listOf(original.copyOf(original.size - 1), original.copyOf().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() })) {
                file.writeBytes(broken)
                var called = false
                assertNotNull(runCatching { AppBackupRecords(f.context).restore(file, password, true,
                    { _, _ -> called = true }, { _, _ -> called = true }, { called = true }) }.exceptionOrNull())
                assertFalse(called)
                assertEquals(listOf(deletionMemory(2)), f.reopen().loadItems())
                assertTrue(File(f.context.cacheDir, "app-backup-staging").listFiles().orEmpty().isEmpty())
                assertTrue(File(f.context.cacheDir, "memory-backup-staging").listFiles().orEmpty().isEmpty())
            }
        } finally { file.delete() }
    }

    @Test fun authenticatedButIncompleteOrDuplicateFieldsAreRejectedBeforeMutation() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(9)))
        for (duplicate in listOf(false, true)) {
            val file = file(f)
            try {
                StreamingBackupArchive.write(file, password) { w ->
                    w.json("app", "begin", JSONObject().put("schema", 1).put("contacts", false).put("messages", false))
                    w.json("app-field", "profile", JSONObject().put("value", JSONObject()))
                    if (duplicate) w.json("app-field", "profile", JSONObject().put("value", JSONObject()))
                    EncryptedAgentMemoryDeletionIndex(f.context).exportRecords(w)
                    w.json("app", "end", JSONObject().put("fields", 1))
                }
                assertNotNull(runCatching { AppBackupRecords(f.context).restore(file, password, true,
                    { _, _ -> fail("Applied incomplete backup") }, { _, _ -> fail() }, { fail() }) }.exceptionOrNull())
                assertEquals(listOf(deletionMemory(9)), f.reopen().loadItems())
            } finally { file.delete() }
        }
    }

    @Test fun metadataFieldStagingEncryptsLargeLegacyFieldsAndCleansUp() = fixture { f ->
        val text = "fixture-private-".repeat(180_000)
        val encoded = JSONObject().put("value", JSONObject().put("text", text)).toString()
        BackupFieldStaging(f.context).use { stage ->
            stage.accept("app-field", "messages", encoded.byteInputStream())
            val directory = File(f.context.cacheDir, "app-backup-staging").listFiles()!!.single()
            val encrypted = directory.listFiles()!!.single()
            assertTrue(encrypted.length() > 2_000_000L)
            val head = ByteArray(4096)
            encrypted.inputStream().use { java.io.DataInputStream(it).readFully(head) }
            assertFalse(String(head, Charsets.ISO_8859_1).contains("fixture-private"))
            stage.visit { section, key, item ->
                assertEquals("app-field", section); assertEquals("messages", key)
                assertEquals(text, (item as JSONObject).getString("text"))
            }
        }
        assertTrue(File(f.context.cacheDir, "app-backup-staging").listFiles().orEmpty().isEmpty())
    }

    @Test fun nonMemoryRestoreDoesNotFallBackToWholeMemoryNormalization() = fixture { f ->
        f.store.saveItems(listOf(deletionMemory(1)))
        val meta = f.store.database.readString(AgentPersonalMemoryRows.META, "")
        f.store.database.writeString(AgentPersonalMemoryRows.META, "unreadable-fixture-metadata")
        try {
            AgentBackupData.restoreNonMemoryFields(f.context, JSONObject().put("version", 33))
            assertEquals("unreadable-fixture-metadata", f.store.database.readString(AgentPersonalMemoryRows.META, ""))
        } finally { f.store.database.writeString(AgentPersonalMemoryRows.META, meta) }
        assertEquals(listOf(deletionMemory(1)), f.reopen().loadItems())
    }
}
